//
//  ServiceContainer.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - ServiceContainer

/// Container for application services.
///
/// ServiceContainer manages the lifecycle and dependencies of all services:
/// - ProcessManager for tunnel process management
/// - HealthMonitor for connection health tracking
/// - AutoReconnectService for automatic reconnection
/// - LogStreamManager for log capture and streaming
/// - NotificationService for system notifications
///
/// ## Usage
/// ```swift
/// let container = await ServiceContainer.create(
///     apiClient: apiClient,
///     settings: appState.settings
/// )
///
/// // Start services
/// await container.startAll()
///
/// // Access services
/// try await container.processManager.startTunnel(...)
///
/// // Access logs
/// let entries = await container.logStreamManager.getAllEntries()
///
/// // Cleanup on app termination
/// await container.stopAll()
/// ```
actor ServiceContainer {

    // MARK: - Properties

    /// Process manager for tunnel operations.
    let processManager: ProcessManager

    /// Health monitor for connection tracking.
    let healthMonitor: HealthMonitor

    /// Auto-reconnect service for failure recovery.
    let autoReconnectService: AutoReconnectService

    /// Log stream manager for log capture and storage.
    let logStreamManager: LogStreamManager

    /// Log file writer for persisting logs to disk.
    let logFileWriter: LogFileWriter

    /// Notification service for system notifications.
    nonisolated let notificationService: NotificationService

    /// Application settings reference.
    private var settings: AppSettings

    /// API client for tunnel operations.
    private let apiClient: CloudflareAPIClient

    /// Logger for service container operations.
    private let logger = Logger.app

    /// Whether services have been started.
    private(set) var isRunning: Bool = false

    /// Task for processing log events.
    private var logProcessingTask: Task<Void, Never>?

    /// Task for processing health events for notifications.
    private var notificationProcessingTask: Task<Void, Never>?

    /// Tunnel name lookup for notifications.
    private var tunnelNames: [String: String] = [:]

    // MARK: - Initialization

    /// Creates a new ServiceContainer with all services.
    ///
    /// - Parameters:
    ///   - apiClient: The API client for tunnel operations.
    ///   - settings: Application settings.
    ///   - notificationService: The notification service for system notifications.
    private init(
        apiClient: CloudflareAPIClient,
        settings: AppSettings,
        notificationService: NotificationService
    ) {
        // Create process manager
        self.processManager = ProcessManager(apiClient: apiClient, settings: settings)

        // Create health monitor
        self.healthMonitor = HealthMonitor(processManager: processManager)

        // Create auto-reconnect service
        self.autoReconnectService = AutoReconnectService(
            processManager: processManager,
            healthMonitor: healthMonitor,
            settings: settings
        )

        // Create log stream manager
        self.logStreamManager = LogStreamManager()

        // Create log file writer
        self.logFileWriter = LogFileWriter()

        // Store notification service
        self.notificationService = notificationService

        // Store settings
        self.settings = settings

        // Store API client
        self.apiClient = apiClient
    }

    /// Creates a ServiceContainer asynchronously.
    ///
    /// - Parameters:
    ///   - apiClient: The API client for tunnel operations.
    ///   - settings: Application settings.
    ///   - notificationService: The notification service for system notifications.
    /// - Returns: A configured ServiceContainer.
    static func create(
        apiClient: CloudflareAPIClient,
        settings: AppSettings,
        notificationService: NotificationService? = nil
    ) async -> ServiceContainer {
        let notifService = await MainActor.run {
            notificationService ?? NotificationService(settings: settings)
        }
        return ServiceContainer(
            apiClient: apiClient,
            settings: settings,
            notificationService: notifService
        )
    }

    // MARK: - Lifecycle Methods

    /// Starts all services.
    func startAll() async {
        guard !isRunning else {
            logger.warning("Services already running")
            return
        }

        logger.info("Starting all services")

        // Request notification authorization
        await notificationService.requestAuthorization()

        // Start health monitor
        await healthMonitor.startMonitoring()

        // Start auto-reconnect service
        await autoReconnectService.start()

        // Start log processing
        startLogProcessing()

        // Start notification processing
        startNotificationProcessing()

        isRunning = true
        logger.info("All services started")
    }

    /// Stops all services and performs cleanup.
    func stopAll() async {
        guard isRunning else {
            logger.warning("Services not running")
            return
        }

        logger.info("Stopping all services")

        // Stop log processing
        logProcessingTask?.cancel()
        logProcessingTask = nil

        // Stop notification processing
        notificationProcessingTask?.cancel()
        notificationProcessingTask = nil

        // Stop auto-reconnect first
        await autoReconnectService.stop()

        // Stop health monitor
        await healthMonitor.stopMonitoring()

        // Stop all running tunnels
        await processManager.cleanup()

        // Close all log files
        await logFileWriter.closeAll()

        isRunning = false
        logger.info("All services stopped")
    }

    /// Updates settings across all services.
    ///
    /// - Parameter settings: The new settings.
    func updateSettings(_ settings: AppSettings) async {
        self.settings = settings
        await processManager.updateSettings(settings)
        await autoReconnectService.updateFromSettings(settings)
        await notificationService.updateSettings(settings)
    }

    // MARK: - Tunnel Operations

    /// Starts a tunnel and registers it for auto-reconnect.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID.
    ///   - accountId: The account ID.
    ///   - tunnelName: The display name of the tunnel for notifications.
    /// - Throws: `CloudflaredError` or `APIError` if the operation fails.
    func startTunnel(tunnelId: String, accountId: String, tunnelName: String? = nil) async throws {
        // Store tunnel name for notifications
        if let name = tunnelName {
            tunnelNames[tunnelId] = name
        }

        // Register for auto-reconnect
        await autoReconnectService.registerTunnel(tunnelId: tunnelId, accountId: accountId)

        // Start log file (always persisted per-tunnel)
        do {
            try await logFileWriter.startLogging(tunnelId: tunnelId)
        } catch {
            logger.error("Failed to start log file for tunnel \(tunnelId): \(error.localizedDescription)")
        }

        // Start the tunnel
        try await processManager.startTunnel(tunnelId: tunnelId, accountId: accountId)
    }

    /// Stops a tunnel and unregisters it from auto-reconnect.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    func stopTunnel(tunnelId: String) async {
        // Unregister from auto-reconnect
        await autoReconnectService.unregisterTunnel(tunnelId: tunnelId)

        // Stop the tunnel
        await processManager.stopTunnel(tunnelId: tunnelId)

        // Stop log file
        await logFileWriter.stopLogging(tunnelId: tunnelId)

        // Remove pending notifications for this tunnel
        await notificationService.removePendingNotifications(for: tunnelId)
    }

    /// Restarts a tunnel.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID.
    ///   - accountId: The account ID.
    /// - Throws: `CloudflaredError` or `APIError` if the operation fails.
    func restartTunnel(tunnelId: String, accountId: String) async throws {
        try await processManager.restartTunnel(tunnelId: tunnelId, accountId: accountId)
    }

    /// Stops all running tunnels.
    func stopAllTunnels() async {
        await processManager.stopAllTunnels()
    }

    /// Deletes a tunnel completely, including DNS records, local storage, and API deletion.
    ///
    /// This method:
    /// 1. Stops the tunnel if running
    /// 2. Deletes DNS records associated with the tunnel
    /// 3. Deletes from Cloudflare API
    /// 4. Removes token from Keychain
    /// 5. Deletes local storage (config cache + logs)
    /// 6. Deletes from database
    /// 7. Unregisters tunnel name
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID to delete.
    ///   - accountId: The account ID.
    /// - Returns: The result of the deletion including DNS cleanup status.
    /// - Throws: `APIError` if the API deletion fails.
    @discardableResult
    func deleteTunnel(tunnelId: String, accountId: String) async throws -> TunnelDeletionResult {
        logger.info("Deleting tunnel: \(tunnelId)")

        var dnsResult: DNSDeletionResult?

        // 1. Stop the tunnel if running
        await stopTunnel(tunnelId: tunnelId)

        // 2. Delete DNS records (don't throw on failure)
        logger.info("Deleting DNS records for tunnel: \(tunnelId)")
        dnsResult = await apiClient.deleteDNSRecordsForTunnel(accountId: accountId, tunnelId: tunnelId)
        if dnsResult?.hasDeleted == true {
            logger.info("Deleted DNS records: \(dnsResult?.deletedHostnames.joined(separator: ", ") ?? "")")
        }
        if let errors = dnsResult?.errors, !errors.isEmpty {
            for error in errors {
                logger.warning("DNS deletion warning: \(error)")
            }
        }

        // 3. Delete from Cloudflare API
        try await apiClient.deleteTunnel(accountId: accountId, tunnelId: tunnelId)

        // 4. Remove token from Keychain (don't throw on failure)
        do {
            try await KeychainManager.shared.deleteTunnelToken(for: tunnelId)
            logger.info("Deleted Keychain token for tunnel: \(tunnelId)")
        } catch {
            logger.warning("Failed to delete Keychain token for tunnel \(tunnelId): \(error.localizedDescription)")
        }

        // 5. Delete local storage (don't throw on failure)
        do {
            try await TunnelStorageManager.shared.deleteTunnelData(for: tunnelId)
            logger.info("Deleted local storage for tunnel: \(tunnelId)")
        } catch {
            logger.warning("Failed to delete local storage for tunnel \(tunnelId): \(error.localizedDescription)")
        }

        // 6. Delete from database (don't throw on failure)
        do {
            try await TunnelDatabase.shared.deleteTunnel(id: tunnelId)
            logger.info("Deleted database record for tunnel: \(tunnelId)")
        } catch {
            logger.warning("Failed to delete database record for tunnel \(tunnelId): \(error.localizedDescription)")
        }

        // 7. Unregister tunnel name
        unregisterTunnelName(tunnelId: tunnelId)

        logger.info("Tunnel deleted successfully: \(tunnelId)")

        return TunnelDeletionResult(
            tunnelId: tunnelId,
            dnsResult: dnsResult
        )
    }

    // MARK: - Tunnel Name Registration

    /// Registers a tunnel name for use in notifications.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID.
    ///   - name: The display name of the tunnel.
    func registerTunnelName(tunnelId: String, name: String) {
        tunnelNames[tunnelId] = name
    }

    /// Unregisters a tunnel name.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    func unregisterTunnelName(tunnelId: String) {
        tunnelNames.removeValue(forKey: tunnelId)
    }

    /// Gets the registered name for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The tunnel name, or the tunnel ID if no name is registered.
    func getTunnelName(tunnelId: String) -> String {
        tunnelNames[tunnelId] ?? tunnelId
    }

    // MARK: - Status Methods

    /// Gets the status of all tunnels.
    ///
    /// - Returns: A dictionary of tunnel states.
    func getAllTunnelStatus() async -> [String: TunnelRunState] {
        await processManager.getAllStatus()
    }

    /// Gets the health information for all tunnels.
    ///
    /// - Returns: A dictionary of tunnel health information.
    func getAllTunnelHealth() async -> [String: HealthMonitor.TunnelHealth] {
        await healthMonitor.getAllHealth()
    }

    /// Gets the reconnect attempt count for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The number of reconnect attempts.
    func getReconnectAttempts(tunnelId: String) async -> Int {
        await autoReconnectService.getReconnectAttempts(tunnelId: tunnelId)
    }

    // MARK: - Log Methods

    /// Gets log entries for a specific tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: Array of log entries.
    func getLogsForTunnel(_ tunnelId: String) async -> [LogEntry] {
        await logStreamManager.getEntries(for: tunnelId)
    }

    /// Gets all log entries.
    ///
    /// - Returns: Array of all log entries.
    func getAllLogs() async -> [LogEntry] {
        await logStreamManager.getAllEntries()
    }

    /// Clears logs for a specific tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    func clearLogsForTunnel(_ tunnelId: String) async {
        await logStreamManager.clearLogs(for: tunnelId)
    }

    /// Clears all logs.
    func clearAllLogs() async {
        await logStreamManager.clearAllLogs()
    }

    // MARK: - Notification Methods

    /// Sends an authentication expired notification.
    func sendAuthExpiredNotification() async {
        await notificationService.sendAuthExpiredNotification()
    }

    // MARK: - Private Methods

    /// Starts the log processing task.
    private func startLogProcessing() {
        logProcessingTask = Task {
            for await event in await processManager.eventStream() {
                guard !Task.isCancelled else { break }

                switch event {
                case .logReceived(let tunnelId, let line):
                    // Process log for in-memory storage
                    await logStreamManager.processLogLine(line, tunnelId: tunnelId)

                    // Write to file (always persisted per-tunnel)
                    await logFileWriter.writeRawLog(tunnelId: tunnelId, line: line)
                default:
                    break
                }
            }
        }
    }

    /// Starts the notification processing task.
    private func startNotificationProcessing() {
        notificationProcessingTask = Task {
            for await event in await healthMonitor.eventStream() {
                guard !Task.isCancelled else { break }

                let tunnelId: String
                switch event {
                case .connected(let id, _):
                    tunnelId = id
                case .disconnected(let id, _):
                    tunnelId = id
                case .crashed(let id, _):
                    tunnelId = id
                case .reconnecting(let id, _):
                    tunnelId = id
                case .error(let id, _):
                    tunnelId = id
                }

                let tunnelName = getTunnelName(tunnelId: tunnelId)
                await notificationService.processHealthEvent(event, tunnelName: tunnelName)
            }
        }
    }
}

