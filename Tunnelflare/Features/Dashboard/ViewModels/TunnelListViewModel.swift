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

    /// Loads the tunnels from the API.
    func loadTunnels() async {
        guard !isLoading else { return }

        isLoading = true
        appState?.isLoadingTunnels = true
        error = nil

        defer {
            isLoading = false
            appState?.isLoadingTunnels = false
            hasLoaded = true
        }

        do {
            guard let accountId = appState?.selectedOrganization?.id else {
                self.error = "No organization selected"
                return
            }

            print("[TunnelList] Fetching tunnels for account: \(accountId)")
            let tunnels = try await apiClient.fetchTunnels(accountId: accountId)
            print("[TunnelList] Loaded \(tunnels.count) tunnels from API")

            appState?.tunnels = tunnels
            appState?.lastTunnelSync = Date()
        } catch {
            print("[TunnelList] Error loading tunnels: \(error)")
            self.error = error.localizedDescription
            appState?.tunnelLoadError = error.localizedDescription
        }
    }

    /// Refreshes the tunnel list.
    func refresh() async {
        await loadTunnels()
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
}
