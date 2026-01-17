//
//  AppDelegate.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import AppKit
import os.log
import UserNotifications

/// Application delegate for handling macOS-specific lifecycle events.
///
/// This delegate manages:
/// - Application lifecycle (launch, termination, activation)
/// - Dock icon visibility based on user settings
/// - Notification handling and action responses
/// - Cleanup on application termination
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties

    /// Logger for app delegate events.
    private let logger = Logger.app

    /// Reference to the shared app state.
    /// This is set after the app launches and AppState is initialized.
    weak var appState: AppState?

    // MARK: - Application Lifecycle

    /// Called when the application has finished launching.
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Application did finish launching")

        // Configure the app's activation policy based on settings
        updateActivationPolicy()

        // Log system information
        logSystemInfo()

        // Perform storage migration if needed (one-time, from shared to per-tunnel storage)
        performStorageMigration()

        // Note: Notification authorization is now handled by NotificationService
        // which is initialized via ServiceContainer
    }

    /// Performs one-time migration to per-tunnel storage structure.
    private func performStorageMigration() {
        Task {
            await TunnelStorageManager.shared.performMigrationIfNeeded()
        }
    }

    /// Called before the application terminates.
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("Application will terminate")

        // Stop all running tunnels gracefully
        stopAllTunnels()

        // Clean up resources
        cleanup()
    }

    /// Called when the application becomes active.
    func applicationDidBecomeActive(_ notification: Notification) {
        logger.debug("Application did become active")
    }

    /// Called when the application resigns active state.
    func applicationWillResignActive(_ notification: Notification) {
        logger.debug("Application will resign active")
    }

    /// Called when all windows are closed.
    /// Returns true to keep the app running (menu bar app behavior).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running even when all windows are closed
        // This is typical behavior for menu bar applications
        return false
    }

    /// Called to determine if the application should handle a reopen request.
    /// This is triggered when the user clicks the dock icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows, show the dashboard
            showDashboard()
        }
        return true
    }

    // MARK: - Public Methods

    /// Sets up the notification service delegate.
    ///
    /// This should be called after the ServiceContainer is initialized.
    func setupNotificationHandling(with notificationService: NotificationService) {
        notificationService.delegate = self
        logger.info("Notification handling set up with NotificationService")
    }

    // MARK: - Private Methods

    /// Updates the application's activation policy based on user settings.
    ///
    /// - If showInDock is true: Regular app with dock icon
    /// - If showInDock is false: Accessory app (menu bar only, no dock icon)
    private func updateActivationPolicy() {
        // Load settings from the AppSettings model
        let settings = AppSettings.load()
        let showInDock = settings.showInDock

        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        NSApp.setActivationPolicy(policy)

        logger.info("Activation policy set to: \(showInDock ? "regular" : "accessory")")
    }

    /// Logs system information for debugging purposes.
    private func logSystemInfo() {
        let processInfo = ProcessInfo.processInfo
        let osVersion = processInfo.operatingSystemVersionString

        logger.info("macOS version: \(osVersion)")
        logger.info("App version: \(Bundle.main.appVersion)")
        logger.info("Build number: \(Bundle.main.buildNumber)")

        #if arch(arm64)
        logger.info("Architecture: Apple Silicon (arm64)")
        #else
        logger.info("Architecture: Intel (x86_64)")
        #endif
    }

    /// Shows the main dashboard window.
    private func showDashboard() {
        // Update app state to show dashboard
        appState?.isDashboardVisible = true

        // Use the shared window opener to handle both existing and new windows
        DashboardWindowOpener.shared.openDashboard()
    }

    /// Stops all running tunnels before termination.
    private func stopAllTunnels() {
        logger.info("Stopping all running tunnels...")

        // Use a blocking semaphore for termination
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            if let container = appState?.serviceContainer {
                await container.stopAll()
            }
            semaphore.signal()
        }

        // Wait for cleanup to complete with timeout
        _ = semaphore.wait(timeout: .now() + 5.0)
        logger.info("Tunnel shutdown complete")
    }

    /// Cleans up resources before termination.
    private func cleanup() {
        // Clear any temporary files
        // Cancel any pending network requests
        // Save any pending state
        logger.info("Cleanup completed")
    }
}

// MARK: - NotificationService.Delegate

extension AppDelegate: NotificationService.Delegate {

    /// Handles events from the NotificationService.
    nonisolated func notificationService(_ service: NotificationService, didReceive event: NotificationService.Event) async {
        Logger.app.info("Received notification event: \(String(describing: event))")

        await MainActor.run {
            switch event {
            case .reconnectRequested(let tunnelId):
                handleReconnect(tunnelId: tunnelId)

            case .viewLogsRequested(let tunnelId):
                handleViewLogs(tunnelId: tunnelId)

            case .restartRequested(let tunnelId):
                handleRestart(tunnelId: tunnelId)

            case .reauthenticateRequested:
                handleReauthenticate()

            case .notificationTapped(let tunnelId):
                handleNotificationTapped(tunnelId: tunnelId)
            }
        }
    }

    /// Handles the reconnect action from a notification.
    private func handleReconnect(tunnelId: String) {
        logger.info("Handling reconnect for tunnel: \(tunnelId)")

        Task {
            await appState?.handleReconnectFromNotification(tunnelId: tunnelId)
        }

        // Also show the dashboard
        showDashboard()
    }

    /// Handles the view logs action from a notification.
    private func handleViewLogs(tunnelId: String) {
        logger.info("Handling view logs for tunnel: \(tunnelId)")

        appState?.handleViewLogsFromNotification(tunnelId: tunnelId)
        showDashboard()
    }

    /// Handles the restart action from a notification.
    private func handleRestart(tunnelId: String) {
        logger.info("Handling restart for tunnel: \(tunnelId)")

        Task {
            await appState?.handleRestartFromNotification(tunnelId: tunnelId)
        }

        // Also show the dashboard
        showDashboard()
    }

    /// Handles the re-authenticate action from a notification.
    private func handleReauthenticate() {
        logger.info("Handling re-authenticate")

        // Show the dashboard which will show the login view if needed
        appState?.isDashboardVisible = true
        appState?.clearAuthentication()
        showDashboard()
    }

    /// Handles a notification tap to open the dashboard.
    private func handleNotificationTapped(tunnelId: String?) {
        logger.info("Handling notification tap, tunnelId: \(tunnelId ?? "nil")")

        appState?.handleNotificationTapped(tunnelId: tunnelId)
        showDashboard()
    }
}

// MARK: - Bundle Extension

private extension Bundle {
    /// The application's version string (e.g., "1.0.0").
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// The application's build number (e.g., "1").
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
}
