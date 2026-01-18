//
//  DashboardView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// The main dashboard view with sidebar navigation.
struct DashboardView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @State private var viewModel = DashboardViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingNewTunnelWizard = false
    @State private var tunnelCreationViewModel = TunnelCreationViewModel()
    @State private var showingOrganizationSelector = false

    // MARK: - Body

    var body: some View {
        mainContent
            .frame(
                minWidth: UIConstants.minWindowWidth,
                minHeight: UIConstants.minWindowHeight
            )
            .task {
                // Check cloudflared availability on launch
                if !appState.isCloudflaredAvailable && !appState.isCheckingCloudflared {
                    await appState.checkCloudflaredAvailability()
                }
            }
            .onAppear {
                viewModel.setup(appState: appState)

                // Handle pending navigation when view appears (from menu bar)
                if let tunnelId = appState.pendingTunnelDetailNavigation,
                   let tunnel = appState.tunnels.first(where: { $0.id == tunnelId }) {
                    viewModel.navigate(to: .tunnels)
                    viewModel.selectTunnel(tunnel)
                    appState.pendingTunnelDetailNavigation = nil
                }
            }
            .onChange(of: appState.selectedNavigation) { _, newValue in
                viewModel.navigate(to: newValue)
            }
            .onChange(of: appState.selectedTunnelId) { _, newValue in
                if let tunnelId = newValue,
                   let tunnel = appState.tunnels.first(where: { $0.id == tunnelId }) {
                    viewModel.selectTunnel(tunnel)
                }
            }
            .onChange(of: appState.pendingTunnelDetailNavigation) { _, newValue in
                if let tunnelId = newValue,
                   let tunnel = appState.tunnels.first(where: { $0.id == tunnelId }) {
                    // Navigate to tunnels section and select the tunnel
                    viewModel.navigate(to: .tunnels)
                    viewModel.selectTunnel(tunnel)
                    // Clear the pending navigation
                    appState.pendingTunnelDetailNavigation = nil
                }
            }
            .onChange(of: appState.isShowingNewTunnelWizard) { _, newValue in
                if newValue {
                    // Set up dependencies BEFORE showing the sheet
                    tunnelCreationViewModel.appState = appState
                    tunnelCreationViewModel.apiClient = CloudflareAPIClient(authManager: .shared)
                }
                showingNewTunnelWizard = newValue
            }
            .sheet(isPresented: $showingNewTunnelWizard, onDismiss: {
                // Ensure state is reset when sheet is dismissed by any means
                appState.isShowingNewTunnelWizard = false
                tunnelCreationViewModel.reset()
            }) {
                TunnelWizardView(
                    viewModel: tunnelCreationViewModel,
                    onComplete: { _ in
                        showingNewTunnelWizard = false
                        // State reset handled by onDismiss
                    },
                    onCancel: {
                        showingNewTunnelWizard = false
                        // State reset handled by onDismiss
                    }
                )
                .environment(appState)
            }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if appState.isCheckingCloudflared {
            // Show loading while checking cloudflared
            CenteredLoadingView(message: "Checking cloudflared...")
        } else if !appState.isCloudflaredAvailable {
            // Show setup view if cloudflared is not installed
            CloudflaredSetupView()
        } else if appState.isAuthenticated {
            if appState.selectedOrganization == nil && appState.organizations.count > 1 {
                // Show organization selector if multiple orgs and none selected
                organizationSelectorView
            } else {
                authenticatedView
            }
        } else {
            LoginView()
        }
    }

    // MARK: - Organization Selector

    private var organizationSelectorView: some View {
        VStack {
            Spacer()
            OrganizationSelectorView(
                organizations: appState.organizations,
                onSelect: { organization in
                    appState.selectOrganization(organization)
                }
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Authenticated View

    private var authenticatedView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(
                    min: UIConstants.sidebarMinWidth,
                    ideal: UIConstants.sidebarIdealWidth
                )
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Show different toolbar items based on selected navigation
                switch viewModel.selectedNavigation {
                case .tunnels:
                    Button {
                        Task {
                            await appState.refreshAllTunnels()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh Tunnels (⌘R)")

                    Button {
                        viewModel.showNewTunnelWizard()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("New Tunnel (⌘N)")

                case .logs:
                    // Logs page - no toolbar buttons needed
                    // (LogsView has its own filter/export controls)
                    EmptyView()

                case .settings:
                    // Settings page - no toolbar buttons needed
                    EmptyView()
                }
            }
        }
        .task {
            // Initialize ServiceContainer if not already done
            if appState.serviceContainer == nil {
                await initializeServiceContainer()
            }
            await viewModel.loadInitialData()
        }
    }

    // MARK: - Sidebar Content

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            navigationList
            Divider()
            accountSection
                .padding()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var navigationList: some View {
        List(selection: Binding(
            get: { viewModel.selectedNavigation },
            set: { if let nav = $0 { viewModel.navigate(to: nav) } }
        )) {
            Section {
                Label("Tunnels", systemImage: "network")
                    .tag(NavigationDestination.tunnels)
                Label("Logs", systemImage: "doc.text")
                    .tag(NavigationDestination.logs)
                Label("Settings", systemImage: "gear")
                    .tag(NavigationDestination.settings)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Account Section

    private var accountSection: some View {
        HStack(spacing: 10) {
            userAvatar
            userInfo
            Spacer()
            accountMenu
        }
    }

    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.2))
            Text(userInitials)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.orange)
        }
        .frame(width: 32, height: 32)
    }

    private var userInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.organizationName)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
            if !viewModel.userEmail.isEmpty {
                Text(viewModel.userEmail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            if appState.organizations.count > 1 {
                Button("Switch Organization...") {
                    showingOrganizationSelector = true
                }
                Divider()
            }
            Button("Log Out", role: .destructive) {
                appState.clearAuthentication()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: 24)
        .sheet(isPresented: $showingOrganizationSelector) {
            OrganizationSelectorView(
                organizations: appState.organizations,
                onSelect: { organization in
                    appState.selectOrganization(organization)
                    showingOrganizationSelector = false
                }
            )
        }
    }

    private var userInitials: String {
        let name = viewModel.organizationName
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first?.prefix(2) {
            return String(first).uppercased()
        }
        return "O"
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedNavigation {
        case .tunnels:
            tunnelsDetailContent
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var tunnelsDetailContent: some View {
        if viewModel.isShowingTunnelDetail, let tunnel = viewModel.selectedTunnel {
            TunnelDetailView(tunnel: tunnel, onBack: {
                viewModel.deselectTunnel()
            })
        } else {
            TunnelListView(
                onTunnelSelected: { tunnel in
                    viewModel.selectTunnel(tunnel)
                },
                onNewTunnel: {
                    viewModel.showNewTunnelWizard()
                }
            )
        }
    }

    // MARK: - Service Initialization

    /// Initializes the ServiceContainer for tunnel operations.
    private func initializeServiceContainer() async {
        let apiClient = CloudflareAPIClient(authManager: .shared)
        let container = await ServiceContainer.create(
            apiClient: apiClient,
            settings: appState.settings
        )

        // Start all services
        await container.startAll()

        // Assign to appState
        appState.serviceContainer = container

        // Register tunnel names for notifications
        await appState.registerTunnelNamesWithService()
    }
}

// MARK: - Window Frame Persistence

extension DashboardView {
    static func saveWindowFrame(_ frame: NSRect) {
        let frameString = NSStringFromRect(frame)
        UserDefaults.standard.set(frameString, forKey: UserDefaultsKeys.dashboardWindowFrame)
    }

    static func loadWindowFrame() -> NSRect? {
        guard let frameString = UserDefaults.standard.string(forKey: UserDefaultsKeys.dashboardWindowFrame) else {
            return nil
        }
        let frame = NSRectFromString(frameString)
        return frame.isEmpty ? nil : frame
    }
}
