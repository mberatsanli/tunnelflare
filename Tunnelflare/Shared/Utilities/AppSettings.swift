//
//  AppSettings.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import AppKit
import Foundation
import ServiceManagement
import os.log

// MARK: - AppSettings

/// Application settings that persist across launches.
///
/// AppSettings manages all user-configurable preferences for the application.
/// Settings are automatically persisted to UserDefaults when modified.
///
/// ## Usage
/// ```swift
/// // Load settings
/// var settings = AppSettings.load()
///
/// // Modify a setting
/// settings.autoReconnect = true
///
/// // Save changes
/// settings.save()
/// ```
///
/// ## Persistence
/// Settings are stored in UserDefaults as a JSON-encoded blob under the key
/// defined in `UserDefaultsKeys.appSettings`.
@MainActor
@Observable
final class AppSettingsManager {

    // MARK: - Properties

    /// Shared instance for app-wide access.
    static let shared = AppSettingsManager()

    /// The current settings.
    private(set) var settings: AppSettings

    /// Logger for settings operations.
    private let logger = Logger(subsystem: LogConstants.subsystem, category: "settings")

    // MARK: - Initialization

    private init() {
        self.settings = AppSettings.load()
        logger.info("Settings loaded")
    }

    // MARK: - General Settings

    /// Whether to launch the app at login.
    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set {
            settings.launchAtLogin = newValue
            updateLaunchAtLogin(newValue)
            save()
        }
    }

    /// Whether to show the app in the Dock.
    var showInDock: Bool {
        get { settings.showInDock }
        set {
            settings.showInDock = newValue
            updateDockVisibility(newValue)
            save()
        }
    }

    // MARK: - Notification Settings

    /// Whether notifications are enabled.
    var notificationsEnabled: Bool {
        get { settings.notificationsEnabled }
        set {
            settings.notificationsEnabled = newValue
            save()
        }
    }

    /// Whether disconnect notifications are enabled.
    var notifyOnDisconnect: Bool {
        get { settings.notifyOnDisconnect }
        set {
            settings.notifyOnDisconnect = newValue
            save()
        }
    }

    /// Whether reconnect notifications are enabled.
    var notifyOnReconnect: Bool {
        get { settings.notifyOnReconnect }
        set {
            settings.notifyOnReconnect = newValue
            save()
        }
    }

    /// Whether crash notifications are enabled.
    var notifyOnCrash: Bool {
        get { settings.notifyOnCrash }
        set {
            settings.notifyOnCrash = newValue
            save()
        }
    }

    // MARK: - Tunnel Settings

    /// Whether to automatically reconnect failed tunnels.
    var autoReconnect: Bool {
        get { settings.autoReconnect }
        set {
            settings.autoReconnect = newValue
            save()
        }
    }

    /// Delay in seconds before attempting to reconnect.
    var reconnectDelaySeconds: Int {
        get { settings.reconnectDelaySeconds }
        set {
            settings.reconnectDelaySeconds = max(1, min(300, newValue))
            save()
        }
    }

    /// Interval in seconds for refreshing tunnel status.
    var refreshIntervalSeconds: Int {
        get { settings.refreshIntervalSeconds }
        set {
            settings.refreshIntervalSeconds = max(10, min(300, newValue))
            save()
        }
    }

    // MARK: - Advanced Settings

    /// Custom path to cloudflared binary (optional).
    var customCloudflaredPath: String? {
        get { settings.customCloudflaredPath }
        set {
            settings.customCloudflaredPath = newValue?.isEmpty == true ? nil : newValue
            save()
        }
    }

    // MARK: - Log Settings

    /// How to display log entries.
    var logDisplayMode: LogDisplayMode {
        get { settings.logDisplayMode }
        set {
            settings.logDisplayMode = newValue
            save()
        }
    }

    // Note: persistLogsToFile removed - logs are always persisted per-tunnel now

    // MARK: - Public Methods

    /// Saves the current settings to UserDefaults.
    func save() {
        settings.save()
        logger.debug("Settings saved")
    }

    /// Resets all settings to their default values.
    func resetToDefaults() {
        settings = .default
        save()

        // Apply default settings
        updateLaunchAtLogin(settings.launchAtLogin)
        updateDockVisibility(settings.showInDock)

        logger.info("Settings reset to defaults")
    }

    /// Checks the current launch at login status from the system.
    func checkLaunchAtLoginStatus() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return settings.launchAtLogin
        }
    }

    // MARK: - Private Methods

    /// Updates the launch at login setting with the system.
    private func updateLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Registered as login item")
                } else {
                    try SMAppService.mainApp.unregister()
                    logger.info("Unregistered as login item")
                }
            } catch {
                logger.error("Failed to update login item: \(error.localizedDescription)")
            }
        } else {
            // Fallback for older macOS versions
            logger.warning("Launch at login requires macOS 13.0 or later")
        }
    }

    /// Updates the dock visibility setting.
    private func updateDockVisibility(_ showInDock: Bool) {
        if showInDock {
            NSApplication.shared.setActivationPolicy(.regular)
        } else {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

// MARK: - AppSettings Data Model

/// The data model for application settings.
///
/// This struct is Codable for persistence and contains all user preferences.
struct AppSettings: Codable, Equatable {

    // MARK: - General Settings

    /// Whether to launch the app at login.
    var launchAtLogin: Bool = false

    /// Whether to show the app in the Dock.
    var showInDock: Bool = false

    // MARK: - Notification Settings

    /// Whether notifications are enabled.
    var notificationsEnabled: Bool = true

    /// Whether to notify when a tunnel disconnects.
    var notifyOnDisconnect: Bool = true

    /// Whether to notify when a tunnel reconnects.
    var notifyOnReconnect: Bool = true

    /// Whether to notify when a tunnel crashes.
    var notifyOnCrash: Bool = true

    // MARK: - Tunnel Settings

    /// Whether to automatically reconnect failed tunnels.
    var autoReconnect: Bool = true

    /// Delay in seconds before attempting to reconnect.
    var reconnectDelaySeconds: Int = 5

    /// Interval in seconds for refreshing tunnel status.
    var refreshIntervalSeconds: Int = 30

    // MARK: - Advanced Settings

    /// Custom path to cloudflared binary (optional).
    var customCloudflaredPath: String?

    // MARK: - Log Settings

    /// How to display log entries.
    var logDisplayMode: LogDisplayMode = .terminal

    // Note: persistLogsToFile removed - logs are always persisted per-tunnel now

    // MARK: - Default Values

    /// Default settings.
    static let `default` = AppSettings()

    // MARK: - Persistence

    /// Loads settings from UserDefaults.
    ///
    /// - Returns: The loaded settings, or default settings if loading fails.
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.appSettings),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    /// Saves settings to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.appSettings)
        }
    }
}

