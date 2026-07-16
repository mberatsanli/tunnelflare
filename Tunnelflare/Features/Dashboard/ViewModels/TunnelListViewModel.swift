//
//  TunnelListViewModel.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI

/// View model for the tunnel list view.
///
/// TunnelListViewModel manages the tunnel list state including search,
/// filtering, and tunnel operations.
@Observable
@MainActor
final class TunnelListViewModel {

    // MARK: - Search State

    /// The current search text.
    var searchText: String = ""

    // MARK: - Loading State

    /// Whether tunnels are being loaded.
    var isLoading: Bool = false

    /// Whether the initial load has completed.
    var hasLoaded: Bool = false

    // MARK: - Error State

    /// The current error, if any.
    var error: String?

    // MARK: - Selection State

    /// The ID of the currently hovered tunnel.
    var hoveredTunnelId: String?

    // MARK: - Deletion State

    /// The tunnel pending deletion (awaiting confirmation).
    var tunnelToDelete: Tunnel?

    /// Whether the delete confirmation dialog is showing.
    var showDeleteConfirmation: Bool = false

    /// Whether a tunnel deletion is in progress.
    var isDeletingTunnel: Bool = false

    /// Current deletion progress step.
    var deletionStep: DeletionStep = .preparing

    /// Error message from failed deletion.
    var deletionError: String?

    /// Whether to show the deletion error alert.
    var showDeletionError: Bool = false

    // MARK: - Dependencies

    /// Reference to the app state.
    weak var appState: AppState?

    /// API client for fetching tunnels.
    private let apiClient: CloudflareAPIClient

    // MARK: - Initialization

    init(appState: AppState? = nil, apiClient: CloudflareAPIClient = CloudflareAPIClient(authManager: .shared)) {
        self.apiClient = apiClient
        self.appState = appState
    }

    // MARK: - Computed Properties

    /// All tunnels from app state.
    var tunnels: [Tunnel] {
        appState?.tunnels ?? []
    }

