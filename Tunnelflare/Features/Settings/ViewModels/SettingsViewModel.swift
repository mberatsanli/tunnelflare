//
//  SettingsViewModel.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI
import ServiceManagement
import os.log

// MARK: - SettingsViewModel

/// View model for the Settings view.
///
/// SettingsViewModel manages the settings UI state and coordinates with
/// AppSettingsManager for persistence and system integration.
@Observable
@MainActor
final class SettingsViewModel {

    // MARK: - Properties

    /// Logger for settings operations.
    private let logger = Logger(subsystem: LogConstants.subsystem, category: "settings-vm")

    /// The settings manager.
    private let settingsManager = AppSettingsManager.shared

    // MARK: - General Settings

    /// Whether to launch the app at login.
    var launchAtLogin: Bool {
        get { settingsManager.launchAtLogin }
        set { settingsManager.launchAtLogin = newValue }
    }

    /// Whether to show the app in the Dock.
    var showInDock: Bool {
        get { settingsManager.showInDock }
        set { settingsManager.showInDock = newValue }
    }

    // MARK: - Notification Settings

    /// Whether notifications are enabled.
    var notificationsEnabled: Bool {
        get { settingsManager.notificationsEnabled }
        set { settingsManager.notificationsEnabled = newValue }
    }

    /// Whether disconnect notifications are enabled.
    var notifyOnDisconnect: Bool {
        get { settingsManager.notifyOnDisconnect }
        set { settingsManager.notifyOnDisconnect = newValue }
    }

    /// Whether reconnect notifications are enabled.
    var notifyOnReconnect: Bool {
        get { settingsManager.notifyOnReconnect }
        set { settingsManager.notifyOnReconnect = newValue }
    }

    /// Whether crash notifications are enabled.
    var notifyOnCrash: Bool {
        get { settingsManager.notifyOnCrash }
        set { settingsManager.notifyOnCrash = newValue }
    }

    // MARK: - Tunnel Settings

    /// Whether to automatically reconnect failed tunnels.
    var autoReconnect: Bool {
        get { settingsManager.autoReconnect }
        set { settingsManager.autoReconnect = newValue }
    }

    /// Delay in seconds before attempting to reconnect.
    var reconnectDelaySeconds: Int {
        get { settingsManager.reconnectDelaySeconds }
        set { settingsManager.reconnectDelaySeconds = newValue }
    }

    /// Interval in seconds for refreshing tunnel status.
    var refreshIntervalSeconds: Int {
        get { settingsManager.refreshIntervalSeconds }
        set { settingsManager.refreshIntervalSeconds = newValue }
    }

    // MARK: - Advanced Settings

    /// Custom path to cloudflared binary.
    var customCloudflaredPath: String {
        get { settingsManager.customCloudflaredPath ?? "" }
        set { settingsManager.customCloudflaredPath = newValue.isEmpty ? nil : newValue }
    }

    /// Whether to use a custom cloudflared path.
    var useCustomCloudflaredPath: Bool = false

    // MARK: - Log Settings

    /// How to display log entries.
    var logDisplayMode: LogDisplayMode {
        get { settingsManager.logDisplayMode }
        set { settingsManager.logDisplayMode = newValue }
    }

    // Note: persistLogsToFile removed - logs are always persisted per-tunnel now

    // MARK: - Version Information

    /// The current app version.
    var appVersion: String {
        AppInfo.fullVersion
    }

    /// The cloudflared version.
    var cloudflaredVersion: String = "Checking..."

    /// The path to the cloudflared binary in use.
    var cloudflaredPath: String = ""

    // MARK: - State

    /// Whether version information is loading.
    var isLoadingVersion: Bool = false

    /// Whether a custom path is being validated.
    var isValidatingPath: Bool = false

    /// Custom path validation error.
    var pathValidationError: String?

    /// Whether the path is valid.
    var isPathValid: Bool = false

