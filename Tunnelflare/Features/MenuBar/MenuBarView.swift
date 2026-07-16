//
//  MenuBarView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// The main SwiftUI view for the menu bar dropdown.
///
/// MenuBarView displays:
/// - Header with aggregate connection status
/// - List of tunnels (max 5, with "View All" for more)
/// - Quick actions (Start All, Stop All)
/// - Dashboard access button
/// - Quit option
///
/// ## Usage
/// This view is embedded in an NSPopover via NSHostingController
/// and managed by MenuBarController.
struct MenuBarView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    // MARK: - Properties

    /// Action to dismiss the popover.
    let dismissAction: () -> Void

    /// Maximum number of tunnels to show in the list.
    private let maxVisibleTunnels = UIConstants.maxMenuBarTunnels

    /// Maximum number of local services to show in the list.
    private let maxVisibleLocalServices = UIConstants.maxMenuBarLocalServices

    /// Shared Local Services view model (owned by AppState).
    private var localServicesViewModel: LocalServicesViewModel {
        appState.localServicesViewModel
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            statusHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 8)

            if appState.isAuthenticated {
                // Tunnel list
                tunnelSection
                    .padding(.vertical, 4)

                Divider()
                    .padding(.horizontal, 8)

                // Local dev servers detected on this machine
                localServicesSection
                    .padding(.vertical, 4)

                Divider()
                    .padding(.horizontal, 8)

                // Quick actions
                quickActionsSection
                    .padding(.vertical, 4)

                Divider()
                    .padding(.horizontal, 8)
            } else {
                // Login prompt
                loginPromptSection
                    .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 8)
            }

            // Dashboard and quit buttons
            footerSection
                .padding(.vertical, 4)
                .padding(.bottom, 8)
        }
        .frame(width: 320)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cloudflare Tunnel Menu")
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 10) {
            // Status indicator dot
            Circle()
                .fill(StatusIconManager.color(for: appState.aggregateStatus))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Refresh button
            if appState.isAuthenticated {
                Button(action: refreshTunnels) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh tunnel status")
                .disabled(appState.isLoadingTunnels)
                .accessibilityLabel("Refresh tunnels")
                .accessibilityHint("Double tap to refresh tunnel status")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(statusTitle). \(statusSubtitle)")
    }

    private var statusTitle: String {
        switch appState.aggregateStatus {
        case .connected:
            return "Connected"
        case .partial:
            return "Partially Connected"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .error:
            return "Error"
        case .unauthenticated:
            return "Not Logged In"
        }
    }

    private var statusSubtitle: String {
        guard appState.isAuthenticated else {
            return "Log in to manage tunnels"
        }

        let running = appState.localRunningTunnelCount
        let total = appState.tunnels.count

        if running == 0 && total == 0 {
            return "No tunnels configured"
        } else if running == 0 {
            return "\(total) tunnel\(total == 1 ? "" : "s") available"
        } else {
            return "\(running) of \(total) tunnel\(total == 1 ? "" : "s") running"
        }
    }

    // MARK: - Tunnel Section

    private var tunnelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.tunnels.isEmpty {
                emptyTunnelView
            } else {
                ForEach(visibleTunnels) { tunnel in
                    TunnelRowItem(
                        tunnel: tunnel,
                        localState: appState.localTunnelStates[tunnel.id],
                        onTap: { selectTunnel(tunnel) },
                        onToggle: { toggleTunnel(tunnel) }
                    )
                }

                if appState.tunnels.count > maxVisibleTunnels {
                    viewAllButton
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tunnels list")
    }

    private var visibleTunnels: [Tunnel] {
        Array(appState.tunnels.sorted().prefix(maxVisibleTunnels))
    }

    private var emptyTunnelView: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "network.slash")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("No tunnels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Create Tunnel") {
                    createTunnel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Double tap to create a new tunnel")
            }
            .padding(.vertical, 16)
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No tunnels configured. Create tunnel button available.")
    }

    private var viewAllButton: some View {
        Button(action: openDashboardToTunnels) {
            HStack {
                Text("View All (\(appState.tunnels.count) tunnels)")
                    .font(.subheadline)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View all \(appState.tunnels.count) tunnels")
        .accessibilityHint("Double tap to open dashboard and view all tunnels")
    }

    // MARK: - Local Services Section

    private var localServicesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Text("Local Services")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task {
                        await localServicesViewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh local services")
                .disabled(localServicesViewModel.isScanning)
                .accessibilityLabel("Refresh local services")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            if visibleLocalServices.isEmpty {
                Text(localServicesViewModel.hasScanned
                        ? "No local dev servers detected"
                        : "Scanning...")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            } else {
                ForEach(visibleLocalServices) { service in
                    LocalServiceMenuRow(
                        service: service,
                        onCopyURL: { localServicesViewModel.copyURL(for: service) },
                        onOpenInBrowser: { localServicesViewModel.openInBrowser(service) },
                        onCreateTunnel: { createTunnel(for: service) }
                    )
                }
            }
        }
        .onAppear {
            // Refresh on open and keep polling while the popover is visible.
            // Polling (rather than a one-shot refresh) also keeps the list
            // fresh if the popover content stays in the view hierarchy
            // across opens.
            localServicesViewModel.startPolling()
        }
        .onDisappear {
            localServicesViewModel.stopPolling()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Local services list")
    }

    private var visibleLocalServices: [LocalService] {
        Array(localServicesViewModel.services.prefix(maxVisibleLocalServices))
    }

    // MARK: - Login Prompt Section

    private var loginPromptSection: some View {
        VStack(spacing: 12) {
            Image("TunnelIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            Text("Log in to manage your Cloudflare Tunnels")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Log In") {
                openDashboard()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.regular)
            .accessibilityHint("Double tap to open login")
        }
        .padding()
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Not logged in. Log in to manage your Cloudflare Tunnels.")
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarActionButton(
                title: "Start All",
                systemImage: "play.fill",
                action: startAllTunnels,
                disabled: !hasStoppedTunnels
            )
            .accessibilityLabel("Start all tunnels")
            .accessibilityHint(hasStoppedTunnels ? "Double tap to start all stopped tunnels" : "No stopped tunnels to start")

            MenuBarActionButton(
                title: "Stop All",
                systemImage: "stop.fill",
                action: stopAllTunnels,
                disabled: !hasRunningTunnels
            )
            .accessibilityLabel("Stop all tunnels")
            .accessibilityHint(hasRunningTunnels ? "Double tap to stop all running tunnels" : "No running tunnels to stop")
        }
    }

    private var hasRunningTunnels: Bool {
        appState.localTunnelStates.values.contains { $0.isRunning }
    }

    private var hasStoppedTunnels: Bool {
        let runningIds = Set(appState.localTunnelStates.filter { $0.value.isRunning }.keys)
        return appState.tunnels.contains { !runningIds.contains($0.id) }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarActionButton(
                title: "Open Dashboard...",
                systemImage: "square.grid.2x2",
                shortcut: "D",
                action: openDashboard
            )
            .accessibilityLabel("Open Dashboard")
            .accessibilityHint("Double tap or press Command D to open the dashboard window")

            Divider()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            MenuBarActionButton(
                title: "Check for Updates…",
                systemImage: "arrow.down.circle",
                action: checkForUpdates,
                disabled: !UpdaterService.shared.canCheckForUpdates
            )
            .accessibilityLabel("Check for Updates")
            .accessibilityHint("Double tap to check for a new version of Tunnelflare")

            MenuBarActionButton(
                title: "Quit Cloudflare Tunnel UI",
                systemImage: "power",
                shortcut: "Q",
                action: quitApp
            )
            .accessibilityLabel("Quit application")
            .accessibilityHint("Double tap or press Command Q to quit the application")
        }
    }

    // MARK: - Actions

    private func refreshTunnels() {
        Task {
            await appState.refreshAllTunnels()
        }
    }

    private func checkForUpdates() {
        UpdaterService.shared.checkForUpdates()
    }

    private func selectTunnel(_ tunnel: Tunnel) {
        appState.selectedTunnelId = tunnel.id
        appState.pendingTunnelDetailNavigation = tunnel.id
        openDashboard()
    }

    private func toggleTunnel(_ tunnel: Tunnel) {
        guard let state = appState.localTunnelStates[tunnel.id] else {
            // Not running locally, start it
            startTunnel(tunnel)
            return
        }

        if state.isRunning {
            stopTunnel(tunnel)
        } else {
            startTunnel(tunnel)
        }
    }

    private func startTunnel(_ tunnel: Tunnel) {
        Task {
            do {
                try await appState.startTunnel(tunnelId: tunnel.id)
            } catch {
                // Error handling is done in appState
            }
        }
    }

    private func stopTunnel(_ tunnel: Tunnel) {
        Task {
            await appState.stopTunnel(tunnelId: tunnel.id)
        }
    }

    private func startAllTunnels() {
        for tunnel in appState.tunnels {
            if appState.localTunnelStates[tunnel.id]?.isRunning != true {
                startTunnel(tunnel)
            }
        }
    }

    private func stopAllTunnels() {
        for tunnel in appState.tunnels {
            if appState.localTunnelStates[tunnel.id]?.isRunning == true {
                stopTunnel(tunnel)
            }
        }
    }

    private func createTunnel() {
        appState.isShowingNewTunnelWizard = true
        openDashboard()
    }

    private func createTunnel(for service: LocalService) {
        localServicesViewModel.createTunnel(for: service, appState: appState)
        openDashboard()
    }

    private func openDashboard() {
        dismissAction()
        openWindow(id: WindowIdentifier.dashboard)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openDashboardToTunnels() {
        appState.selectedNavigation = .tunnels
        openDashboard()
    }

    private func quitApp() {
        dismissAction()
        NSApp.terminate(nil)
    }
}

