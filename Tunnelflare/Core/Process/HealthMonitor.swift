//
//  HealthMonitor.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - HealthMonitor

/// Monitors the health of tunnel connections.
///
/// HealthMonitor watches for:
/// - Connection/disconnection events in logs
/// - Unexpected process termination
/// - Connection uptime tracking
/// - Health status changes
///
/// ## Log Patterns Monitored
/// - Connection established: "connection registered", "connected to"
/// - Disconnection: "connection lost", "disconnected", "retrying"
/// - Errors: "error", "failed", "ERR"
///
/// ## Usage
/// ```swift
/// let monitor = HealthMonitor(processManager: processManager)
///
/// // Start monitoring
/// await monitor.startMonitoring()
///
/// // Subscribe to health events
/// for await event in monitor.eventStream() {
///     switch event {
///     case .connected(let tunnelId):
///         print("Tunnel \(tunnelId) connected")
///     case .disconnected(let tunnelId, let reason):
///         print("Tunnel \(tunnelId) disconnected: \(reason)")
///     case .crashed(let tunnelId, let exitCode):
///         print("Tunnel \(tunnelId) crashed with exit code \(exitCode)")
///     }
/// }
/// ```
actor HealthMonitor {

    // MARK: - Types

    /// Health events emitted by the monitor.
    enum HealthEvent: Sendable {
        case connected(tunnelId: String, at: Date)
        case disconnected(tunnelId: String, reason: DisconnectReason)
        case crashed(tunnelId: String, exitCode: Int32)
        case reconnecting(tunnelId: String, attempt: Int)
        case error(tunnelId: String, message: String)
    }

    /// Reason for tunnel disconnection.
    enum DisconnectReason: Sendable {
        case graceful
        case connectionLost
        case timeout
        case serverError
        case unknown
    }

    /// Health information for a tunnel.
    struct TunnelHealth: Sendable {
        let tunnelId: String
        var status: TunnelRunner.HealthStatus
        var lastConnectedAt: Date?
        var lastDisconnectedAt: Date?
        var connectionUptime: TimeInterval?
        var reconnectAttempts: Int
        var lastError: String?
    }

    // MARK: - Properties

    /// Reference to the process manager.
    private weak var processManager: ProcessManager?

    /// Health information for each tunnel.
    private var tunnelHealth: [String: TunnelHealth] = [:]

    /// Task for monitoring process manager events.
    private var monitoringTask: Task<Void, Never>?

    /// Event continuation for broadcasting health events.
    private var eventContinuation: AsyncStream<HealthEvent>.Continuation?

    /// Logger for health monitoring.
    private let logger = Logger.process

    // MARK: - Initialization

    /// Creates a new HealthMonitor.
    ///
    /// - Parameter processManager: The process manager to monitor.
    init(processManager: ProcessManager) {
        self.processManager = processManager
    }

    // MARK: - Public Methods

    /// Starts monitoring tunnel health.
    func startMonitoring() async {
        guard monitoringTask == nil else {
            logger.warning("Health monitor already running")
            return
        }

        logger.info("Starting health monitor")

        guard let processManager = processManager else {
            logger.error("ProcessManager reference is nil")
            return
        }

        monitoringTask = Task {
            for await event in await processManager.eventStream() {
                await handleProcessEvent(event)
            }
        }
    }

    /// Stops monitoring tunnel health.
    func stopMonitoring() {
        logger.info("Stopping health monitor")
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    /// Creates an async stream of health events.
    ///
    /// - Returns: An async stream of `HealthEvent` values.
    func eventStream() -> AsyncStream<HealthEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                // Cleanup if needed
            }
        }
    }

    /// Gets the health status for a specific tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The tunnel health information.
    func getHealth(tunnelId: String) -> TunnelHealth? {
        tunnelHealth[tunnelId]
    }

    /// Gets the health status for all monitored tunnels.
    ///
    /// - Returns: A dictionary of tunnel health information.
    func getAllHealth() -> [String: TunnelHealth] {
        tunnelHealth
    }

    /// Gets the connection uptime for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The uptime in seconds, or nil if not connected.
    func getUptime(tunnelId: String) -> TimeInterval? {
        guard let health = tunnelHealth[tunnelId],
              let lastConnected = health.lastConnectedAt,
              health.status == .connected else {
            return nil
        }
        return Date().timeIntervalSince(lastConnected)
    }

    // MARK: - Private Methods

    /// Handles events from the process manager.
    private func handleProcessEvent(_ event: ProcessManager.Event) {
        switch event {
        case .tunnelStarted(let tunnelId, _):
            initializeTunnelHealth(tunnelId)

        case .tunnelStopped(let tunnelId):
            handleTunnelStopped(tunnelId)

        case .tunnelCrashed(let tunnelId, let exitCode):
            handleTunnelCrashed(tunnelId, exitCode: exitCode)

        case .tunnelHealthChanged(let tunnelId, let status):
            handleHealthChanged(tunnelId, status: status)

        case .logReceived(let tunnelId, let line):
            parseLogLine(tunnelId, line: line)
        }
    }

    /// Initializes health tracking for a tunnel.
    private func initializeTunnelHealth(_ tunnelId: String) {
        tunnelHealth[tunnelId] = TunnelHealth(
            tunnelId: tunnelId,
            status: .connecting,
            lastConnectedAt: nil,
            lastDisconnectedAt: nil,
            connectionUptime: nil,
            reconnectAttempts: 0,
            lastError: nil
        )
    }

    /// Handles tunnel stopped event.
    private func handleTunnelStopped(_ tunnelId: String) {
        if var health = tunnelHealth[tunnelId] {
            health.status = .disconnected
            health.lastDisconnectedAt = Date()
            if let lastConnected = health.lastConnectedAt {
                health.connectionUptime = Date().timeIntervalSince(lastConnected)
            }
            tunnelHealth[tunnelId] = health

            eventContinuation?.yield(.disconnected(tunnelId: tunnelId, reason: .graceful))
        }
    }

    /// Handles tunnel crashed event.
    private func handleTunnelCrashed(_ tunnelId: String, exitCode: Int32) {
        if var health = tunnelHealth[tunnelId] {
            health.status = .disconnected
            health.lastDisconnectedAt = Date()
            health.lastError = "Process exited with code \(exitCode)"
            tunnelHealth[tunnelId] = health
        }

        eventContinuation?.yield(.crashed(tunnelId: tunnelId, exitCode: exitCode))
    }

    /// Handles health status change.
    private func handleHealthChanged(_ tunnelId: String, status: TunnelRunner.HealthStatus) {
        guard var health = tunnelHealth[tunnelId] else {
            initializeTunnelHealth(tunnelId)
            return
        }

        let previousStatus = health.status
        health.status = status

        switch status {
        case .connected:
            if previousStatus != .connected {
                health.lastConnectedAt = Date()
                health.reconnectAttempts = 0
                tunnelHealth[tunnelId] = health
                eventContinuation?.yield(.connected(tunnelId: tunnelId, at: Date()))
            }

        case .disconnected:
            if previousStatus == .connected {
                health.lastDisconnectedAt = Date()
                if let lastConnected = health.lastConnectedAt {
                    health.connectionUptime = Date().timeIntervalSince(lastConnected)
                }
                tunnelHealth[tunnelId] = health
                eventContinuation?.yield(.disconnected(tunnelId: tunnelId, reason: .connectionLost))
            }

        case .error(let message):
            health.lastError = message
            tunnelHealth[tunnelId] = health
            eventContinuation?.yield(.error(tunnelId: tunnelId, message: message))

        case .connecting, .unknown:
            tunnelHealth[tunnelId] = health
        }
    }

    /// Parses a log line for health indicators.
    private func parseLogLine(_ tunnelId: String, line: String) {
        let lowercasedLine = line.lowercased()

        // Check for reconnection attempts
        if lowercasedLine.contains("retrying") || lowercasedLine.contains("reconnecting") {
            if var health = tunnelHealth[tunnelId] {
                health.reconnectAttempts += 1
                tunnelHealth[tunnelId] = health
                eventContinuation?.yield(.reconnecting(tunnelId: tunnelId, attempt: health.reconnectAttempts))
            }
        }
    }
}

// MARK: - Connection Statistics

extension HealthMonitor {
    /// Connection statistics for reporting.
    struct ConnectionStatistics: Sendable {
        let tunnelId: String
        let totalUptime: TimeInterval
        let lastConnectedAt: Date?
        let disconnectionCount: Int
        let lastError: String?
    }

    /// Gets connection statistics for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: Connection statistics.
    func getStatistics(tunnelId: String) -> ConnectionStatistics? {
        guard let health = tunnelHealth[tunnelId] else { return nil }

        return ConnectionStatistics(
            tunnelId: tunnelId,
            totalUptime: health.connectionUptime ?? 0,
            lastConnectedAt: health.lastConnectedAt,
            disconnectionCount: health.reconnectAttempts,
            lastError: health.lastError
        )
    }
}
