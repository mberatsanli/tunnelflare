//
//  TunnelRunner.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - TunnelRunner

/// Manages the execution of a single cloudflared tunnel process.
///
/// TunnelRunner handles:
/// - Starting cloudflared with a tunnel token
/// - Capturing stdout/stderr output via Pipes
/// - Tracking process state (PID, status)
/// - Handling process termination
/// - Graceful stop (SIGTERM, then SIGKILL after timeout)
/// - Restart functionality
///
/// ## Usage
/// ```swift
/// let runner = TunnelRunner(
///     tunnelId: "my-tunnel",
///     token: "eyJ...",
///     binaryPath: URL(fileURLWithPath: "/path/to/cloudflared")
/// )
///
/// // Start the tunnel
/// try await runner.start()
///
/// // Stream logs
/// for await log in runner.logStream {
///     print(log)
/// }
///
/// // Stop the tunnel
/// await runner.stop()
/// ```
actor TunnelRunner {

    // MARK: - Types

    /// How the cloudflared process is run.
    enum Mode: Sendable {
        /// A named tunnel authenticated with a tunnel token (`tunnel run --token`).
        case namedTunnel(token: String)

        /// An ephemeral quick tunnel proxying a local URL (`tunnel --url`).
        /// The public trycloudflare.com URL is parsed from process output.
        case quickTunnel(localURL: String)
    }

    /// Events emitted by the tunnel runner.
    enum Event: Sendable {
        case started(pid: Int32)
        case stopped
        case terminated(exitCode: Int32, reason: TerminationReason)
        case outputReceived(String)
        case errorReceived(String)
        case healthChanged(HealthStatus)
        case publicURLDiscovered(URL)
    }

    /// Reason for process termination.
    enum TerminationReason: Sendable {
        case graceful
        case killed
        case crashed
        case unknown
    }

    /// Health status of the tunnel.
    enum HealthStatus: Sendable, Equatable {
        case unknown
        case connecting
        case connected
        case disconnected
        case error(String)
    }

    // MARK: - Properties

    /// The tunnel ID this runner manages.
    let tunnelId: String

    /// The mode the cloudflared process runs in.
    private let mode: Mode

    /// Path to the cloudflared binary.
    private let binaryPath: URL

    /// The public trycloudflare.com URL, once discovered (quick tunnel mode only).
    private(set) var publicURL: URL?

    /// The running process, if any.
    private var process: Process?

    /// Current state of the runner.
    private(set) var state: TunnelRunState = .stopped

    /// Current health status.
    private(set) var healthStatus: HealthStatus = .unknown

    /// Time when the tunnel was started.
    private(set) var startedAt: Date?

    /// Event stream for tunnel events.
    private var eventContinuation: AsyncStream<Event>.Continuation?

    /// Logger for tunnel operations.
    private let logger = Logger.process

    /// Pipe for capturing stdout.
    private var stdoutPipe: Pipe?

    /// Pipe for capturing stderr.
    private var stderrPipe: Pipe?

    /// Graceful shutdown timeout in seconds.
    private let gracefulShutdownTimeout: TimeInterval

    // MARK: - Initialization

    /// Creates a new TunnelRunner for a named tunnel.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the tunnel to run.
    ///   - token: The tunnel authentication token.
    ///   - binaryPath: The path to the cloudflared binary.
    ///   - gracefulShutdownTimeout: Time to wait for graceful shutdown before SIGKILL.
    init(
        tunnelId: String,
        token: String,
        binaryPath: URL,
        gracefulShutdownTimeout: TimeInterval = CloudflaredConstants.gracefulShutdownTimeout
    ) {
        self.init(
            tunnelId: tunnelId,
            mode: .namedTunnel(token: token),
            binaryPath: binaryPath,
            gracefulShutdownTimeout: gracefulShutdownTimeout
        )
    }

    /// Creates a new TunnelRunner with an explicit mode.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the tunnel to run.
    ///   - mode: How the cloudflared process should run.
    ///   - binaryPath: The path to the cloudflared binary.
    ///   - gracefulShutdownTimeout: Time to wait for graceful shutdown before SIGKILL.
    init(
        tunnelId: String,
        mode: Mode,
        binaryPath: URL,
        gracefulShutdownTimeout: TimeInterval = CloudflaredConstants.gracefulShutdownTimeout
    ) {
        self.tunnelId = tunnelId
        self.mode = mode
        self.binaryPath = binaryPath
        self.gracefulShutdownTimeout = gracefulShutdownTimeout
    }

    // MARK: - Public Methods

    /// Starts the tunnel process.
    ///
    /// - Throws: `CloudflaredError` if the process fails to start.
    func start() async throws {
        guard state == .stopped || state.errorMessage != nil else {
            logger.warning("Cannot start tunnel \(self.tunnelId): already running or transitioning")
            return
        }

        logger.info("Starting tunnel: \(self.tunnelId)")
        state = .starting

        // Create the process
        let newProcess = Process()
        newProcess.executableURL = binaryPath
        newProcess.arguments = buildArguments()

        // Set up pipes for output capture
        let stdout = Pipe()
        let stderr = Pipe()
        newProcess.standardOutput = stdout
        newProcess.standardError = stderr
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        // Set up termination handler
        newProcess.terminationHandler = { [weak self] terminatedProcess in
            Task {
                await self?.handleTermination(terminatedProcess)
            }
        }

        // Start capturing output
        setupOutputCapture(stdout: stdout, stderr: stderr)

        do {
            try newProcess.run()
            self.process = newProcess
            self.startedAt = Date()

            let pid = newProcess.processIdentifier
            state = .running(pid: pid, startedAt: startedAt!)
            healthStatus = .connecting

            logger.info("Tunnel \(self.tunnelId) started with PID \(pid)")
            eventContinuation?.yield(.started(pid: pid))

        } catch {
            logger.error("Failed to start tunnel \(self.tunnelId): \(error.localizedDescription)")
            state = .error("Failed to start: \(error.localizedDescription)")
            throw CloudflaredError.startFailed(error.localizedDescription)
        }
    }

    /// Stops the tunnel process gracefully.
    ///
    /// Sends SIGTERM first, waits for graceful shutdown timeout, then SIGKILL if needed.
    func stop() async {
        guard let runningProcess = process, runningProcess.isRunning else {
            logger.info("Tunnel \(self.tunnelId) is not running")
            state = .stopped
            return
        }

        logger.info("Stopping tunnel \(self.tunnelId) (PID: \(runningProcess.processIdentifier))")
        state = .stopping

        // Send SIGTERM for graceful shutdown
        runningProcess.terminate()

        // Wait for graceful shutdown
        let gracefulShutdown = await waitForTermination(timeout: gracefulShutdownTimeout)

        if !gracefulShutdown {
            // Force kill if still running
            logger.warning("Tunnel \(self.tunnelId) did not terminate gracefully, sending SIGKILL")
            kill(runningProcess.processIdentifier, SIGKILL)
            _ = await waitForTermination(timeout: 2.0)
        }

        cleanup()
        state = .stopped
        healthStatus = .disconnected

        logger.info("Tunnel \(self.tunnelId) stopped")
        eventContinuation?.yield(.stopped)
    }

    /// Restarts the tunnel.
    func restart() async throws {
        logger.info("Restarting tunnel \(self.tunnelId)")
        await stop()
        try await Task.sleep(for: .milliseconds(500))
        try await start()
    }

    /// Creates an async stream of tunnel events.
    ///
    /// - Returns: An async stream of `Event` values.
    func eventStream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                // Cleanup if needed
            }
        }
    }

    /// Gets the current process ID, if running.
    var pid: Int32? {
        process?.processIdentifier
    }

    /// Whether the process is currently running.
    var isRunning: Bool {
        process?.isRunning == true
    }

    // MARK: - Private Methods

    /// Builds the command line arguments for cloudflared.
    private func buildArguments() -> [String] {
        var args: [String] = []

        // Add default arguments
        args.append("tunnel")
        args.append(contentsOf: CloudflaredConstants.defaultArgs)

        switch mode {
        case .namedTunnel(let token):
            // Add run command with token
            args.append("run")
            args.append("--token")
            args.append(token)

        case .quickTunnel(let localURL):
            // Quick tunnel mode: no run command, just the local URL to proxy
            args.append("--url")
            args.append(localURL)
        }

        return args
    }

    /// Sets up output capture from the process pipes.
    private func setupOutputCapture(stdout: Pipe, stderr: Pipe) {
        // Handle stdout
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            Task {
                await self?.handleOutput(output, isError: false)
            }
        }

        // Handle stderr (cloudflared logs to stderr)
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

            Task {
                await self?.handleOutput(output, isError: true)
            }
        }
    }

    /// Handles output from the process.
    private func handleOutput(_ output: String, isError: Bool) {
        // Split into lines and process each
        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            if isError {
                eventContinuation?.yield(.errorReceived(line))
            } else {
                eventContinuation?.yield(.outputReceived(line))
            }

            // Parse the trycloudflare.com URL for quick tunnels
            // (cloudflared prints it in a boxed banner on stderr)
            if case .quickTunnel = mode, publicURL == nil,
               let url = QuickTunnelURLParser.parse(line) {
                publicURL = url
                logger.info("Quick tunnel \(self.tunnelId) URL discovered: \(url.absoluteString)")
                eventContinuation?.yield(.publicURLDiscovered(url))
            }

            // Parse health indicators from logs
            updateHealthFromLog(line)
        }
    }

    /// Waits for the public trycloudflare.com URL to be discovered (quick tunnel mode).
    ///
    /// - Parameter timeout: Maximum time to wait for the URL.
    /// - Returns: The public URL.
    /// - Throws: `CloudflaredError.quickTunnelURLTimeout` if the URL is not
    ///   discovered in time, or `CloudflaredError.processTerminated` if the
    ///   process exits before printing it.
    func waitForPublicURL(timeout: TimeInterval = QuickTunnelConstants.urlDiscoveryTimeout) async throws -> URL {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let url = publicURL {
                return url
            }

            // Bail out early if the process died before printing the URL
            if case .error = state {
                throw CloudflaredError.processTerminated(
                    exitCode: process?.terminationStatus ?? -1
                )
            }
            if state == .stopped {
                throw CloudflaredError.processTerminated(exitCode: 0)
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        throw CloudflaredError.quickTunnelURLTimeout
    }

    /// Updates health status based on log content.
    private func updateHealthFromLog(_ line: String) {
        let lowercasedLine = line.lowercased()

        if lowercasedLine.contains("connection registered") ||
           lowercasedLine.contains("registered tunnel connection") ||
           lowercasedLine.contains("connected to") ||
           lowercasedLine.contains("tunnel is healthy") {
            if healthStatus != .connected {
                healthStatus = .connected
                eventContinuation?.yield(.healthChanged(.connected))
            }
        } else if lowercasedLine.contains("connection lost") ||
                  lowercasedLine.contains("disconnected") ||
                  lowercasedLine.contains("retrying connection") {
            if healthStatus != .disconnected {
                healthStatus = .disconnected
                eventContinuation?.yield(.healthChanged(.disconnected))
            }
        } else if lowercasedLine.contains("error") ||
                  lowercasedLine.contains("failed") {
            let errorMessage = extractErrorMessage(from: line)
            healthStatus = .error(errorMessage)
            eventContinuation?.yield(.healthChanged(.error(errorMessage)))
        }
    }

    /// Extracts an error message from a log line.
    private func extractErrorMessage(from line: String) -> String {
        // Try to extract message after "error=" or "error:"
        if let range = line.range(of: "error=") ?? line.range(of: "error:") {
            let message = String(line[range.upperBound...])
                .trimmingCharacters(in: .whitespaces)
            return message.isEmpty ? "Unknown error" : message
        }
        return "Unknown error"
    }

    /// Handles process termination.
    private func handleTermination(_ terminatedProcess: Process) {
        let exitCode = terminatedProcess.terminationStatus
        let reason: TerminationReason

        switch terminatedProcess.terminationReason {
        case .exit where exitCode == 0:
            reason = .graceful
        case .exit where state == .stopping:
            reason = .graceful
        case .uncaughtSignal:
            reason = state == .stopping ? .killed : .crashed
        default:
            reason = exitCode == 0 ? .graceful : .crashed
        }

        logger.info("Tunnel \(self.tunnelId) terminated: exitCode=\(exitCode), reason=\(String(describing: reason))")

        // Update state based on reason
        if state == .stopping {
            state = .stopped
        } else if reason == .crashed {
            state = .error("Process crashed with exit code \(exitCode)")
        } else {
            state = .stopped
        }

        healthStatus = .disconnected
        eventContinuation?.yield(.terminated(exitCode: exitCode, reason: reason))
    }

    /// Waits for process termination with timeout.
    ///
    /// - Parameter timeout: Maximum time to wait.
    /// - Returns: True if process terminated within timeout.
    private func waitForTermination(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if process?.isRunning != true {
                return true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        return process?.isRunning != true
    }

    /// Cleans up resources after process termination.
    private func cleanup() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        startedAt = nil
    }

    deinit {
        // Ensure cleanup happens
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
    }
}

