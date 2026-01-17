//
//  ProcessManager.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - ProcessManager

/// Actor-based coordinator for managing multiple tunnel processes.
///
/// ProcessManager handles:
/// - Tracking all running TunnelRunners
/// - Starting/stopping/restarting tunnels by ID
/// - Getting status of all tunnels
/// - Cleanup on app termination
///
/// ## Usage
/// ```swift
/// let processManager = ProcessManager(
///     apiClient: apiClient,
///     settings: appState.settings
/// )
///
/// // Start a tunnel
/// try await processManager.startTunnel(
///     tunnelId: "my-tunnel",
///     accountId: "account-123"
/// )
///
/// // Get status of all tunnels
/// let status = await processManager.getAllStatus()
/// ```
actor ProcessManager {

    // MARK: - Types

    /// Events emitted by the process manager.
    enum Event: Sendable {
        case tunnelStarted(tunnelId: String, pid: Int32)
        case tunnelStopped(tunnelId: String)
        case tunnelCrashed(tunnelId: String, exitCode: Int32)
        case tunnelHealthChanged(tunnelId: String, status: TunnelRunner.HealthStatus)
        case logReceived(tunnelId: String, line: String)
    }

    // MARK: - Properties

    /// Active tunnel runners, keyed by tunnel ID.
    private var runners: [String: TunnelRunner] = [:]

    /// Event stream tasks for each runner.
    private var eventTasks: [String: Task<Void, Never>] = [:]

    /// Locator for finding the cloudflared binary.
    private let locator: CloudflaredLocator

    /// API client for fetching tunnel tokens.
    private let apiClient: CloudflareAPIClient

    /// Application settings.
    private var settings: AppSettings

    /// Event continuation for broadcasting events.
    private var eventContinuation: AsyncStream<Event>.Continuation?

    /// Logger for process management operations.
    private let logger = Logger.process

    // MARK: - Initialization

    /// Creates a new ProcessManager.
    ///
    /// - Parameters:
    ///   - apiClient: The API client for fetching tunnel tokens.
    ///   - settings: Application settings for configuration.
    init(apiClient: CloudflareAPIClient, settings: AppSettings = .default) {
        self.apiClient = apiClient
        self.settings = settings
        self.locator = CloudflaredLocator(customPath: settings.customCloudflaredPath)
    }

    // MARK: - Public Methods

    /// Starts a tunnel by ID.
    ///
    /// Fetches the tunnel token from the API and starts a new TunnelRunner.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the tunnel to start.
    ///   - accountId: The account ID that owns the tunnel.
    /// - Throws: `CloudflaredError` or `APIError` if the operation fails.
    func startTunnel(tunnelId: String, accountId: String) async throws {
        // Check if already running
        if let existingRunner = runners[tunnelId], await existingRunner.isRunning {
            logger.warning("Tunnel \(tunnelId) is already running")
            return
        }

        logger.info("Starting tunnel: \(tunnelId)")

        // Locate cloudflared binary
        guard let binaryPath = locator.locateBinary() else {
            throw CloudflaredError.binaryNotFound
        }

        // Fetch tunnel token
        let token = try await apiClient.fetchTunnelToken(accountId: accountId, tunnelId: tunnelId)

        // Create and start runner
        let runner = TunnelRunner(
            tunnelId: tunnelId,
            token: token,
            binaryPath: binaryPath
        )

        // Store runner
        runners[tunnelId] = runner

        // Start event streaming
        startEventStreaming(for: tunnelId, runner: runner)

        // Start the tunnel
        try await runner.start()

        if let pid = await runner.pid {
            eventContinuation?.yield(.tunnelStarted(tunnelId: tunnelId, pid: pid))
        }
    }

    /// Stops a tunnel by ID.
    ///
    /// - Parameter tunnelId: The ID of the tunnel to stop.
    func stopTunnel(tunnelId: String) async {
        guard let runner = runners[tunnelId] else {
            logger.warning("No runner found for tunnel: \(tunnelId)")
            return
        }

        logger.info("Stopping tunnel: \(tunnelId)")
        await runner.stop()

        // Cancel event streaming
        eventTasks[tunnelId]?.cancel()
        eventTasks.removeValue(forKey: tunnelId)

        // Remove runner
        runners.removeValue(forKey: tunnelId)

        eventContinuation?.yield(.tunnelStopped(tunnelId: tunnelId))
    }

    /// Restarts a tunnel by ID.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the tunnel to restart.
    ///   - accountId: The account ID that owns the tunnel.
    /// - Throws: `CloudflaredError` or `APIError` if the operation fails.
    func restartTunnel(tunnelId: String, accountId: String) async throws {
        logger.info("Restarting tunnel: \(tunnelId)")
        await stopTunnel(tunnelId: tunnelId)
        try await Task.sleep(for: .milliseconds(500))
        try await startTunnel(tunnelId: tunnelId, accountId: accountId)
    }

    /// Stops all running tunnels.
    func stopAllTunnels() async {
        logger.info("Stopping all tunnels")

        let tunnelIds = Array(runners.keys)
        for tunnelId in tunnelIds {
            await stopTunnel(tunnelId: tunnelId)
        }
    }

    /// Gets the status of a specific tunnel.
    ///
    /// - Parameter tunnelId: The ID of the tunnel.
    /// - Returns: The tunnel run state, or nil if not managed.
    func getStatus(tunnelId: String) async -> TunnelRunState? {
        await runners[tunnelId]?.state
    }

    /// Gets the status of all managed tunnels.
    ///
    /// - Returns: A dictionary mapping tunnel IDs to their states.
    func getAllStatus() async -> [String: TunnelRunState] {
        var status: [String: TunnelRunState] = [:]
        for (tunnelId, runner) in runners {
            status[tunnelId] = await runner.state
        }
        return status
    }

    /// Gets a snapshot of all runners.
    ///
    /// - Returns: An array of runner snapshots.
    func getAllSnapshots() async -> [TunnelRunnerSnapshot] {
        var snapshots: [TunnelRunnerSnapshot] = []
        for runner in runners.values {
            snapshots.append(await runner.snapshot)
        }
        return snapshots
    }

    /// Creates an async stream of process manager events.
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

    /// Updates the settings used by the process manager.
    ///
    /// - Parameter settings: The new settings.
    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
        // Note: Changes to customCloudflaredPath will only affect new tunnel starts
    }

    /// Checks if a tunnel is currently running.
    ///
    /// - Parameter tunnelId: The ID of the tunnel.
    /// - Returns: True if the tunnel is running.
    func isRunning(tunnelId: String) async -> Bool {
        await runners[tunnelId]?.isRunning == true
    }

    /// Gets the runner for a specific tunnel.
    ///
    /// - Parameter tunnelId: The ID of the tunnel.
    /// - Returns: The runner, if it exists.
    func getRunner(tunnelId: String) -> TunnelRunner? {
        runners[tunnelId]
    }

    /// Gets the count of running tunnels.
    var runningCount: Int {
        get async {
            var count = 0
            for runner in runners.values {
                if await runner.isRunning {
                    count += 1
                }
            }
            return count
        }
    }

    // MARK: - Private Methods

    /// Starts event streaming for a runner.
    private func startEventStreaming(for tunnelId: String, runner: TunnelRunner) {
        let task = Task {
            for await event in await runner.eventStream() {
                await handleRunnerEvent(event, tunnelId: tunnelId)
            }
        }
        eventTasks[tunnelId] = task
    }

    /// Handles events from a tunnel runner.
    private func handleRunnerEvent(_ event: TunnelRunner.Event, tunnelId: String) {
        switch event {
        case .started(let pid):
            eventContinuation?.yield(.tunnelStarted(tunnelId: tunnelId, pid: pid))

        case .stopped:
            eventContinuation?.yield(.tunnelStopped(tunnelId: tunnelId))

        case .terminated(let exitCode, let reason):
            if case .crashed = reason {
                eventContinuation?.yield(.tunnelCrashed(tunnelId: tunnelId, exitCode: exitCode))
            } else {
                eventContinuation?.yield(.tunnelStopped(tunnelId: tunnelId))
            }

        case .outputReceived(let line):
            eventContinuation?.yield(.logReceived(tunnelId: tunnelId, line: line))

        case .errorReceived(let line):
            // cloudflared logs to stderr, so this is normal log output
            eventContinuation?.yield(.logReceived(tunnelId: tunnelId, line: line))

        case .healthChanged(let status):
            eventContinuation?.yield(.tunnelHealthChanged(tunnelId: tunnelId, status: status))
        }
    }
}

// MARK: - ProcessManager Cleanup

extension ProcessManager {
    /// Performs cleanup when the app is terminating.
    ///
    /// This should be called from AppDelegate's applicationWillTerminate.
    func cleanup() async {
        logger.info("ProcessManager cleanup: stopping all tunnels")
        await stopAllTunnels()

        // Cancel all event tasks
        for task in eventTasks.values {
            task.cancel()
        }
        eventTasks.removeAll()
        runners.removeAll()
    }
}
