//
//  AutoReconnectService.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - AutoReconnectService

/// Automatically reconnects failed tunnels.
///
/// AutoReconnectService subscribes to health events and:
/// - Automatically restarts crashed tunnels
/// - Implements configurable reconnect delay
/// - Uses exponential backoff on repeated failures
/// - Respects max retry limits
/// - Can be enabled/disabled per user preference
///
/// ## Usage
/// ```swift
/// let reconnectService = AutoReconnectService(
///     processManager: processManager,
///     healthMonitor: healthMonitor
/// )
///
/// // Configure and start
/// reconnectService.configure(
///     enabled: true,
///     initialDelay: 5.0,
///     maxRetries: 5
/// )
///
/// await reconnectService.start()
/// ```
actor AutoReconnectService {

    // MARK: - Types

    /// Configuration for the auto-reconnect service.
    struct Configuration: Sendable {
        /// Whether auto-reconnect is enabled.
        var enabled: Bool = true

        /// Initial delay before attempting reconnect (in seconds).
        var initialDelay: TimeInterval = 5.0

        /// Maximum delay between reconnect attempts (in seconds).
        var maxDelay: TimeInterval = 60.0

        /// Backoff multiplier for exponential backoff.
        var backoffMultiplier: Double = 2.0

        /// Maximum number of retry attempts (0 for unlimited).
        var maxRetries: Int = 10

        /// Whether to reset retry count on successful connection.
        var resetOnSuccess: Bool = true

        /// Default configuration.
        static let `default` = Configuration()

        /// Creates a configuration from app settings.
        static func from(settings: AppSettings) -> Configuration {
            Configuration(
                enabled: settings.autoReconnect,
                initialDelay: TimeInterval(settings.reconnectDelaySeconds)
            )
        }
    }

    /// Events emitted by the auto-reconnect service.
    enum Event: Sendable {
        case reconnectScheduled(tunnelId: String, delay: TimeInterval, attempt: Int)
        case reconnectAttempting(tunnelId: String, attempt: Int)
        case reconnectSucceeded(tunnelId: String)
        case reconnectFailed(tunnelId: String, error: String, attempt: Int)
        case reconnectGaveUp(tunnelId: String, totalAttempts: Int)
        case reconnectCancelled(tunnelId: String)
    }

    /// Reconnect state for a tunnel.
    private struct ReconnectState {
        var tunnelId: String
        var accountId: String
        var attemptCount: Int = 0
        var lastAttemptAt: Date?
        var nextAttemptTask: Task<Void, Never>?
        var currentDelay: TimeInterval
    }

    // MARK: - Properties

    /// Reference to the process manager.
    private weak var processManager: ProcessManager?

    /// Reference to the health monitor.
    private weak var healthMonitor: HealthMonitor?

    /// Current configuration.
    private var configuration: Configuration

    /// Reconnect state for each tunnel.
    private var reconnectStates: [String: ReconnectState] = [:]

    /// Account IDs for each tunnel (needed for restart).
    private var tunnelAccountIds: [String: String] = [:]

    /// Task for monitoring health events.
    private var monitoringTask: Task<Void, Never>?

    /// Event continuation for broadcasting events.
    private var eventContinuation: AsyncStream<Event>.Continuation?

    /// Logger for auto-reconnect operations.
    private let logger = Logger.process

    /// Whether the service is currently running.
    private(set) var isRunning: Bool = false

    // MARK: - Initialization

    /// Creates a new AutoReconnectService.
    ///
    /// - Parameters:
    ///   - processManager: The process manager for tunnel operations.
    ///   - healthMonitor: The health monitor for event subscription.
    ///   - configuration: Initial configuration.
    init(
        processManager: ProcessManager,
        healthMonitor: HealthMonitor,
        configuration: Configuration = .default
    ) {
        self.processManager = processManager
        self.healthMonitor = healthMonitor
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Configures the auto-reconnect service.
    ///
    /// - Parameter configuration: The new configuration.
    func configure(_ configuration: Configuration) {
        self.configuration = configuration

        if !configuration.enabled {
            // Cancel all pending reconnects
            cancelAllPendingReconnects()
        }
    }

    /// Registers a tunnel for auto-reconnect.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID.
    ///   - accountId: The account ID that owns the tunnel.
    func registerTunnel(tunnelId: String, accountId: String) {
        tunnelAccountIds[tunnelId] = accountId
    }

    /// Unregisters a tunnel from auto-reconnect.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    func unregisterTunnel(tunnelId: String) {
        cancelPendingReconnect(tunnelId: tunnelId)
        tunnelAccountIds.removeValue(forKey: tunnelId)
        reconnectStates.removeValue(forKey: tunnelId)
    }

    /// Starts the auto-reconnect service.
    func start() async {
        guard !isRunning else {
            logger.warning("AutoReconnectService already running")
            return
        }

        logger.info("Starting AutoReconnectService")
        isRunning = true

        guard let healthMonitor = healthMonitor else {
            logger.error("HealthMonitor reference is nil")
            return
        }

        monitoringTask = Task {
            let stream = await healthMonitor.eventStream()
            for await event in stream {
                await handleHealthEvent(event)
            }
        }
    }

    /// Stops the auto-reconnect service.
    func stop() {
        logger.info("Stopping AutoReconnectService")
        isRunning = false
        monitoringTask?.cancel()
        monitoringTask = nil
        cancelAllPendingReconnects()
    }

    /// Creates an async stream of auto-reconnect events.
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

    /// Gets the reconnect attempt count for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The number of reconnect attempts.
    func getReconnectAttempts(tunnelId: String) -> Int {
        reconnectStates[tunnelId]?.attemptCount ?? 0
    }

    /// Manually triggers a reconnect attempt for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    func triggerReconnect(tunnelId: String) async {
        guard let accountId = tunnelAccountIds[tunnelId] else {
            logger.warning("No account ID registered for tunnel: \(tunnelId)")
            return
        }

        await attemptReconnect(tunnelId: tunnelId, accountId: accountId)
    }

    /// Resets the reconnect state for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    func resetReconnectState(tunnelId: String) {
        cancelPendingReconnect(tunnelId: tunnelId)
        reconnectStates.removeValue(forKey: tunnelId)
    }

    // MARK: - Private Methods

    /// Handles health events from the monitor.
    private func handleHealthEvent(_ event: HealthMonitor.HealthEvent) async {
        guard configuration.enabled else { return }

        switch event {
        case .crashed(let tunnelId, _):
            await scheduleReconnect(tunnelId: tunnelId)

        case .disconnected(let tunnelId, let reason):
            // Only auto-reconnect for unexpected disconnections
            if reason != .graceful {
                await scheduleReconnect(tunnelId: tunnelId)
            }

        case .connected(let tunnelId, _):
            handleSuccessfulConnection(tunnelId: tunnelId)

        case .reconnecting, .error:
            // Handled by existing reconnect logic
            break
        }
    }

    /// Schedules a reconnect attempt for a tunnel.
    private func scheduleReconnect(tunnelId: String) async {
        guard let accountId = tunnelAccountIds[tunnelId] else {
            logger.warning("No account ID registered for tunnel: \(tunnelId)")
            return
        }

        // Cancel any existing pending reconnect
        cancelPendingReconnect(tunnelId: tunnelId)

        // Get or create reconnect state
        var state = reconnectStates[tunnelId] ?? ReconnectState(
            tunnelId: tunnelId,
            accountId: accountId,
            currentDelay: configuration.initialDelay
        )

        // Check max retries
        if configuration.maxRetries > 0 && state.attemptCount >= configuration.maxRetries {
            logger.warning("Giving up on reconnecting tunnel \(tunnelId) after \(state.attemptCount) attempts")
            eventContinuation?.yield(.reconnectGaveUp(tunnelId: tunnelId, totalAttempts: state.attemptCount))
            reconnectStates.removeValue(forKey: tunnelId)
            return
        }

        // Calculate delay with exponential backoff
        let delay = calculateDelay(for: state)
        state.currentDelay = delay

        logger.info("Scheduling reconnect for tunnel \(tunnelId) in \(delay)s (attempt \(state.attemptCount + 1))")
        eventContinuation?.yield(.reconnectScheduled(tunnelId: tunnelId, delay: delay, attempt: state.attemptCount + 1))

        // Schedule the reconnect
        state.nextAttemptTask = Task {
            do {
                try await Task.sleep(for: .seconds(delay))
                await self.attemptReconnect(tunnelId: tunnelId, accountId: accountId)
            } catch {
                // Task was cancelled
                self.logger.info("Reconnect task cancelled for tunnel \(tunnelId)")
            }
        }

        reconnectStates[tunnelId] = state
    }

    /// Attempts to reconnect a tunnel.
    private func attemptReconnect(tunnelId: String, accountId: String) async {
        guard var state = reconnectStates[tunnelId] else {
            // Create new state if needed
            reconnectStates[tunnelId] = ReconnectState(
                tunnelId: tunnelId,
                accountId: accountId,
                currentDelay: configuration.initialDelay
            )
            return await attemptReconnect(tunnelId: tunnelId, accountId: accountId)
        }

        state.attemptCount += 1
        state.lastAttemptAt = Date()
        reconnectStates[tunnelId] = state

        logger.info("Attempting reconnect for tunnel \(tunnelId) (attempt \(state.attemptCount))")
        eventContinuation?.yield(.reconnectAttempting(tunnelId: tunnelId, attempt: state.attemptCount))

        guard let processManager = processManager else {
            logger.error("ProcessManager reference is nil")
            return
        }

        do {
            try await processManager.startTunnel(tunnelId: tunnelId, accountId: accountId)
            // Success will be handled by handleSuccessfulConnection
        } catch {
            logger.error("Reconnect failed for tunnel \(tunnelId): \(error.localizedDescription)")
            eventContinuation?.yield(.reconnectFailed(
                tunnelId: tunnelId,
                error: error.localizedDescription,
                attempt: state.attemptCount
            ))

            // Schedule another attempt
            await scheduleReconnect(tunnelId: tunnelId)
        }
    }

    /// Handles a successful connection.
    private func handleSuccessfulConnection(tunnelId: String) {
        if configuration.resetOnSuccess {
            if var state = reconnectStates[tunnelId] {
                let attempts = state.attemptCount
                state.attemptCount = 0
                state.currentDelay = configuration.initialDelay
                state.nextAttemptTask = nil
                reconnectStates[tunnelId] = state

                if attempts > 0 {
                    logger.info("Tunnel \(tunnelId) reconnected successfully after \(attempts) attempts")
                    eventContinuation?.yield(.reconnectSucceeded(tunnelId: tunnelId))
                }
            }
        }
    }

    /// Calculates the delay for the next reconnect attempt.
    private func calculateDelay(for state: ReconnectState) -> TimeInterval {
        if state.attemptCount == 0 {
            return configuration.initialDelay
        }

        // Exponential backoff: initialDelay * (multiplier ^ attemptCount)
        let exponentialDelay = configuration.initialDelay * pow(configuration.backoffMultiplier, Double(state.attemptCount))

        // Add jitter (up to 25% of delay)
        let jitter = Double.random(in: 0...0.25) * exponentialDelay

        // Cap at max delay
        return min(exponentialDelay + jitter, configuration.maxDelay)
    }

    /// Cancels a pending reconnect for a tunnel.
    private func cancelPendingReconnect(tunnelId: String) {
        if let state = reconnectStates[tunnelId] {
            state.nextAttemptTask?.cancel()
            eventContinuation?.yield(.reconnectCancelled(tunnelId: tunnelId))
        }
    }

    /// Cancels all pending reconnects.
    private func cancelAllPendingReconnects() {
        for (tunnelId, state) in reconnectStates {
            state.nextAttemptTask?.cancel()
            eventContinuation?.yield(.reconnectCancelled(tunnelId: tunnelId))
        }
        reconnectStates.removeAll()
    }
}

// MARK: - AutoReconnectService Extensions

extension AutoReconnectService {
    /// Creates an AutoReconnectService configured with the given app settings.
    static func create(
        processManager: ProcessManager,
        healthMonitor: HealthMonitor,
        settings: AppSettings
    ) -> AutoReconnectService {
        AutoReconnectService(
            processManager: processManager,
            healthMonitor: healthMonitor,
            configuration: Configuration.from(settings: settings)
        )
    }

    /// Updates configuration from app settings.
    func updateFromSettings(_ settings: AppSettings) {
        configure(Configuration.from(settings: settings))
    }
}