// MARK: - ServiceContainer Events

extension ServiceContainer {
    /// Creates a combined event stream from all services.
    ///
    /// - Returns: An async stream of service events.
    func eventStream() -> AsyncStream<ServiceEvent> {
        AsyncStream { continuation in
            // Note: In a real implementation, we would merge streams from all services
            // For now, we'll just forward process manager events

            Task {
                for await event in await processManager.eventStream() {
                    let serviceEvent: ServiceEvent
                    switch event {
                    case .tunnelStarted(let tunnelId, let pid):
                        serviceEvent = .tunnelStarted(tunnelId: tunnelId, pid: pid)
                    case .tunnelStopped(let tunnelId):
                        serviceEvent = .tunnelStopped(tunnelId: tunnelId)
                    case .tunnelCrashed(let tunnelId, let exitCode):
                        serviceEvent = .tunnelCrashed(tunnelId: tunnelId, exitCode: exitCode)
                    case .tunnelHealthChanged(let tunnelId, let status):
                        serviceEvent = .tunnelHealthChanged(tunnelId: tunnelId, status: status)
                    case .logReceived(let tunnelId, let line):
                        serviceEvent = .logReceived(tunnelId: tunnelId, line: line)
                    }
                    continuation.yield(serviceEvent)
                }
            }
        }
    }
}

