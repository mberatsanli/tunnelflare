//
//  NotificationService.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import Foundation
import UserNotifications
import os.log

// MARK: - NotificationService

/// Service for managing system notifications for tunnel events.
///
/// NotificationService handles:
/// - Requesting notification authorization
/// - Registering notification categories with actions
/// - Sending notifications for tunnel events (disconnect, reconnect, crash, auth expired)
/// - Processing notification action responses
/// - Respecting user notification preferences
///
/// ## Notification Categories
/// - TUNNEL_DISCONNECT: Actions: Reconnect Now, View Logs
/// - TUNNEL_RECONNECT: Informational only
/// - TUNNEL_CRASH: Actions: Restart, View Logs
/// - AUTH_EXPIRED: Actions: Re-authenticate
///
/// ## Usage
/// ```swift
/// let service = NotificationService(settings: appSettings)
/// await service.requestAuthorization()
///
/// // Send notifications
/// await service.sendDisconnectNotification(tunnelId: "abc", tunnelName: "my-tunnel")
/// await service.sendCrashNotification(tunnelId: "abc", tunnelName: "my-tunnel")
/// ```
@MainActor
final class NotificationService: NSObject {

    // MARK: - Types

    /// Notification events that can be triggered by user actions.
    enum NotificationAction: String, Sendable {
        case reconnect = "RECONNECT"
        case viewLogs = "VIEW_LOGS"
        case restart = "RESTART"
        case reauthenticate = "REAUTHENTICATE"
    }

    /// Events emitted by the notification service when user interacts with notifications.
    enum Event: Sendable {
        case reconnectRequested(tunnelId: String)
        case viewLogsRequested(tunnelId: String)
        case restartRequested(tunnelId: String)
        case reauthenticateRequested
        case notificationTapped(tunnelId: String?)
    }

    /// Delegate protocol for handling notification events.
    protocol Delegate: AnyObject, Sendable {
        func notificationService(_ service: NotificationService, didReceive event: Event) async
    }

    // MARK: - Properties

    /// The notification center.
    private let notificationCenter = UNUserNotificationCenter.current()

    /// Application settings for notification preferences.
    private var settings: AppSettings

    /// Logger for notification operations.
    private let logger = Logger(subsystem: LogConstants.subsystem, category: "notifications")

    /// Delegate for handling notification events.
    weak var delegate: (any Delegate)?

    /// Whether notifications are authorized by the system.
    private(set) var isAuthorized: Bool = false

    /// The authorization status.
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Initialization

    /// Creates a new NotificationService.
    ///
    /// - Parameter settings: Application settings for notification preferences.
    init(settings: AppSettings = .default) {
        self.settings = settings
        super.init()
        notificationCenter.delegate = self
    }

    // MARK: - Authorization

