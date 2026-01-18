//
//  AppState.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI

/// The global application state container.
///
/// AppState is the single source of truth for the application's state.
/// It uses the `@Observable` macro (available in macOS 14+) for automatic
/// SwiftUI view updates when state changes.
///
/// ## Architecture
/// AppState follows the MVVM pattern and acts as the central hub for:
/// - Authentication state (user, tokens, organization)
/// - Tunnel state (list of tunnels, local run states)
/// - UI state (dashboard visibility, selected items)
/// - Service references (API client, process manager, etc.)
///
/// ## Usage
/// ```swift
/// // In SwiftUI views
/// @Environment(AppState.self) private var appState
///
/// // Access state
/// if appState.isAuthenticated {
///     TunnelListView()
/// }
/// ```
@MainActor
@Observable
final class AppState {

    // MARK: - Cloudflared State

    /// Whether cloudflared binary is available on the system.
    var isCloudflaredAvailable: Bool = false

    /// The path to the cloudflared binary, if found.
    var cloudflaredPath: String?

    /// The version of cloudflared, if determined.
    var cloudflaredVersion: String?

    /// Whether cloudflared check is in progress.
    var isCheckingCloudflared: Bool = false

    /// Whether cloudflared installation is in progress.
    var isInstallingCloudflared: Bool = false

    /// Error message from cloudflared installation, if any.
    var cloudflaredInstallError: String?

    // MARK: - Authentication State

    /// Whether the user is currently authenticated.
    var isAuthenticated: Bool = false

    /// The currently authenticated user.
    /// Uses the User model from Core/API/Models/User.swift
    var currentUser: User?

    /// The list of organizations/accounts the user has access to.
    /// Uses the Organization (alias for Account) from Core/API/Models/Account.swift
    var organizations: [Organization] = []

    /// The currently selected organization.
    var selectedOrganization: Organization?

    // MARK: - Tunnel State

    /// All tunnels fetched from the Cloudflare API.
    /// Uses the Tunnel model from Core/API/Models/Tunnel.swift
    var tunnels: [Tunnel] = []

    /// Local run states for tunnels running on this machine.
    /// Key: tunnel ID, Value: current run state
    var localTunnelStates: [String: TunnelRunState] = [:]

    /// Whether tunnels are currently being loaded.
    var isLoadingTunnels: Bool = false

    /// Error that occurred while loading tunnels, if any.
    var tunnelLoadError: String?

    /// Timestamp of the last successful tunnel sync.
    var lastTunnelSync: Date?

    /// Auto-refresh interval in seconds (default: 60 seconds).
    var autoRefreshInterval: TimeInterval = 60

    /// Whether auto-refresh is enabled.
    var isAutoRefreshEnabled: Bool = true

    /// The auto-refresh task.
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - UI State

    /// Whether the dashboard window is currently visible.
    var isDashboardVisible: Bool = false

    /// The currently selected tunnel ID in the dashboard.
    var selectedTunnelId: String?

    /// Tunnel ID to navigate to detail view when dashboard opens (from menu bar).
    var pendingTunnelDetailNavigation: String?

    /// The currently selected navigation destination.
    var selectedNavigation: NavigationDestination = .tunnels

    /// Whether the new tunnel wizard is being shown.
    var isShowingNewTunnelWizard: Bool = false

    /// Current search text in the tunnel list.
    var tunnelSearchText: String = ""

    // MARK: - Settings

    /// Application settings.
    /// Returns the current settings from the shared settings manager.
    /// Uses AppSettings from Shared/Utilities/AppSettings.swift
    var settings: AppSettings {
        settingsManager.settings
    }

    /// The settings manager for system-level settings (launch at login, dock visibility).
    var settingsManager: AppSettingsManager {
        AppSettingsManager.shared
    }

    // MARK: - Services

    /// Service container holding process management services.
    /// This is set after initialization when services are ready.
    var serviceContainer: ServiceContainer?

    // MARK: - Initialization

    /// Creates a new AppState instance.
    ///
    /// This initializer sets up the initial state and loads any persisted data.
    init() {
        loadPersistedState()
    }

