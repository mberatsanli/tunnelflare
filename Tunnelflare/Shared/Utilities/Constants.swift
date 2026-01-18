//
//  Constants.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - API Configuration

/// Cloudflare API configuration constants.
enum APIConstants {
    /// Base URL for the Cloudflare API v4.
    static let baseURL = URL(string: "https://api.cloudflare.com/client/v4/")!

    /// Request timeout interval in seconds.
    static let requestTimeout: TimeInterval = 30

    /// Maximum number of retries for failed requests.
    static let maxRetries = 3

    /// Delay between retries in seconds.
    static let retryDelay: TimeInterval = 1.0

    /// Default page size for paginated requests.
    static let defaultPageSize = 25

    /// Maximum page size for paginated requests.
    static let maxPageSize = 50
}

// MARK: - Keychain Configuration

/// Keychain service and key identifiers.
enum KeychainConstants {
    /// Service identifier for Keychain items.
    static let service = "com.tunnelflare"

    /// Access group for shared Keychain access.
    static let accessGroup = "com.tunnelflare"

    /// Key for storing API token.
    static let apiTokenKey = "api-token"

    /// Key prefix for storing tunnel tokens.
    static let tunnelTokenPrefix = "tunnel."

    /// Key suffix for tunnel tokens.
    static let tunnelTokenSuffix = ".token"

    /// Creates the key for a tunnel token.
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The Keychain key for the tunnel token.
    static func tunnelTokenKey(for tunnelId: String) -> String {
        "\(tunnelTokenPrefix)\(tunnelId)\(tunnelTokenSuffix)"
    }
}

// MARK: - UserDefaults Keys

/// UserDefaults key constants.
enum UserDefaultsKeys {
    /// Key for storing selected organization ID.
    static let selectedOrganizationId = "selectedOrganizationId"

    /// Key for storing app settings.
    static let appSettings = "appSettings"

    /// Key for storing show in dock preference.
    static let showInDock = "showInDock"

    /// Key for storing launch at login preference.
    static let launchAtLogin = "launchAtLogin"

    /// Key for storing notifications enabled preference.
    static let notificationsEnabled = "notificationsEnabled"

    /// Key for storing auto reconnect preference.
    static let autoReconnect = "autoReconnect"

    /// Key for storing reconnect delay preference.
    static let reconnectDelaySeconds = "reconnectDelaySeconds"

    /// Key for storing refresh interval preference.
    static let refreshIntervalSeconds = "refreshIntervalSeconds"

    /// Key for storing custom cloudflared path.
    static let customCloudflaredPath = "customCloudflaredPath"

    /// Key for storing last sync timestamp.
    static let lastSyncTimestamp = "lastSyncTimestamp"

    /// Key for storing window frame.
    static let dashboardWindowFrame = "dashboardWindowFrame"
}

// MARK: - Notification Constants

/// Notification category identifiers.
enum NotificationCategory {
    /// Category for tunnel disconnect notifications.
    static let tunnelDisconnect = "TUNNEL_DISCONNECT"

    /// Category for tunnel reconnect notifications.
    static let tunnelReconnect = "TUNNEL_RECONNECT"

    /// Category for tunnel crash notifications.
    static let tunnelCrash = "TUNNEL_CRASH"

    /// Category for authentication expired notifications.
    static let authExpired = "AUTH_EXPIRED"
}

/// Notification action identifiers.
enum NotificationAction {
    /// Action to reconnect a tunnel.
    static let reconnect = "RECONNECT"

    /// Action to view logs.
    static let viewLogs = "VIEW_LOGS"

    /// Action to restart a tunnel.
    static let restart = "RESTART"

    /// Action to re-authenticate.
    static let reauthenticate = "REAUTHENTICATE"
}

// MARK: - Log Configuration

/// Log configuration constants.
enum LogConstants {
    /// Subsystem for os.log entries.
    static let subsystem = "com.tunnelflare"

    /// Maximum number of log entries per tunnel.
    static let maxLogLines = 10_000

    /// Maximum log buffer size in bytes (50 MB).
    static let maxLogBytes = 50 * 1024 * 1024
}

// MARK: - cloudflared Configuration

/// cloudflared binary configuration constants.
enum CloudflaredConstants {
    /// Name of the cloudflared binary.
    static let binaryName = "cloudflared"

    /// Protocol to use for tunnel connections.
    static let tunnelProtocol = "quic"

    /// Default arguments for cloudflared.
    static let defaultArgs = ["--no-autoupdate", "--protocol", CloudflaredConstants.tunnelProtocol]

    /// Homebrew installation path (Apple Silicon).
    static let homebrewPathARM = "/opt/homebrew/bin/cloudflared"

    /// Homebrew installation path (Intel).
    static let homebrewPathIntel = "/usr/local/bin/cloudflared"

    /// Graceful shutdown timeout in seconds.
    static let gracefulShutdownTimeout: TimeInterval = 5.0
}

// MARK: - UI Constants

/// UI-related constants.
enum UIConstants {
    /// Minimum window width for the dashboard.
    static let minWindowWidth: CGFloat = 800

    /// Minimum window height for the dashboard.
    static let minWindowHeight: CGFloat = 600

    /// Default window width for the dashboard.
    static let defaultWindowWidth: CGFloat = 1000

    /// Default window height for the dashboard.
    static let defaultWindowHeight: CGFloat = 700

    /// Maximum tunnels to show in menu bar dropdown.
    static let maxMenuBarTunnels = 5

    /// Sidebar width range.
    static let sidebarMinWidth: CGFloat = 180
    static let sidebarIdealWidth: CGFloat = 200
}

// MARK: - Colors

/// Brand and status colors.
enum BrandColors {
    /// Cloudflare orange accent color.
    static let cloudflareOrange = "#F6821F"
}

// MARK: - Tunnel Validation

/// Tunnel name validation constants.
enum TunnelValidation {
    /// Minimum length for tunnel names.
    static let minLength = 3

    /// Maximum length for tunnel names.
    static let maxLength = 63

    /// Regex pattern for valid tunnel names.
    /// Must start with letter, end with alphanumeric, contain only lowercase letters, numbers, and hyphens.
    static let pattern = "^[a-z][a-z0-9-]{1,61}[a-z0-9]$"

    /// Allowed characters description for error messages.
    static let allowedCharactersDescription = "lowercase letters, numbers, and hyphens"
}

// MARK: - App Info

/// Application information constants.
enum AppInfo {
    /// Application name.
    static let name = "Tunnelflare"

    /// Bundle identifier.
    static let bundleIdentifier = "com.tunnelflare"

    /// Application version from bundle.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Build number from bundle.
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    /// Full version string (e.g., "1.0.0 (1)").
    static var fullVersion: String {
        "\(version) (\(buildNumber))"
    }

    /// Copyright notice.
    static let copyright = "Copyright 2026. All rights reserved."
}

// MARK: - External Links

/// External link URLs.
enum ExternalLinks {
    /// Cloudflare Tunnel documentation.
    static let documentation = URL(string: "https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/")!

    /// Cloudflare dashboard.
    static let cloudfllareDashboard = URL(string: "https://dash.cloudflare.com/")!

    /// Cloudflare Zero Trust dashboard.
    static let zeroTrustDashboard = URL(string: "https://one.dash.cloudflare.com/")!

    /// GitHub repository.
    static let gitHub = URL(string: "https://github.com/mberatsanli/tunnelflare")!

    /// Support page.
    static let support = URL(string: "https://developers.cloudflare.com/support/")!
}