// MARK: - TunnelRunner Extensions

extension TunnelRunner {
    /// Gets a snapshot of the current runner state.
    var snapshot: TunnelRunnerSnapshot {
        TunnelRunnerSnapshot(
            tunnelId: tunnelId,
            state: state,
            healthStatus: healthStatus,
            startedAt: startedAt,
            pid: pid
        )
    }
}

/// A snapshot of TunnelRunner state for UI consumption.
struct TunnelRunnerSnapshot: Sendable {
    let tunnelId: String
    let state: TunnelRunState
    let healthStatus: TunnelRunner.HealthStatus
    let startedAt: Date?
    let pid: Int32?

    /// The uptime duration if running.
    var uptime: TimeInterval? {
        guard let startedAt = startedAt else { return nil }
        return Date().timeIntervalSince(startedAt)
    }

    /// Formatted uptime string.
    var formattedUptime: String? {
        guard let uptime = uptime else { return nil }

        if uptime < 60 {
            return "< 1 min"
        } else if uptime < 3600 {
            let minutes = Int(uptime / 60)
            return "\(minutes) min"
        } else if uptime < 86400 {
            let hours = Int(uptime / 3600)
            return "\(hours) hr\(hours == 1 ? "" : "s")"
        } else {
            let days = Int(uptime / 86400)
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }
}