    // MARK: - Computed Properties

    /// The currently selected tunnel, if any.
    var selectedTunnel: Tunnel? {
        guard let id = selectedTunnelId else { return nil }
        return tunnels.first { $0.id == id }
    }

    /// Tunnels filtered by the current search text.
    var filteredTunnels: [Tunnel] {
        guard !tunnelSearchText.isEmpty else { return tunnels }
        return tunnels.filter { tunnel in
            tunnel.name.localizedCaseInsensitiveContains(tunnelSearchText)
        }
    }

    /// Count of tunnels that are currently connected (have active connections).
    var connectedTunnelCount: Int {
        tunnels.filter { $0.isActive }.count
    }

    /// Count of tunnels running locally on this machine.
    var localRunningTunnelCount: Int {
        localTunnelStates.values.filter { $0.isRunning }.count
    }

    /// Aggregate status for the menu bar icon.
    var aggregateStatus: AggregateStatus {
        if !isAuthenticated {
            return .unauthenticated
        }

        // Check for errors first
        if localTunnelStates.values.contains(where: { if case .error = $0 { return true } else { return false } }) {
            return .error
        }

        // Check for transitioning states
        if localTunnelStates.values.contains(where: { $0.isTransitioning }) {
            return .connecting
        }

        let runningCount = localRunningTunnelCount

        // If any tunnel is running, we're connected
        if runningCount > 0 {
            return .connected
        }

        return .disconnected
    }

    // MARK: - Public Methods

    // MARK: Cloudflared Management

    /// Checks if cloudflared is available on the system.
    func checkCloudflaredAvailability() async {
        isCheckingCloudflared = true
        defer { isCheckingCloudflared = false }

        let locator = CloudflaredLocator(customPath: settings.customCloudflaredPath)

        if let binaryURL = locator.locateBinary() {
            cloudflaredPath = binaryURL.path
            isCloudflaredAvailable = true

            // Try to get version
            do {
                cloudflaredVersion = try await locator.getVersion(at: binaryURL)
            } catch {
                cloudflaredVersion = nil
            }
        } else {
            cloudflaredPath = nil
            cloudflaredVersion = nil
            isCloudflaredAvailable = false
        }
    }