// MARK: - Tunnel Row Item

/// A single tunnel row in the menu bar dropdown.
struct TunnelRowItem: View {
    let tunnel: Tunnel
    let localState: TunnelRunState?
    let onTap: () -> Void
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Status indicator
                statusIndicator
                    .accessibilityHidden(true)

                // Tunnel info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(tunnel.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)

                        // Type badge
                        typeBadge
                    }

                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Toggle button
                if canToggle {
                    toggleButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view details")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityDescription: String {
        var description = "Tunnel \(tunnel.name). "
        description += statusText + ". "
        if isRunningLocally {
            description += "Running locally."
        } else if tunnel.isActive {
            description += "Running remotely."
        }
        return description
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        guard let state = localState else {
            return tunnel.isActive ? .green.opacity(0.5) : .gray
        }

        switch state {
        case .running:
            return .green
        case .starting, .stopping:
            return .yellow
        case .error:
            return .red
        case .stopped:
            return .gray
        }
    }

    private var statusText: String {
        guard let state = localState else {
            if tunnel.isActive {
                return "Running remotely"
            }
            return "Not connected"
        }

        switch state {
        case .running(_, let startedAt):
            let duration = Date().timeIntervalSince(startedAt)
            return "Running for \(formatDuration(duration))"
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        case .error(let message):
            return message
        case .stopped:
            return "Stopped"
        }
    }

    private var typeBadge: some View {
        Group {
            if isRunningLocally {
                Text("Local")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else if tunnel.isActive {
                Text("Remote")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.gray.opacity(0.2))
                    .foregroundStyle(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }

    private var isRunningLocally: Bool {
        localState?.isRunning == true
    }

    private var canToggle: Bool {
        // Can toggle if it's a local tunnel or not running remotely
        localState != nil || !tunnel.isActive
    }

    private var toggleButton: some View {
        Button(action: onToggle) {
            Image(systemName: toggleButtonIcon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.gray.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isTransitioning)
        .help(toggleButtonHelp)
        .accessibilityLabel(toggleButtonHelp)
        .accessibilityHint("Double tap to \(isRunningLocally ? "stop" : "start") this tunnel")
    }

    private var toggleButtonIcon: String {
        guard let state = localState else {
            return "play.fill"
        }

        switch state {
        case .running:
            return "stop.fill"
        case .starting, .stopping:
            return "hourglass"
        case .stopped, .error:
            return "play.fill"
        }
    }

    private var toggleButtonHelp: String {
        guard let state = localState else {
            return "Start tunnel"
        }

        switch state {
        case .running:
            return "Stop tunnel"
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        case .stopped, .error:
            return "Start tunnel"
        }
    }

    private var isTransitioning: Bool {
        localState?.isTransitioning == true
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "< 1 min"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            return "\(minutes) min"
        } else if duration < 86400 {
            let hours = Int(duration / 3600)
            return "\(hours) hr"
        } else {
            let days = Int(duration / 86400)
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }
}

// MARK: - Local Service Menu Row

/// A local service row in the menu bar dropdown with a submenu of actions.
struct LocalServiceMenuRow: View {
    let service: LocalService
    let onCopyURL: () -> Void
    let onOpenInBrowser: () -> Void
    let onCreateTunnel: () -> Void

    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("Copy URL") {
                onCopyURL()
            }

            Button("Open in Browser") {
                onOpenInBrowser()
            }

            Divider()

            Button("Create Tunnel...") {
                onCreateTunnel()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: service.kind.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(service.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(service.portLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(service.displayName), port \(service.port)")
        .accessibilityHint("Opens actions: copy URL, open in browser, create tunnel")
    }
}

// MARK: - Menu Bar Action Button

/// A styled action button for the menu bar dropdown.
struct MenuBarActionButton: View {
    let title: String
    let systemImage: String
    var shortcut: String? = nil
    let action: () -> Void
    var disabled: Bool = false

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 13))

                Spacer()

                if let shortcut = shortcut {
                    Text("Cmd+\(shortcut)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isHovered && !disabled ? Color.gray.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    MenuBarView(dismissAction: {})
        .environment(AppState())
        .frame(width: 320)
}
