//
//  TunnelListView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// The tunnel list view in the dashboard.
///
/// TunnelListView displays all tunnels with:
/// - Header with title and "New Tunnel" button
/// - Search field with debouncing
/// - Refresh button
/// - Tunnel rows with status, name, type, service, and controls
/// - Empty state when no tunnels exist
/// - Loading state during data fetch
struct TunnelListView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @State private var viewModel = TunnelListViewModel()
    @State private var refreshTask: Task<Void, Never>?
    @State private var searchDebouncer = Debouncer(delay: 0.3)

    // MARK: - Callbacks

    /// Called when a tunnel is selected.
    let onTunnelSelected: (Tunnel) -> Void

    /// Called when the new tunnel button is tapped.
    let onNewTunnel: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            Divider()

            contentSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.appState = appState
        }
        .task {
            if !viewModel.hasLoaded {
                await viewModel.loadTunnels()
            }
        }
        .onChange(of: appState.tunnels) { _, _ in
            // Update when tunnels change
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tunnel List")
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Title row
            HStack {
                Text("Tunnels")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button(action: onNewTunnel) {
                    Label("New Tunnel", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.regular)
                .accessibilityLabel("Create new tunnel")
                .accessibilityHint("Opens the tunnel creation wizard")
            }

            // Search and refresh row
            HStack(spacing: 12) {
                // Search field with debouncing
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    TextField("Search tunnels...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search tunnels")
                        .accessibilityHint("Type to filter tunnels by name")
                        .onChange(of: viewModel.searchText) { _, newValue in
                            searchDebouncer.debounce {
                                viewModel.updateSearch(newValue)
                            }
                        }

                    if !viewModel.searchText.isEmpty {
                        Button(action: viewModel.clearSearch) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .animation(.easeInOut(duration: 0.2), value: viewModel.searchText.isEmpty)

                // Refresh button
                Button(action: refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                        .animation(
                            viewModel.isLoading
                                ? .linear(duration: 1).repeatForever(autoreverses: false)
                                : .default,
                            value: viewModel.isLoading
                        )
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
                .accessibilityLabel("Refresh tunnels")
                .accessibilityHint("Reloads the tunnel list from Cloudflare")

                // Tunnel count
                if !viewModel.isEmpty {
                    Text(viewModel.tunnelCountText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(viewModel.tunnelCountText)")
                }
            }

            // Last sync info
            if let lastSync = appState.lastTunnelSync {
                HStack {
                    Spacer()
                    Text("Updated \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Last updated \(lastSync, style: .relative)")
                }
            }
        }
        .padding()
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.isLoading && !viewModel.hasLoaded {
            loadingView
                .transition(.opacity)
        } else if let error = viewModel.error {
            errorView(error)
                .transition(.opacity)
        } else if viewModel.isEmpty {
            emptyStateView
                .transition(.opacity)
        } else if viewModel.isFilteredEmpty {
            noResultsView
                .transition(.opacity)
        } else {
            tunnelListView
                .transition(.opacity)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        CenteredLoadingView(message: "Loading tunnels...")
            .accessibilityLabel("Loading tunnels")
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ErrorView(
            title: "Failed to Load Tunnels",
            description: error,
            retryAction: {
                await viewModel.loadTunnels()
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: Failed to load tunnels. \(error)")
        .accessibilityHint("Double tap the retry button to try again")
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "network.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Tunnels Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create your first tunnel to expose local services\nthrough Cloudflare's network.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onNewTunnel) {
                Label("Create Tunnel", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .padding(.top, 8)
            .accessibilityHint("Opens the tunnel creation wizard")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No tunnels yet. Create your first tunnel to expose local services through Cloudflare's network.")
    }

    // MARK: - No Results View

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("No Matching Tunnels")
                .font(.headline)

            Text("No tunnels match \"\(viewModel.searchText)\"")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Clear Search") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.clearSearch()
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
            .accessibilityHint("Clears the search field to show all tunnels")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No matching tunnels. No tunnels match \(viewModel.searchText).")
    }

    // MARK: - Tunnel List View

    private var tunnelListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.filteredTunnels) { tunnel in
                    TunnelRowView(
                        tunnel: tunnel,
                        localState: viewModel.localState(for: tunnel),
                        onSelect: { onTunnelSelected(tunnel) },
                        onToggle: {
                            Task {
                                await viewModel.toggleTunnel(tunnel)
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                }
            }
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.2), value: viewModel.filteredTunnels.map(\.id))
        }
        .refreshable {
            await viewModel.refresh()
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading && viewModel.hasLoaded {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.1), radius: 4)
                )
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Refreshing tunnel list")
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
    }

    // MARK: - Actions

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            await viewModel.refresh()
        }
    }
}

// MARK: - Preview

#Preview("Tunnel List - With Tunnels") {
    let appState = AppState()
    appState.isAuthenticated = true
    appState.tunnels = [.preview, .inactivePreview]
    appState.localTunnelStates = [
        "preview-tunnel-id": .running(pid: 1234, startedAt: Date().addingTimeInterval(-3600))
    ]

    return TunnelListView(
        onTunnelSelected: { _ in },
        onNewTunnel: { }
    )
    .environment(appState)
    .frame(width: 700, height: 500)
}

#Preview("Tunnel List - Empty") {
    let appState = AppState()
    appState.isAuthenticated = true
    appState.tunnels = []

    return TunnelListView(
        onTunnelSelected: { _ in },
        onNewTunnel: { }
    )
    .environment(appState)
    .frame(width: 700, height: 500)
}