    /// Installs cloudflared using Homebrew.
    func installCloudflaredWithHomebrew() async {
        isInstallingCloudflared = true
        cloudflaredInstallError = nil

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "/opt/homebrew/bin/brew install cloudflared || /usr/local/bin/brew install cloudflared"]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Installation successful, recheck availability
                await checkCloudflaredAvailability()
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                cloudflaredInstallError = "Installation failed: \(errorOutput)"
            }
        } catch {
            cloudflaredInstallError = "Failed to run Homebrew: \(error.localizedDescription)"
        }

        isInstallingCloudflared = false
    }

    /// Downloads and installs cloudflared directly from GitHub.
    func installCloudflaredDirect() async {
        isInstallingCloudflared = true
        cloudflaredInstallError = nil

        do {
            // Determine architecture
            #if arch(arm64)
            let downloadURL = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-arm64"
            #else
            let downloadURL = "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64"
            #endif

            let installPath = "/usr/local/bin/cloudflared"

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", """
                curl -L -o /tmp/cloudflared '\(downloadURL)' && \
                chmod +x /tmp/cloudflared && \
                sudo mv /tmp/cloudflared '\(installPath)'
                """]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                await checkCloudflaredAvailability()
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                cloudflaredInstallError = "Installation failed: \(errorOutput)"
            }
        } catch {
            cloudflaredInstallError = "Failed to download cloudflared: \(error.localizedDescription)"
        }

        isInstallingCloudflared = false
    }

    // MARK: Authentication

    /// Updates the authentication state after successful login.
    ///
    /// - Parameters:
    ///   - user: The authenticated user.
    ///   - organizations: The list of organizations the user has access to.
    func setAuthenticated(user: User, organizations: [Organization]) {
        self.currentUser = user
        self.organizations = organizations
        self.isAuthenticated = true

        // Auto-select organization if only one exists
        if organizations.count == 1 {
            self.selectedOrganization = organizations.first
        } else {
            // Try to restore previously selected organization
            loadSelectedOrganization()
        }

        persistAuthState()
    }

    /// Clears authentication state on logout.
    func clearAuthentication() {
        // Stop auto-refresh
        stopAutoRefresh()

        isAuthenticated = false
        currentUser = nil
        organizations = []
        selectedOrganization = nil
        tunnels = []
        localTunnelStates = [:]
        selectedTunnelId = nil

        clearPersistedAuthState()
    }

    /// Updates the selected organization.
    ///
    /// - Parameter organization: The organization to select.
    func selectOrganization(_ organization: Organization) {
        selectedOrganization = organization
        persistSelectedOrganization()

        // Clear tunnels when organization changes
        tunnels = []
        selectedTunnelId = nil
        tunnelLoadError = nil
    }

    /// Updates the local run state for a tunnel.
    ///
    /// - Parameters:
    ///   - tunnelId: The ID of the tunnel.
    ///   - state: The new run state.
    func updateLocalTunnelState(tunnelId: String, state: TunnelRunState) {
        localTunnelStates[tunnelId] = state
    }

    /// Removes the local run state for a tunnel.
    ///
    /// - Parameter tunnelId: The ID of the tunnel.
    func removeLocalTunnelState(tunnelId: String) {
        localTunnelStates.removeValue(forKey: tunnelId)
    }

    /// Gets the tunnel name for a given tunnel ID.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The tunnel name, or the tunnel ID if not found.
    func getTunnelName(tunnelId: String) -> String {
        tunnels.first { $0.id == tunnelId }?.name ?? tunnelId
    }

    // MARK: - Tunnel Control Methods

    /// Starts a tunnel using the service container.
    ///
    /// - Parameter tunnelId: The tunnel ID to start.
    /// - Throws: AppError if start fails.
    func startTunnel(tunnelId: String) async throws {
        guard let accountId = selectedOrganization?.id else {
            throw AppError.noOrganizationSelected
        }

        guard let container = serviceContainer else {
            throw AppError.servicesNotInitialized
        }

        updateLocalTunnelState(tunnelId: tunnelId, state: .starting)

        // Get the tunnel name for notifications
        let tunnelName = getTunnelName(tunnelId: tunnelId)

        do {
            try await container.startTunnel(tunnelId: tunnelId, accountId: accountId, tunnelName: tunnelName)

            // State will be updated via event stream
            // For now, simulate the running state
            if let status = await container.processManager.getStatus(tunnelId: tunnelId) {
                updateLocalTunnelState(tunnelId: tunnelId, state: status)
            }

            // Update last connected time in database (silent failure - don't fail tunnel start)
            try? await TunnelDatabase.shared.updateLastConnectedAt(tunnelId: tunnelId, date: Date())
        } catch {
            updateLocalTunnelState(tunnelId: tunnelId, state: .error(error.localizedDescription))
            throw AppError.from(error)
        }
    }

    /// Stops a tunnel using the service container.
    ///
    /// - Parameter tunnelId: The tunnel ID to stop.
    func stopTunnel(tunnelId: String) async {
        guard let container = serviceContainer else {
            updateLocalTunnelState(tunnelId: tunnelId, state: .error("Services not initialized"))
            return
        }

        updateLocalTunnelState(tunnelId: tunnelId, state: .stopping)

        await container.stopTunnel(tunnelId: tunnelId)
        updateLocalTunnelState(tunnelId: tunnelId, state: .stopped)
    }

    /// Restarts a tunnel using the service container.
    ///
    /// - Parameter tunnelId: The tunnel ID to restart.
    /// - Throws: AppError if restart fails.
    func restartTunnel(tunnelId: String) async throws {
        guard let accountId = selectedOrganization?.id else {
            throw AppError.noOrganizationSelected
        }

        guard let container = serviceContainer else {
            throw AppError.servicesNotInitialized
        }

        updateLocalTunnelState(tunnelId: tunnelId, state: .stopping)

        do {
            try await container.restartTunnel(tunnelId: tunnelId, accountId: accountId)

            if let status = await container.processManager.getStatus(tunnelId: tunnelId) {
                updateLocalTunnelState(tunnelId: tunnelId, state: status)
            }
        } catch {
            updateLocalTunnelState(tunnelId: tunnelId, state: .error(error.localizedDescription))
            throw AppError.from(error)
        }
    }

    /// Stops all running tunnels.
    func stopAllTunnels() async {
        guard let container = serviceContainer else { return }

        for tunnelId in localTunnelStates.keys {
            updateLocalTunnelState(tunnelId: tunnelId, state: .stopping)
        }

        await container.stopAllTunnels()

        for tunnelId in localTunnelStates.keys {
            updateLocalTunnelState(tunnelId: tunnelId, state: .stopped)
        }
    }

    /// Registers all current tunnel names with the service container.
    ///
    /// This should be called after tunnels are loaded to ensure notifications
    /// have access to tunnel names.
    func registerTunnelNamesWithService() async {
        guard let container = serviceContainer else { return }

        for tunnel in tunnels {
            await container.registerTunnelName(tunnelId: tunnel.id, name: tunnel.name)
        }
    }

    // MARK: - Auto-Refresh

    /// Starts the auto-refresh task for tunnel data.
    ///
    /// This refreshes all tunnel data from the API at regular intervals.
    func startAutoRefresh() {
        stopAutoRefresh()

        guard isAutoRefreshEnabled else { return }

        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Wait for the refresh interval
                try? await Task.sleep(for: .seconds(self?.autoRefreshInterval ?? 60))

                guard !Task.isCancelled else { break }

                // Refresh tunnels
                await self?.refreshAllTunnels()
            }
        }

        print("[AppState] Auto-refresh started with interval: \(autoRefreshInterval)s")
    }

    /// Stops the auto-refresh task.
    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        print("[AppState] Auto-refresh stopped")
    }

    /// Refreshes all tunnel data from the API (background, no loading indicator).
    @MainActor
    func refreshAllTunnels() async {
        guard isAuthenticated,
              let accountId = selectedOrganization?.id else {
            return
        }

        // Don't refresh if already loading
        guard !isLoadingTunnels else { return }

        // Note: No loading indicator for background refresh
        // isLoadingTunnels = true

        do {
            let apiClient = CloudflareAPIClient(authManager: .shared)
            let updatedTunnels = try await apiClient.fetchTunnels(accountId: accountId)

            // Update tunnels
            tunnels = updatedTunnels
            lastTunnelSync = Date()
            tunnelLoadError = nil

            // Save to database for cache
            await saveTunnelsToDatabase(tunnels: updatedTunnels, accountId: accountId)

            // Update last connected time for active tunnels (has connections from remote)
            await updateLastConnectedForActiveTunnels(updatedTunnels)

            // Register tunnel names for notifications
            await registerTunnelNamesWithService()

            print("[AppState] Auto-refresh: Updated \(updatedTunnels.count) tunnels")
        } catch {
            print("[AppState] Auto-refresh error: \(error.localizedDescription)")
            tunnelLoadError = error.localizedDescription
        }
    }

    /// Saves tunnels to the local database.
    private func saveTunnelsToDatabase(tunnels: [Tunnel], accountId: String) async {
        do {
            let db = TunnelDatabase.shared
            let records = tunnels.map { TunnelRecord(from: $0, accountId: accountId) }
            try await db.upsertTunnels(records)
            print("[AppState] Saved \(tunnels.count) tunnels to database")
        } catch {
            print("[AppState] Failed to save tunnels to database: \(error)")
        }
    }

    /// Updates last connected time for tunnels that are active (have remote connections).
    private func updateLastConnectedForActiveTunnels(_ tunnels: [Tunnel]) async {
        let db = TunnelDatabase.shared
        let now = Date()

        for tunnel in tunnels {
            // Only update if tunnel has active connections (running remotely or locally)
            guard tunnel.isActive else { continue }

            // Skip if running locally (already updated in startTunnel)
            if localTunnelStates[tunnel.id]?.isRunning == true {
                continue
            }

            // Update last connected time for remote-only active tunnels
            try? await db.updateLastConnectedAt(tunnelId: tunnel.id, date: now)
        }
    }

    // MARK: - Notification Actions

    /// Handles a notification action to reconnect a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID to reconnect.
    func handleReconnectFromNotification(tunnelId: String) async {
        do {
            try await startTunnel(tunnelId: tunnelId)
        } catch {
            // Error is already handled in startTunnel
        }
    }

    /// Handles a notification action to restart a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID to restart.
    func handleRestartFromNotification(tunnelId: String) async {
        do {
            try await restartTunnel(tunnelId: tunnelId)
        } catch {
            // Error is already handled in restartTunnel
        }
    }

    /// Handles a notification action to view logs for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID to view logs for.
    func handleViewLogsFromNotification(tunnelId: String) {
        // Open dashboard and navigate to logs for this tunnel
        isDashboardVisible = true
        selectedTunnelId = tunnelId
        selectedNavigation = .logs
    }

    /// Handles a notification tap to open the dashboard.
    ///
    /// - Parameter tunnelId: The tunnel ID that was tapped, if any.
    func handleNotificationTapped(tunnelId: String?) {
        isDashboardVisible = true
        if let tunnelId = tunnelId {
            selectedTunnelId = tunnelId
        }
    }

    // MARK: - Private Methods

    /// Loads persisted state from UserDefaults.
    private func loadPersistedState() {
        // Settings are now loaded via AppSettingsManager.shared
        // No need to load here - settingsManager handles persistence
    }

    /// Persists authentication state.
    private func persistAuthState() {
        // Note: Actual tokens are stored in Keychain, not here
        // This just persists non-sensitive auth state
    }

    /// Clears persisted authentication state.
    private func clearPersistedAuthState() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.selectedOrganizationId)
    }

    /// Loads the previously selected organization from UserDefaults.
    private func loadSelectedOrganization() {
        guard let savedId = UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedOrganizationId) else {
            return
        }

        selectedOrganization = organizations.first { $0.id == savedId }
    }

    /// Persists the selected organization ID.
    private func persistSelectedOrganization() {
        if let orgId = selectedOrganization?.id {
            UserDefaults.standard.set(orgId, forKey: UserDefaultsKeys.selectedOrganizationId)
        }
    }
}

// MARK: - Aggregate Status

/// Represents the aggregate status of all tunnels for the menu bar icon.
enum AggregateStatus: Equatable {
    /// User is not authenticated.
    case unauthenticated

    /// All local tunnels are connected.
    case connected

    /// Some local tunnels are connected, some are not.
    case partial

    /// No local tunnels are connected.
    case disconnected

    /// A tunnel is starting or stopping.
    case connecting

    /// An error occurred with one or more tunnels.
    case error
}

// MARK: - Tunnel Run State

/// Represents the local run state of a tunnel on this machine.
enum TunnelRunState: Equatable {
    /// The tunnel is not running locally.
    case stopped

    /// The tunnel is starting up.
    case starting

    /// The tunnel is running with the given process ID.
    case running(pid: Int32, startedAt: Date)

    /// The tunnel is stopping.
    case stopping

    /// The tunnel encountered an error.
    case error(String)

    /// Whether the tunnel is currently running.
    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// Whether the tunnel is in a transitional state (starting or stopping).
    var isTransitioning: Bool {
        switch self {
        case .starting, .stopping:
            return true
        default:
            return false
        }
    }

    /// The process ID if running, nil otherwise.
    var pid: Int32? {
        if case .running(let pid, _) = self {
            return pid
        }
        return nil
    }

    /// The start time if running, nil otherwise.
    var startedAt: Date? {
        if case .running(_, let date) = self {
            return date
        }
        return nil
    }

    /// The error message if in error state, nil otherwise.
    var errorMessage: String? {
        if case .error(let message) = self {
            return message
        }
        return nil
    }
}

// Note: AppError is now defined in Shared/Utilities/AppError.swift
// with a comprehensive error type hierarchy that covers:
// - Authentication errors
// - API errors
// - Tunnel errors
// - Validation errors
// - General errors