// MARK: - Settings Validation

extension AppSettings {

    /// Validates the reconnect delay value.
    ///
    /// - Parameter value: The value to validate.
    /// - Returns: A validated value within acceptable range (1-300 seconds).
    static func validateReconnectDelay(_ value: Int) -> Int {
        max(1, min(300, value))
    }

    /// Validates the refresh interval value.
    ///
    /// - Parameter value: The value to validate.
    /// - Returns: A validated value within acceptable range (10-300 seconds).
    static func validateRefreshInterval(_ value: Int) -> Int {
        max(10, min(300, value))
    }
}

// MARK: - Reconnect Delay Options

/// Predefined options for reconnect delay.
enum ReconnectDelayOption: Int, CaseIterable, Identifiable {
    case oneSecond = 1
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneSecond: return "1 second"
        case .threeSeconds: return "3 seconds"
        case .fiveSeconds: return "5 seconds"
        case .tenSeconds: return "10 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        }
    }
}

// MARK: - Refresh Interval Options

/// Predefined options for refresh interval.
enum RefreshIntervalOption: Int, CaseIterable, Identifiable {
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .tenSeconds: return "10 seconds"
        case .thirtySeconds: return "30 seconds"
        case .oneMinute: return "1 minute"
        case .twoMinutes: return "2 minutes"
        case .fiveMinutes: return "5 minutes"
        }
    }
}

// MARK: - Log Display Mode

/// The display mode for log entries.
enum LogDisplayMode: String, Codable, CaseIterable, Identifiable {
    /// Terminal-style display with free text selection.
    case terminal
    /// Row-by-row display with individual selection.
    case rows

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .rows: return "Row-by-Row"
        }
    }

    var description: String {
        switch self {
        case .terminal: return "Free text selection like a terminal"
        case .rows: return "Select and copy individual log entries"
        }
    }
}