    /// Whether to show the reset confirmation dialog.
    var showResetConfirmation: Bool = false

    // MARK: - Initialization

    init() {
        // Check if a custom path is configured
        useCustomCloudflaredPath = !customCloudflaredPath.isEmpty
    }

    // MARK: - Public Methods

    /// Loads version information.
    func loadVersionInfo() async {
        isLoadingVersion = true
        defer { isLoadingVersion = false }

        let locator = CloudflaredLocator(customPath: settingsManager.customCloudflaredPath)

        guard let binaryURL = locator.locateBinary() else {
            cloudflaredVersion = "Not found"
            cloudflaredPath = "cloudflared not found"
            return
        }

        cloudflaredPath = binaryURL.path

        do {
            let version = try await locator.getVersion(at: binaryURL)
            cloudflaredVersion = version
        } catch {
            cloudflaredVersion = "Unknown"
            logger.error("Failed to get cloudflared version: \(error.localizedDescription)")
        }
    }

    /// Validates a custom cloudflared path.
    func validateCustomPath(_ path: String) async {
        guard !path.isEmpty else {
            pathValidationError = nil
            isPathValid = false
            return
        }

        isValidatingPath = true
        defer { isValidatingPath = false }

        let url = URL(fileURLWithPath: path)
        let locator = CloudflaredLocator()
        let result = await locator.validate(url)

        if result.isValid {
            pathValidationError = nil
            isPathValid = true
            cloudflaredVersion = result.version ?? "Unknown"
        } else {
            pathValidationError = result.error?.localizedDescription ?? "Invalid path"
            isPathValid = false
        }
    }

    /// Opens a file panel to browse for cloudflared binary.
    func browseForCloudflared() {
        let panel = NSOpenPanel()
        panel.title = "Select cloudflared Binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the cloudflared binary to use"

        if panel.runModal() == .OK, let url = panel.url {
            customCloudflaredPath = url.path

            Task {
                await validateCustomPath(url.path)
            }
        }
    }

    /// Clears the custom cloudflared path.
    func clearCustomPath() {
        customCloudflaredPath = ""
        useCustomCloudflaredPath = false
        pathValidationError = nil
        isPathValid = false

        Task {
            await loadVersionInfo()
        }
    }

    /// Resets all settings to defaults.
    func resetToDefaults() {
        settingsManager.resetToDefaults()
        useCustomCloudflaredPath = false

        Task {
            await loadVersionInfo()
        }

        logger.info("Settings reset to defaults")
    }

    /// Opens the Cloudflare documentation.
    func openDocumentation() {
        NSWorkspace.shared.open(ExternalLinks.documentation)
    }

    /// Opens the Cloudflare dashboard.
    func openCloudflareDashboard() {
        NSWorkspace.shared.open(ExternalLinks.cloudfllareDashboard)
    }

    /// Opens the GitHub repository.
    func openGitHub() {
        NSWorkspace.shared.open(ExternalLinks.gitHub)
    }

    /// Opens the support page.
    func openSupport() {
        NSWorkspace.shared.open(ExternalLinks.support)
    }

    /// Opens system notification preferences.
    func openNotificationPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Checks the actual launch at login status from the system.
    func refreshLaunchAtLoginStatus() {
        let actualStatus = settingsManager.checkLaunchAtLoginStatus()
        if actualStatus != launchAtLogin {
            logger.info("Launch at login status mismatch, updating UI")
            // Sync the UI to match the system state via the proper API
            settingsManager.launchAtLogin = actualStatus
        }
    }
}

// MARK: - Preview Helpers

extension SettingsViewModel {

    /// Creates a view model for previews.
    static var preview: SettingsViewModel {
        let viewModel = SettingsViewModel()
        viewModel.cloudflaredVersion = "2024.1.1"
        viewModel.cloudflaredPath = "/opt/homebrew/bin/cloudflared"
        return viewModel
    }
}