    /// Requests notification authorization from the user.
    ///
    /// This should be called early in the app lifecycle, typically on first launch
    /// or when the user enables notifications in settings.
    ///
    /// - Returns: `true` if authorization was granted, `false` otherwise.
    @discardableResult
    func requestAuthorization() async -> Bool {
        logger.info("Requesting notification authorization")

        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge]
            )

            isAuthorized = granted
            authorizationStatus = granted ? .authorized : .denied

            if granted {
                logger.info("Notification authorization granted")
                registerCategories()
            } else {
                logger.warning("Notification authorization denied")
            }

            return granted

        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }

    /// Checks the current notification authorization status.
    ///
    /// - Returns: The current authorization status.
    func checkAuthorizationStatus() async -> UNAuthorizationStatus {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized
        return settings.authorizationStatus
    }

    // MARK: - Category Registration

    /// Registers all notification categories with their actions.
    private func registerCategories() {
        logger.debug("Registering notification categories")

        // TUNNEL_DISCONNECT category
        let reconnectAction = UNNotificationAction(
            identifier: NotificationAction.reconnect.rawValue,
            title: "Reconnect Now",
            options: [.foreground]
        )
        let viewLogsAction = UNNotificationAction(
            identifier: NotificationAction.viewLogs.rawValue,
            title: "View Logs",
            options: [.foreground]
        )

        let disconnectCategory = UNNotificationCategory(
            identifier: NotificationCategory.tunnelDisconnect,
            actions: [reconnectAction, viewLogsAction],
            intentIdentifiers: [],
            options: []
        )

        // TUNNEL_RECONNECT category (informational only)
        let reconnectCategory = UNNotificationCategory(
            identifier: NotificationCategory.tunnelReconnect,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // TUNNEL_CRASH category
        let restartAction = UNNotificationAction(
            identifier: NotificationAction.restart.rawValue,
            title: "Restart",
            options: [.foreground]
        )

        let crashCategory = UNNotificationCategory(
            identifier: NotificationCategory.tunnelCrash,
            actions: [restartAction, viewLogsAction],
            intentIdentifiers: [],
            options: []
        )

        // AUTH_EXPIRED category
        let reauthenticateAction = UNNotificationAction(
            identifier: NotificationAction.reauthenticate.rawValue,
            title: "Re-authenticate",
            options: [.foreground]
        )

        let authExpiredCategory = UNNotificationCategory(
            identifier: NotificationCategory.authExpired,
            actions: [reauthenticateAction],
            intentIdentifiers: [],
            options: []
        )

        // Register all categories
        notificationCenter.setNotificationCategories([
            disconnectCategory,
            reconnectCategory,
            crashCategory,
            authExpiredCategory
        ])

        logger.info("Notification categories registered")
    }

    // MARK: - Settings Update

    /// Updates the settings used by the notification service.
    ///
    /// - Parameter settings: The new settings.
    func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Tunnel Disconnect Notification

    /// Sends a notification when a tunnel disconnects.
    ///
    /// This notification includes actions to reconnect or view logs.
    /// The notification is sent within 5 seconds of disconnect detection.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the disconnected tunnel.
    ///   - tunnelName: The name of the tunnel for display.
    func sendDisconnectNotification(tunnelId: String, tunnelName: String) async {
        guard shouldSendNotification(forCategory: .disconnect) else {
            logger.debug("Disconnect notification suppressed by settings")
            return
        }

        logger.info("Sending disconnect notification for tunnel: \(tunnelName)")

        let content = UNMutableNotificationContent()
        content.title = "Tunnel Disconnected"
        content.body = "\(tunnelName) has lost connection"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.tunnelDisconnect
        content.userInfo = [
            "tunnelId": tunnelId,
            "tunnelName": tunnelName,
            "eventType": "disconnect"
        ]

        await scheduleNotification(
            identifier: "disconnect-\(tunnelId)-\(Date().timeIntervalSince1970)",
            content: content
        )
    }

    // MARK: - Tunnel Reconnect Notification

    /// Sends a notification when a tunnel reconnects.
    ///
    /// This is an informational notification with no actions.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the reconnected tunnel.
    ///   - tunnelName: The name of the tunnel for display.
    func sendReconnectNotification(tunnelId: String, tunnelName: String) async {
        guard shouldSendNotification(forCategory: .reconnect) else {
            logger.debug("Reconnect notification suppressed by settings")
            return
        }

        logger.info("Sending reconnect notification for tunnel: \(tunnelName)")

        let content = UNMutableNotificationContent()
        content.title = "Tunnel Reconnected"
        content.body = "\(tunnelName) is back online"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.tunnelReconnect
        content.userInfo = [
            "tunnelId": tunnelId,
            "tunnelName": tunnelName,
            "eventType": "reconnect"
        ]

        await scheduleNotification(
            identifier: "reconnect-\(tunnelId)-\(Date().timeIntervalSince1970)",
            content: content
        )
    }

    // MARK: - Tunnel Crash Notification

    /// Sends a notification when a tunnel crashes.
    ///
    /// This notification includes actions to restart or view logs.
    /// It is only sent for unexpected process termination, not graceful stops.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the crashed tunnel.
    ///   - tunnelName: The name of the tunnel for display.
    ///   - exitCode: The exit code of the crashed process.
    func sendCrashNotification(tunnelId: String, tunnelName: String, exitCode: Int32? = nil) async {
        guard shouldSendNotification(forCategory: .crash) else {
            logger.debug("Crash notification suppressed by settings")
            return
        }

        logger.info("Sending crash notification for tunnel: \(tunnelName)")

        let content = UNMutableNotificationContent()
        content.title = "Tunnel Crashed"

        if let exitCode = exitCode {
            content.body = "\(tunnelName) process terminated unexpectedly (exit code: \(exitCode))"
        } else {
            content.body = "\(tunnelName) process terminated unexpectedly"
        }

        content.sound = .default
        content.categoryIdentifier = NotificationCategory.tunnelCrash
        content.userInfo = [
            "tunnelId": tunnelId,
            "tunnelName": tunnelName,
            "eventType": "crash",
            "exitCode": exitCode ?? -1
        ]

        await scheduleNotification(
            identifier: "crash-\(tunnelId)-\(Date().timeIntervalSince1970)",
            content: content
        )
    }

    // MARK: - Auth Expired Notification

    /// Sends a notification when authentication expires.
    ///
    /// This notification includes an action to re-authenticate.
    /// It is sent when token refresh fails.
    func sendAuthExpiredNotification() async {
        guard shouldSendNotification(forCategory: .authExpired) else {
            logger.debug("Auth expired notification suppressed by settings")
            return
        }

        logger.info("Sending auth expired notification")

        let content = UNMutableNotificationContent()
        content.title = "Authentication Expired"
        content.body = "Please log in again to manage tunnels"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.authExpired
        content.userInfo = [
            "eventType": "authExpired"
        ]

        await scheduleNotification(
            identifier: "auth-expired-\(Date().timeIntervalSince1970)",
            content: content
        )
    }

    // MARK: - Private Methods

    /// Checks if a notification should be sent based on user settings.
    ///
    /// - Parameter category: The notification category to check.
    /// - Returns: `true` if the notification should be sent.
    private func shouldSendNotification(forCategory category: NotificationCategoryType) -> Bool {
        // Master toggle
        guard settings.notificationsEnabled else {
            return false
        }

        // Check system authorization
        guard isAuthorized else {
            return false
        }

        // Category-specific toggles
        switch category {
        case .disconnect:
            return settings.notifyOnDisconnect
        case .reconnect:
            return settings.notifyOnReconnect
        case .crash:
            return settings.notifyOnCrash
        case .authExpired:
            // Auth expired notifications are always enabled when master is on
            return true
        }
    }

    /// Schedules a notification for immediate delivery.
    ///
    /// - Parameters:
    ///   - identifier: A unique identifier for the notification.
    ///   - content: The notification content.
    private func scheduleNotification(identifier: String, content: UNNotificationContent) async {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // Deliver immediately
        )

        do {
            try await notificationCenter.add(request)
            logger.debug("Notification scheduled: \(identifier)")
        } catch {
            logger.error("Failed to schedule notification: \(error.localizedDescription)")
        }
    }

    /// Removes pending notifications for a specific tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID to remove notifications for.
    func removePendingNotifications(for tunnelId: String) async {
        let identifierPrefixes = ["disconnect-\(tunnelId)", "crash-\(tunnelId)", "reconnect-\(tunnelId)"]

        let requests = await notificationCenter.pendingNotificationRequests()
        let identifiersToRemove = requests
            .filter { request in
                identifierPrefixes.contains { request.identifier.hasPrefix($0) }
            }
            .map { $0.identifier }

        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }

    /// Removes all delivered notifications.
    func removeAllDeliveredNotifications() {
        notificationCenter.removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification is about to be presented while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show notifications even when app is in foreground
        return [.banner, .sound]
    }

    /// Called when the user interacts with a notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let tunnelId = userInfo["tunnelId"] as? String
        let actionIdentifier = response.actionIdentifier

        await MainActor.run {
            logger.info("Notification response received: \(actionIdentifier)")
        }

        // Handle the action
        switch actionIdentifier {
        case NotificationAction.reconnect.rawValue:
            if let tunnelId = tunnelId {
                await delegate?.notificationService(self, didReceive: .reconnectRequested(tunnelId: tunnelId))
            }

        case NotificationAction.viewLogs.rawValue:
            if let tunnelId = tunnelId {
                await delegate?.notificationService(self, didReceive: .viewLogsRequested(tunnelId: tunnelId))
            }

        case NotificationAction.restart.rawValue:
            if let tunnelId = tunnelId {
                await delegate?.notificationService(self, didReceive: .restartRequested(tunnelId: tunnelId))
            }

        case NotificationAction.reauthenticate.rawValue:
            await delegate?.notificationService(self, didReceive: .reauthenticateRequested)

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification body
            await delegate?.notificationService(self, didReceive: .notificationTapped(tunnelId: tunnelId))

        default:
            break
        }
    }
}