/// Events emitted by the service container.
enum ServiceEvent: Sendable {
    case tunnelStarted(tunnelId: String, pid: Int32)
    case tunnelStopped(tunnelId: String)
    case tunnelCrashed(tunnelId: String, exitCode: Int32)
    case tunnelHealthChanged(tunnelId: String, status: TunnelRunner.HealthStatus)
    case logReceived(tunnelId: String, line: String)
    case reconnectScheduled(tunnelId: String, delay: TimeInterval)
    case reconnectSucceeded(tunnelId: String)
    case reconnectFailed(tunnelId: String, error: String)
}

// MARK: - Tunnel Deletion Result

/// Result of a tunnel deletion operation.
struct TunnelDeletionResult: Sendable {
    /// The ID of the deleted tunnel.
    let tunnelId: String

    /// The result of DNS record deletion, if applicable.
    let dnsResult: DNSDeletionResult?

    /// Whether DNS records were successfully deleted.
    var dnsCleanupSucceeded: Bool {
        dnsResult?.success ?? true
    }

    /// Hostnames that had their DNS records deleted.
    var deletedHostnames: [String] {
        dnsResult?.deletedHostnames ?? []
    }

    /// Any DNS deletion errors that occurred.
    var dnsErrors: [String] {
        dnsResult?.errors ?? []
    }
}
