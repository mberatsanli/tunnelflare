//
//  TunnelDetailView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// The detailed view for a single tunnel.
///
/// TunnelDetailView displays comprehensive information about a tunnel:
/// - Back navigation
/// - Tunnel name header and status badge
/// - Control buttons (Stop/Restart for local, disabled for remote)
/// - Tab bar: Overview, Ingress Rules, Logs
/// - Overview: ID (copyable), created date, connectors list
/// - Ingress Rules: read-only list of hostname->service mappings
/// - Logs: embedded log viewer for this tunnel
struct TunnelDetailView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - Properties

    /// The tunnel to display.
    let tunnel: Tunnel

    /// Called when back navigation is triggered.
    let onBack: () -> Void

    // MARK: - State

    @State private var viewModel = TunnelDetailViewModel()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Tab content
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.setup(tunnel: tunnel, appState: appState)
        }
        .task {
            await viewModel.loadConfiguration()
        }
        .onChange(of: appState.localTunnelStates[tunnel.id]) { _, _ in
            viewModel.updateLocalState()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Navigation bar
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Tunnels")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()
            }

            // Title and status
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text(tunnel.name)
                            .font(.title)
                            .fontWeight(.bold)

                        StatusBadge(
                            text: viewModel.statusText,
                            color: viewModel.statusColor
                        )
                    }

                    HStack(spacing: 8) {
                        if viewModel.isRemote {
                            Label("Running on another machine", systemImage: "desktopcomputer")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Control buttons
                controlButtons
            }

            // Tab picker
            Picker("Tab", selection: $viewModel.selectedTab) {
                ForEach(TunnelDetailViewModel.DetailTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding()
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            // Visit button (if has public hostname)
            if let hostname = viewModel.publicHostname {
                Button(action: {
                    viewModel.visitHostname()
                }) {
                    Label("Visit", systemImage: "safari")
                }
                .buttonStyle(.bordered)
                .help("Open https://\(hostname) in browser")
            }

            if viewModel.isRunningLocally {
                // Stop button
                Button(action: {
                    Task { await viewModel.stopTunnel() }
                }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.controlsDisabled)

                // Restart button
                Button(action: {
                    Task { await viewModel.restartTunnel() }
                }) {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.controlsDisabled)
            } else if !viewModel.isRemote {
                // Start button
                Button(action: {
                    Task { await viewModel.startTunnel() }
                }) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(viewModel.controlsDisabled)
            }
        }
        .disabled(viewModel.isPerformingAction)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch viewModel.selectedTab {
        case .overview:
            overviewTab
        case .ingressRules:
            ingressRulesTab
        case .logs:
            logsTab
        }
    }

    // MARK: - Overview Tab

    private var overviewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Tunnel Information
                DetailSection(title: "Tunnel Information") {
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(label: "Tunnel ID") {
                            HStack(spacing: 8) {
                                Text(tunnel.id)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)

                                Button(action: viewModel.copyTunnelId) {
                                    Image(systemName: viewModel.hasCopiedId ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(viewModel.hasCopiedId ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Copy Tunnel ID")
                            }
                        }

                        DetailRow(label: "Created") {
                            Text(viewModel.createdAtText)
                        }

                        DetailRow(label: "Status") {
                            HStack(spacing: 6) {
                                StatusIndicator(runState: viewModel.localState, size: .small)
                                Text(viewModel.statusText)
                            }
                        }
                    }
                }

                // Connectors
                DetailSection(title: "Connectors") {
                    if tunnel.connections.isEmpty {
                        Text("No active connectors")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(tunnel.connections) { connection in
                                ConnectorRow(connection: connection)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Ingress Rules Tab

    private var ingressRulesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoadingConfiguration {
                    CenteredLoadingView(message: "Loading configuration...")
                } else if viewModel.ingressRules.isEmpty {
                    emptyIngressRules
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(viewModel.ingressRules.enumerated()), id: \.element.id) { index, rule in
                            IngressRuleRow(rule: rule, index: index)
                        }
                    }
                    .background(Color(nsColor: .separatorColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
    }

    private var emptyIngressRules: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No Ingress Rules")
                .font(.headline)

            Text("Configure ingress rules to route traffic to your services.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Logs Tab

    private var logsTab: some View {
        VStack(spacing: 0) {
            // Mode picker (Active / History)
            logModePicker
                .padding()

            Divider()

            // Content based on mode
            if viewModel.logViewMode == .active {
                activeLogsView
            } else {
                logHistoryView
            }
        }
        .onAppear {
            if viewModel.selectedTab == .logs {
                if viewModel.isRunningLocally {
                    viewModel.startLogRefresh()
                }
                Task {
                    await viewModel.loadActiveLogFilePath()
                    await viewModel.loadLogHistory()
                }
            }
        }
        .onDisappear {
            viewModel.stopLogRefresh()
        }
        .onChange(of: viewModel.selectedTab) { _, newTab in
            if newTab == .logs {
                if viewModel.isRunningLocally {
                    viewModel.startLogRefresh()
                }
                Task {
                    await viewModel.loadActiveLogFilePath()
                    await viewModel.loadLogHistory()
                }
            } else {
                viewModel.stopLogRefresh()
            }
        }
        .onChange(of: viewModel.logViewMode) { _, newMode in
            if newMode == .active && viewModel.isRunningLocally {
                viewModel.startLogRefresh()
            } else if newMode == .history {
                viewModel.stopLogRefresh()
            }
        }
    }

    // MARK: - Log Mode Picker

    private var logModePicker: some View {
        HStack {
            Picker("Log View", selection: $viewModel.logViewMode) {
                ForEach(TunnelDetailViewModel.LogViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            // Open logs folder button
            Button(action: {
                viewModel.openLogsDirectory()
            }) {
                Label("Open Logs Folder", systemImage: "folder")
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Active Logs View

    private var activeLogsView: some View {
        VStack(spacing: 0) {
            if viewModel.isRunningLocally {
                // Active log file path
                if let logPath = viewModel.activeLogFilePath {
                    activeLogFilePathBar(logPath)
                }

                // Logs header
                logsHeader
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                // Log entries
                if viewModel.logEntries.isEmpty {
                    emptyLogsView
                } else {
                    // Show terminal or row-by-row based on setting
                    if appState.settings.logDisplayMode == .terminal {
                        terminalStyleLogs
                    } else {
                        rowStyleLogs
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    Text("No Active Logs")
                        .font(.headline)

                    Text("Start the tunnel locally to view live logs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if !viewModel.logHistoryFiles.isEmpty {
                        Text("Check the History tab for previous logs.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    private func activeLogFilePathBar(_ path: URL) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.green)

            Text("Logging to:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(path.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()

            Button(action: {
                viewModel.revealLogFileInFinder(path)
            }) {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help("Reveal in Finder")
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.1))
    }

    // MARK: - Log History View

    private var logHistoryView: some View {
        HStack(spacing: 0) {
            // Log file list
            logHistoryList
                .frame(width: 280)
                .clipped()

            Divider()

            // Log content viewer
            logHistoryContent
                .frame(maxWidth: .infinity)
        }
    }

    private var logHistoryList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Previous Sessions")
                    .font(.headline)

                Spacer()

                Button(action: {
                    Task { await viewModel.loadLogHistory() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            if viewModel.logHistoryFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)

                    Text("No Log History")
                        .font(.subheadline)

                    Text("Previous tunnel sessions will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.logHistoryFiles) { file in
                            LogHistoryListItem(
                                file: file,
                                isSelected: viewModel.selectedHistoryFile?.id == file.id,
                                onTap: {
                                    Task { await viewModel.loadHistoryLogContent(file) }
                                },
                                onReveal: {
                                    viewModel.revealLogFileInFinder(file.url)
                                },
                                onDelete: {
                                    Task { await viewModel.deleteHistoryLogFile(file) }
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var logHistoryContent: some View {
        VStack(spacing: 0) {
            if let file = viewModel.selectedHistoryFile {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session: \(file.sessionTimestamp)")
                            .font(.headline)

                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.historyLogContent, forType: .string)
                    }) {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)

                    Button(action: {
                        viewModel.revealLogFileInFinder(file.url)
                    }) {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.borderless)
                }
                .padding()

                Divider()

                // Content
                if viewModel.isLoadingHistoryContent {
                    VStack {
                        ProgressView()
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(viewModel.historyLogContent)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)

                    Text("Select a Log File")
                        .font(.headline)

                    Text("Choose a session from the list to view its logs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    // MARK: - Logs Header

    private var logsHeader: some View {
        HStack {
            if viewModel.isSelectionMode {
                Text("\(viewModel.selectedLogCount) of \(viewModel.logEntries.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(viewModel.logEntries.count) log entries")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isSelectionMode {
                // Selection mode controls (for row-by-row mode)
                Button(action: {
                    if viewModel.selectedLogCount == viewModel.logEntries.count {
                        viewModel.deselectAllLogs()
                    } else {
                        viewModel.selectAllLogs()
                    }
                }) {
                    Text(viewModel.selectedLogCount == viewModel.logEntries.count ? "Deselect All" : "Select All")
                }
                .buttonStyle(.borderless)

                Button(action: {
                    viewModel.copySelectedLogs()
                }) {
                    Label("Copy Selected", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.selectedLogCount == 0)

                Button(action: {
                    viewModel.toggleSelectionMode()
                }) {
                    Text("Done")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                // Normal mode controls
                if appState.settings.logDisplayMode == .rows {
                    Button(action: {
                        viewModel.toggleSelectionMode()
                    }) {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(viewModel.logEntries.isEmpty)
                }

                // Copy All button
                Button(action: {
                    viewModel.copyAllLogs()
                }) {
                    Label("Copy All", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.logEntries.isEmpty)

                // Clear All button
                Button(action: {
                    viewModel.clearAllLogs()
                }) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.logEntries.isEmpty)

                Button(action: {
                    Task { await viewModel.loadLogs() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoadingLogs)
            }
        }
    }

    // MARK: - Empty Logs View

    private var emptyLogsView: some View {
        VStack(spacing: 12) {
            if viewModel.isLoadingLogs {
                ProgressView()
                Text("Loading logs...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No logs yet")
                    .font(.headline)
                Text("Logs will appear here as the tunnel runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Terminal Style Logs

    private var terminalStyleLogs: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(formattedLogText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .id("terminal-bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: viewModel.logEntries.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }

    /// Formats all log entries as a single string for terminal-style display.
    private var formattedLogText: AttributedString {
        var result = AttributedString()

        for entry in viewModel.logEntries {
            // Timestamp
            var timestamp = AttributedString("[\(entry.formattedTime)] ")
            timestamp.foregroundColor = Color.secondary

            // Level
            var level = AttributedString("[\(entry.level.rawValue.uppercased())] ")
            level.foregroundColor = entry.level.color

            // Message
            var message = AttributedString(entry.message + "\n")
            message.foregroundColor = Color.primary

            result += timestamp + level + message
        }

        return result
    }

    // MARK: - Row Style Logs

    private var rowStyleLogs: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.logEntries) { entry in
                        LogEntryRow(
                            entry: entry,
                            isSelectionMode: viewModel.isSelectionMode,
                            isSelected: viewModel.isLogSelected(entry),
                            onToggleSelection: {
                                viewModel.toggleLogSelection(entry)
                            }
                        )
                        .id(entry.id)
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: viewModel.logEntries.count) { _, _ in
                if let lastEntry = viewModel.logEntries.last {
                    withAnimation {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

/// A row displaying a log entry.
struct LogEntryRow: View {
    let entry: LogEntry
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelection: (() -> Void)?

    @State private var isHovered: Bool = false
    @State private var showCopied: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Checkbox for selection mode
            if isSelectionMode {
                Button(action: {
                    onToggleSelection?()
                }) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? .blue : .secondary)
                }
                .buttonStyle(.plain)
            }

            Text(entry.formattedTime)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Circle()
                .fill(entry.level.color)
                .frame(width: 6, height: 6)
                .padding(.top, 4)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            Spacer()

            // Copy button (visible on hover, only in normal mode)
            if isHovered && !isSelectionMode {
                Button(action: copyLogEntry) {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(showCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy log entry")
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            isSelected ? Color.blue.opacity(0.15) :
            (isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection?()
            }
        }
    }

    private func copyLogEntry() {
        let text = "[\(entry.formattedTime)] [\(entry.level.rawValue.uppercased())] \(entry.message)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        showCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            showCopied = false
        }
    }
}

// MARK: - Supporting Views

/// A status badge view.
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A section container for detail views.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A label-value row for detail views.
struct DetailRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            content()

            Spacer()
        }
    }
}

/// A row displaying connector information.
struct ConnectorRow: View {
    let connection: Connection

    var body: some View {
        HStack(spacing: 12) {
            StatusIndicator(status: connection.isHealthy ? .connected : .error, size: .small)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Connector")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    BadgeView(text: connection.coloName, color: .blue)
                }

                HStack(spacing: 12) {
                    Text(connection.connectorInfo)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Connected \(connection.formattedDuration) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A row displaying an ingress rule.
struct IngressRuleRow: View {
    let rule: IngressRule
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            // Rule number
            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Hostname
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayHostname)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(rule.isCatchAll ? .secondary : .primary)

                if rule.isCatchAll {
                    Text("Catch-all rule")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Service
            HStack(spacing: 6) {
                Image(systemName: rule.serviceType.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(rule.service)
                    .font(.system(.subheadline, design: .monospaced))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// A list item for log history with full-width selection background.
struct LogHistoryListItem: View {
    let file: LogHistoryFile
    let isSelected: Bool
    let onTap: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(isSelected ? .primary : .secondary)

                        Text(file.sessionTimestamp)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    HStack(spacing: 8) {
                        Text(file.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(file.formattedSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .padding(.leading, 12)
        }
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button("Reveal in Finder", action: onReveal)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

/// A row displaying a log history file.
struct LogHistoryFileRow: View {
    let file: LogHistoryFile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)

                Text(file.sessionTimestamp)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            HStack(spacing: 8) {
                Text(file.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(file.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("Tunnel Detail") {
    let appState = AppState()
    appState.isAuthenticated = true
    appState.localTunnelStates = [
        "preview-tunnel-id": .running(pid: 1234, startedAt: Date().addingTimeInterval(-3600))
    ]

    return TunnelDetailView(
        tunnel: .preview,
        onBack: { }
    )
    .environment(appState)
    .frame(width: 800, height: 600)
}