    /// Tunnels filtered by search text.
    var filteredTunnels: [Tunnel] {
        let allTunnels = tunnels.sorted()

        guard !searchText.isEmpty else {
            return allTunnels
        }

        return allTunnels.filter { tunnel in
            tunnel.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Whether there are no tunnels.
    var isEmpty: Bool {
        tunnels.isEmpty
    }

    /// Whether the filtered results are empty.
    var isFilteredEmpty: Bool {
        filteredTunnels.isEmpty && !searchText.isEmpty
    }

    /// The local run state for a tunnel.
    func localState(for tunnel: Tunnel) -> TunnelRunState? {
        appState?.localTunnelStates[tunnel.id]
    }

    /// Whether a tunnel is running locally.
    func isRunningLocally(_ tunnel: Tunnel) -> Bool {
        localState(for: tunnel)?.isRunning == true
    }

    /// The tunnel count text.
    var tunnelCountText: String {
        let count = tunnels.count
        if searchText.isEmpty {
            return "\(count) tunnel\(count == 1 ? "" : "s")"
        } else {
            let filtered = filteredTunnels.count
            return "\(filtered) of \(count) tunnel\(count == 1 ? "" : "s")"
        }
    }

    // MARK: - Actions

    /// Loads the tunnels using cache-first strategy.
    ///
    /// 1. First loads from local database (instant, no loading indicator)
    /// 2. Then fetches from API in background
    /// 3. Updates DB and UI when API returns
    func loadTunnels() async {
        guard let accountId = appState?.selectedOrganization?.id else {
            self.error = "No organization selected"
            return
        }

        // Step 1: Load from database first (instant display)
        if !hasLoaded {
            await loadFromDatabase(accountId: accountId)
        }

        // Step 2: Fetch from API in background
        await fetchFromAPI(accountId: accountId)
    }

    /// Loads tunnels from the local database.
    private func loadFromDatabase(accountId: String) async {
        do {
            let db = TunnelDatabase.shared
            let records = try await db.getTunnels(accountId: accountId)

            if !records.isEmpty {
                let cachedTunnels = records.map { $0.toTunnel() }
                appState?.tunnels = cachedTunnels
                hasLoaded = true
                print("[TunnelList] Loaded \(cachedTunnels.count) tunnels from cache")
            }
        } catch {
            print("[TunnelList] Failed to load from database: \(error)")
            // Continue to API fetch even if DB fails
        }
    }

    /// Fetches tunnels from the Cloudflare API.
    private func fetchFromAPI(accountId: String) async {
        // Only show loading indicator if we have no cached data
        let showLoading = tunnels.isEmpty

        if showLoading {
            isLoading = true
            appState?.isLoadingTunnels = true
        }

        error = nil

        defer {
            if showLoading {
                isLoading = false
                appState?.isLoadingTunnels = false
            }
            hasLoaded = true
        }

        do {
            print("[TunnelList] Fetching tunnels from API for account: \(accountId)")
            let tunnels = try await apiClient.fetchTunnels(accountId: accountId)
            print("[TunnelList] Loaded \(tunnels.count) tunnels from API")

            appState?.tunnels = tunnels
            appState?.lastTunnelSync = Date()
            appState?.tunnelLoadError = nil

            // Save to database for next time
            await saveTunnelsToDatabase(tunnels: tunnels, accountId: accountId)
        } catch {
            print("[TunnelList] Error loading tunnels from API: \(error)")
            self.error = error.localizedDescription
            appState?.tunnelLoadError = error.localizedDescription
        }
    }

    /// Refreshes the tunnel list (always fetches from API).
    func refresh() async {
        guard let accountId = appState?.selectedOrganization?.id else { return }

        isLoading = true
        appState?.isLoadingTunnels = true

        defer {
            isLoading = false
            appState?.isLoadingTunnels = false
        }

        await fetchFromAPI(accountId: accountId)
    }

    /// Starts a tunnel.
    func startTunnel(_ tunnel: Tunnel) async {
        guard let appState = appState else { return }

        do {
            try await appState.startTunnel(tunnelId: tunnel.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Stops a tunnel.
    func stopTunnel(_ tunnel: Tunnel) async {
        guard let appState = appState else { return }

        await appState.stopTunnel(tunnelId: tunnel.id)
    }

    /// Toggles a tunnel's running state.
    func toggleTunnel(_ tunnel: Tunnel) async {
        if isRunningLocally(tunnel) {
            await stopTunnel(tunnel)
        } else {
            await startTunnel(tunnel)
        }
    }

    /// Restarts a tunnel.
    func restartTunnel(_ tunnel: Tunnel) async {
        guard let appState = appState else { return }

        do {
            try await appState.restartTunnel(tunnelId: tunnel.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Clears the search text.
    func clearSearch() {
        searchText = ""
    }

    /// Updates the search text in app state.
    func updateSearch(_ text: String) {
        searchText = text
        appState?.tunnelSearchText = text
    }

    // MARK: - Deletion Actions

    /// Requests deletion of a tunnel (shows confirmation dialog).
    ///
    /// - Parameter tunnel: The tunnel to delete.
    func requestDeleteTunnel(_ tunnel: Tunnel) {
        // Cannot delete a running tunnel (locally or remotely)
        guard !isRunningLocally(tunnel) && !tunnel.isActive else { return }

        tunnelToDelete = tunnel
        showDeleteConfirmation = true
    }

    /// Whether a tunnel can be deleted (not running locally or remotely).
    func canDeleteTunnel(_ tunnel: Tunnel) -> Bool {
        !isRunningLocally(tunnel) && !tunnel.isActive
    }

    /// Confirms and performs the tunnel deletion with progress tracking.
    func confirmDeleteTunnel() async {
        guard let tunnel = tunnelToDelete else { return }

        showDeleteConfirmation = false
        isDeletingTunnel = true
        deletionStep = .preparing
        deletionError = nil

        do {
            guard let accountId = appState?.selectedOrganization?.id,
                  let container = appState?.serviceContainer else {
                throw NSError(domain: "TunnelDeletion", code: -1, userInfo: [NSLocalizedDescriptionKey: "No organization selected"])
            }

            // Step 1: Check if tunnel needs to be stopped
            if appState?.localTunnelStates[tunnel.id]?.isRunning == true {
                deletionStep = .stoppingTunnel
                await appState?.stopTunnel(tunnelId: tunnel.id)
                try? await Task.sleep(for: .milliseconds(300))
            }

            // Step 2: Delete DNS records
            deletionStep = .deletingDNS
            try? await Task.sleep(for: .milliseconds(300))

            // Step 3: Delete from Cloudflare
            deletionStep = .deletingFromCloudflare
            _ = try await container.deleteTunnel(tunnelId: tunnel.id, accountId: accountId)

            // Step 4: Clean up local data
            deletionStep = .cleaningUp
            try? await Task.sleep(for: .milliseconds(300))

            // Step 5: Complete
            deletionStep = .completed
            try? await Task.sleep(for: .milliseconds(500))

            // Reset state and refresh
            isDeletingTunnel = false
            tunnelToDelete = nil
            await loadTunnels()

        } catch {
            deletionStep = .failed(error.localizedDescription)
            deletionError = error.localizedDescription

            // Wait a moment before showing error
            try? await Task.sleep(for: .seconds(1))
            isDeletingTunnel = false
            tunnelToDelete = nil
            showDeletionError = true
        }
    }

    /// Cancels the pending tunnel deletion.
    func cancelDeleteTunnel() {
        tunnelToDelete = nil
        showDeleteConfirmation = false
    }

    /// Dismisses the deletion error alert.
    func dismissDeletionError() {
        deletionError = nil
        showDeletionError = false
    }

    // MARK: - Database & Config Caching

    /// Saves tunnels to database and caches their configs.
    private func saveTunnelsToDatabase(tunnels: [Tunnel], accountId: String) async {
        print("[TunnelList] Saving \(tunnels.count) tunnels to database")

        do {
            // Convert to records and sync with database
            let records = tunnels.map { TunnelRecord(from: $0, accountId: accountId) }
            let removedIds = try await TunnelDatabase.shared.syncTunnels(records, accountId: accountId)

            // Clean up storage for removed tunnels
            for tunnelId in removedIds {
                try? await TunnelStorageManager.shared.deleteTunnelData(for: tunnelId)
                print("[TunnelList] Cleaned up removed tunnel: \(tunnelId)")
            }

            print("[TunnelList] Database sync complete")
        } catch {
            print("[TunnelList] Failed to save to database: \(error.localizedDescription)")
        }

        // Cache configs in parallel
        await cacheAllTunnelConfigs(tunnels: tunnels, accountId: accountId)
    }

    /// Caches configurations for all tunnels in parallel.
    private func cacheAllTunnelConfigs(tunnels: [Tunnel], accountId: String) async {
        print("[TunnelList] Caching configs for \(tunnels.count) tunnels")

        // Capture apiClient for use in task group
        let client = apiClient

        await withTaskGroup(of: Void.self) { group in
            for tunnel in tunnels {
                let tunnelId = tunnel.id
                let tunnelName = tunnel.name

                group.addTask {
                    do {
                        let config = try await client.fetchTunnelConfiguration(
                            accountId: accountId,
                            tunnelId: tunnelId
                        )

                        try await TunnelStorageManager.shared.saveConfig(
                            tunnelId: tunnelId,
                            ingressRules: config.config?.ingress ?? []
                        )
                        print("[TunnelList] Saved config for tunnel: \(tunnelName)")
                    } catch {
                        print("[TunnelList] Failed to save config for \(tunnelName): \(error.localizedDescription)")
                    }
                }
            }
        }

        print("[TunnelList] Finished caching tunnel configs")
    }
}

// MARK: - Deletion Step

/// Represents the current step in the tunnel deletion process.
enum DeletionStep: Equatable {
    case preparing
    case stoppingTunnel
    case deletingDNS
    case deletingFromCloudflare
    case cleaningUp
    case completed
    case failed(String)

    var title: String {
        switch self {
        case .preparing:
            return "Preparing..."
        case .stoppingTunnel:
            return "Stopping tunnel..."
        case .deletingDNS:
            return "Removing DNS records..."
        case .deletingFromCloudflare:
            return "Deleting from Cloudflare..."
        case .cleaningUp:
            return "Cleaning up..."
        case .completed:
            return "Completed"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }

    var systemImage: String {
        switch self {
        case .preparing:
            return "hourglass"
        case .stoppingTunnel:
            return "stop.circle"
        case .deletingDNS:
            return "globe"
        case .deletingFromCloudflare:
            return "cloud"
        case .cleaningUp:
            return "trash"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