// MARK: - Notification Category Type

/// Internal enum for categorizing notification types.
private enum NotificationCategoryType {
    case disconnect
    case reconnect
    case crash
    case authExpired
}

// MARK: - HealthMonitor Integration

extension NotificationService {

    /// Processes health events from the HealthMonitor.
    ///
    /// This method is called by the ServiceContainer to bridge health events
    /// to notifications.
    ///
    /// - Parameters:
    ///   - event: The health event from HealthMonitor.
    ///   - tunnelName: The display name of the tunnel.
    func processHealthEvent(_ event: HealthMonitor.HealthEvent, tunnelName: String) async {
        switch event {
        case .connected(let tunnelId, _):
            await sendReconnectNotification(tunnelId: tunnelId, tunnelName: tunnelName)

        case .disconnected(let tunnelId, let reason):
            // Only notify for non-graceful disconnects
            if reason != .graceful {
                await sendDisconnectNotification(tunnelId: tunnelId, tunnelName: tunnelName)
            }

        case .crashed(let tunnelId, let exitCode):
            await sendCrashNotification(tunnelId: tunnelId, tunnelName: tunnelName, exitCode: exitCode)

        case .reconnecting:
            // Don't send notification for reconnecting attempts
            break

        case .error(let tunnelId, let message):
            // Treat errors as potential disconnects
            await sendDisconnectNotification(tunnelId: tunnelId, tunnelName: "\(tunnelName): \(message)")
        }
    }
}
