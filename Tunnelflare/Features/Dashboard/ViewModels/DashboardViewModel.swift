//
//  DashboardViewModel.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI

/// View model for the main dashboard view.
///
/// DashboardViewModel manages the dashboard navigation state and coordinates
/// data loading for the dashboard content areas.
@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - Navigation State

    /// The currently selected navigation item.
    var selectedNavigation: NavigationDestination = .tunnels

    /// The currently selected tunnel ID for detail view.
    var selectedTunnelId: String?

    /// Whether the tunnel detail view is being shown.
    var isShowingTunnelDetail: Bool = false

    // MARK: - Loading State

    /// Whether data is currently being loaded.
    var isLoading: Bool = false

    /// Whether the initial data load has completed.
    var hasLoadedInitialData: Bool = false

    // MARK: - Error State

    /// The current error, if any.
    var error: Error?

    /// Whether to show the error alert.
    var showErrorAlert: Bool = false

    // MARK: - Dependencies

    /// Reference to the app state.
    weak var appState: AppState?

    // MARK: - Initialization

    init(appState: AppState? = nil) {
        self.appState = appState
    }

    // MARK: - Public Methods

    /// Sets up the view model with the app state.
    func setup(appState: AppState) {
        self.appState = appState
    }

    /// Loads initial data for the dashboard.
    func loadInitialData() async {
        guard !hasLoadedInitialData, !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            // TODO: Connect to API client to load tunnels
            // For now, this is a placeholder
            try await Task.sleep(for: .milliseconds(500))

            hasLoadedInitialData = true
            error = nil
        } catch {
            self.error = error
            showErrorAlert = true
        }
    }

    /// Refreshes the dashboard data.
    func refresh() async {
        guard !isLoading else { return }

        isLoading = true
        appState?.isLoadingTunnels = true
        defer {
            isLoading = false
            appState?.isLoadingTunnels = false
        }

        do {
            // TODO: Connect to API client to refresh tunnels
            try await Task.sleep(for: .milliseconds(500))

            appState?.lastTunnelSync = Date()
            error = nil
        } catch {
            self.error = error
            showErrorAlert = true
        }
    }

    /// Navigates to a specific destination.
    func navigate(to destination: NavigationDestination) {
        selectedNavigation = destination
        appState?.selectedNavigation = destination

        // Clear tunnel selection when navigating away from tunnels
        if destination != .tunnels {
            selectedTunnelId = nil
            isShowingTunnelDetail = false
        }
    }

    /// Selects a tunnel for detail view.
    func selectTunnel(_ tunnel: Tunnel) {
        selectedTunnelId = tunnel.id
        isShowingTunnelDetail = true
        appState?.selectedTunnelId = tunnel.id
    }

    /// Deselects the current tunnel.
    func deselectTunnel() {
        selectedTunnelId = nil
        isShowingTunnelDetail = false
        appState?.selectedTunnelId = nil
    }

    /// Handles the new tunnel wizard request.
    func showNewTunnelWizard() {
        appState?.isShowingNewTunnelWizard = true
    }

    /// Dismisses any error alert.
    func dismissError() {
        showErrorAlert = false
        error = nil
    }

    // MARK: - Computed Properties

    /// The user's display name.
    var userDisplayName: String {
        appState?.currentUser?.displayName ?? "User"
    }

    /// The user's email.
    var userEmail: String {
        appState?.currentUser?.email ?? ""
    }

    /// The selected organization name.
    var organizationName: String {
        appState?.selectedOrganization?.name ?? "Organization"
    }

    /// Whether the user is authenticated.
    var isAuthenticated: Bool {
        appState?.isAuthenticated ?? false
    }

    /// The list of tunnels from app state.
    var tunnels: [Tunnel] {
        appState?.tunnels ?? []
    }

    /// The filtered tunnels based on search.
    var filteredTunnels: [Tunnel] {
        appState?.filteredTunnels ?? []
    }

    /// The currently selected tunnel.
    var selectedTunnel: Tunnel? {
        guard let id = selectedTunnelId else { return nil }
        return tunnels.first { $0.id == id }
    }

    /// The last sync timestamp formatted.
    var lastSyncText: String? {
        guard let lastSync = appState?.lastTunnelSync else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
    }
}
