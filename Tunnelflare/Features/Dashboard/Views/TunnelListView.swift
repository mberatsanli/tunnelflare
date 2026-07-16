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
/// - Header with title, refresh, and "New Tunnel" button
/// - Native searchable toolbar integration
/// - Tunnel rows with status, name, type, service, and controls
/// - Empty state when no tunnels exist
/// - Loading state during data fetch
struct TunnelListView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @State private var viewModel = TunnelListViewModel()
    @State private var refreshTask: Task<Void, Never>?

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
        .searchable(
            text: $viewModel.searchText,
            placement: .toolbar,
            prompt: "Search tunnels..."
        )
        .onChange(of: viewModel.searchText) { _, newValue in
            viewModel.updateSearch(newValue)
        }
        .onAppear {
            viewModel.appState = appState
        }
        .task {
            if !viewModel.hasLoaded {
                await viewModel.loadTunnels()
            }
            // Start auto-refresh when tunnel list is loaded
            appState.startAutoRefresh()
        }
        .onDisappear {
            // Stop auto-refresh when leaving tunnel list
            appState.stopAutoRefresh()
        }
        .onChange(of: appState.tunnels) { _, _ in
            // Update when tunnels change
        }
        // Delete confirmation dialog
        .alert(
            "Delete Tunnel?",
            isPresented: $viewModel.showDeleteConfirmation,
            presenting: viewModel.tunnelToDelete
        ) { tunnel in
            Button("Cancel", role: .cancel) {
                viewModel.cancelDeleteTunnel()
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.confirmDeleteTunnel()
                }
            }
        } message: { tunnel in
            Text("Are you sure you want to delete \"\(tunnel.name)\"? This will also remove associated DNS records. This action cannot be undone.")
        }
        // Deletion error alert
        .alert(
            "Deletion Failed",
            isPresented: $viewModel.showDeletionError
        ) {
            Button("OK") {
                viewModel.dismissDeletionError()
            }
        } message: {
            if let error = viewModel.deletionError {
                Text(error)
            }
        }
        // Deletion progress sheet
        .sheet(isPresented: $viewModel.isDeletingTunnel) {
            DeletionProgressView(
                tunnelName: viewModel.tunnelToDelete?.name ?? "Tunnel",
                step: viewModel.deletionStep
            )
            .interactiveDismissDisabled()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tunnel List")
    }

    // MARK: - Header Section

    private var headerSection: some View {
        PageHeader(title: "Tunnels", actions: {
            HStack(spacing: 8) {
                // Tunnel count
                if !viewModel.isEmpty {
                    Text(viewModel.tunnelCountText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(viewModel.tunnelCountText)")
                }

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

                Button(action: onNewTunnel) {
                    Label("New Tunnel", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.regular)
                .accessibilityLabel("Create new tunnel")
                .accessibilityHint("Opens the tunnel creation wizard")
            }
        }, subtitle: {
            HStack(spacing: 6) {
                // Auto-refresh indicator
                if appState.isAutoRefreshEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Auto-refresh")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .help("Auto-refreshing every \(Int(appState.autoRefreshInterval)) seconds")
                }

                if let lastSync = appState.lastTunnelSync {
                    if appState.isAutoRefreshEnabled {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("Updated \(lastSync, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Last updated \(lastSync, style: .relative)")
                }
            }
        })
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        // Quick tunnels are ephemeral (not part of the API tunnel list),
        // so they render in their own section above the named tunnels.
        QuickTunnelSectionView()

        if !appState.quickTunnels.isEmpty {
            Divider()
        }

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
        ContentUnavailableView.search(text: viewModel.searchText)
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
                        },
                        onDelete: {
                            viewModel.requestDeleteTunnel(tunnel)
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

// MARK: - Deletion Progress View

/// A sheet view showing deletion progress with animated steps.
struct DeletionProgressView: View {
    let tunnelName: String
    let step: DeletionStep

    private let allSteps: [DeletionStep] = [
        .preparing,
        .deletingDNS,
        .deletingFromCloudflare,
        .cleaningUp,
        .completed
    ]

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: step.isFailed ? "xmark.circle.fill" : "trash.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(step.isFailed ? .red : .orange)
                    .symbolEffect(.pulse, isActive: !step.isCompleted && !step.isFailed)

                Text(step.isFailed ? "Deletion Failed" : "Deleting Tunnel")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(tunnelName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Progress steps
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(allSteps.enumerated()), id: \.offset) { index, displayStep in
                    DeletionStepRow(
                        step: displayStep,
                        currentStep: step,
                        stepIndex: index,
                        currentIndex: currentStepIndex
                    )
                }
            }
            .padding(.horizontal)

            // Error message
            if case .failed(let error) = step {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(32)
        .frame(width: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var currentStepIndex: Int {
        switch step {
        case .preparing: return 0
        case .stoppingTunnel: return 0
        case .deletingDNS: return 1
        case .deletingFromCloudflare: return 2
        case .cleaningUp: return 3
        case .completed: return 4
        case .failed: return -1
        }
    }
}

/// A single step row in the deletion progress.
struct DeletionStepRow: View {
    let step: DeletionStep
    let currentStep: DeletionStep
    let stepIndex: Int
    let currentIndex: Int

    private var state: StepState {
        if currentStep.isFailed {
            return stepIndex <= currentIndex ? .failed : .pending
        } else if stepIndex < currentIndex {
            return .completed
        } else if stepIndex == currentIndex {
            return .inProgress
        } else {
            return .pending
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(state.backgroundColor)
                    .frame(width: 24, height: 24)

                Group {
                    switch state {
                    case .completed:
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    case .inProgress:
                        ProgressView()
                            .scaleEffect(0.6)
                    case .failed:
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    case .pending:
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }

            // Step title
            Text(step.title.replacingOccurrences(of: "...", with: ""))
                .font(.subheadline)
                .foregroundStyle(state == .pending ? .secondary : .primary)

            Spacer()
        }
    }

    enum StepState {
        case pending, inProgress, completed, failed

        var backgroundColor: Color {
            switch self {
            case .pending: return Color.secondary.opacity(0.2)
            case .inProgress: return Color.orange.opacity(0.2)
            case .completed: return Color.green
            case .failed: return Color.red
            }
        }
    }
}
