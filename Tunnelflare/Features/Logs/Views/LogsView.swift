//
//  LogsView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

// MARK: - LogsView

/// The main log viewer view.
///
/// LogsView provides a full-featured log viewing interface with:
/// - Tunnel selector dropdown
/// - Log level filters
/// - Text search with debouncing
/// - Auto-scroll with pause/resume
/// - Monospace, color-coded log display
/// - Export functionality
///
/// ## Performance
/// Uses LazyVStack and efficient diffing for smooth scrolling
/// with 10,000+ entries.
///
/// ## Usage
/// ```swift
/// LogsView()
///     .environment(appState)
/// ```
struct LogsView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @State private var viewModel = LogsViewModel()
    @State private var scrollViewProxy: ScrollViewProxy?
    @State private var showingExportConfirmation = false
    @State private var searchDebouncer = Debouncer(delay: 0.3)

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Filter bar
            LogFilterView(
                selectedTunnelId: $viewModel.selectedTunnelId,
                selectedLevels: $viewModel.selectedLevels,
                searchText: $viewModel.searchText,
                tunnelOptions: viewModel.availableTunnels,
                onClearFilters: { viewModel.clearFilters() }
            )
            .onChange(of: viewModel.searchText) { _, newValue in
                searchDebouncer.debounce {
                    Task { await viewModel.refresh() }
                }
            }

            Divider()

            // Log content area
            if viewModel.hasLogs {
                logListView
                    .transition(.opacity)
            } else {
                emptyStateView
                    .transition(.opacity)
            }

            Divider()

            // Footer
            footer
        }
        .onAppear {
            viewModel.setup(appState: appState)
        }
        .onDisappear {
            viewModel.stopStreaming()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Log Viewer")
    }

    // MARK: - Header

    private var header: some View {
        PageHeader(title: "Logs", actions: {
            HStack(spacing: 8) {
                // Streaming indicator
                if viewModel.isStreaming {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Live")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Live streaming enabled")
                }

                // Export button
                Button(action: { Task { await viewModel.exportLogs() } }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(!viewModel.hasLogs)
                .accessibilityLabel("Export logs")
                .accessibilityHint("Exports logs to a file")

                // More menu
                Menu {
                    Button(action: { viewModel.copyLogsToClipboard() }) {
                        Label("Copy All Logs", systemImage: "doc.on.doc")
                    }
                    .disabled(!viewModel.hasLogs)

                    Divider()

                    Button(action: { Task { await viewModel.clearLogs() } }) {
                        Label("Clear All Logs", systemImage: "trash")
                    }
                    .disabled(!viewModel.hasLogs)

                    if viewModel.selectedTunnelId != nil {
                        Button(action: { Task { await viewModel.clearSelectedTunnelLogs() } }) {
                            Label("Clear \(viewModel.selectedTunnelName) Logs", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More options")
            }
        })
    }

    // MARK: - Log List View

    private var logListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.displayedEntries) { entry in
                        LogEntryView(
                            entry: entry,
                            showTunnelId: viewModel.selectedTunnelId == nil
                        )
                        .id(entry.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(entry.level.displayName) at \(entry.formattedTime): \(entry.message)")

                        Divider()
                            .padding(.leading, 8)
                    }

                    // Scroll anchor
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
            }
            .onAppear {
                scrollViewProxy = proxy
            }
            .onChange(of: viewModel.scrollToBottom) { _, shouldScroll in
                if shouldScroll {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    viewModel.scrollToBottom = false
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .accessibilityLabel("Log entries")
        .accessibilityHint("Scroll to view log entries")
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            if viewModel.isFiltering {
                Text("No Matching Logs")
                    .font(.title2)

                Text("Try adjusting your filters or search text.")
                    .foregroundStyle(.secondary)

                Button("Clear Filters") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.clearFilters()
                    }
                }
                .accessibilityHint("Removes all filters to show all logs")
            } else if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)

                Text("Loading logs...")
                    .foregroundStyle(.secondary)
            } else {
                Text("No Logs Yet")
                    .font(.title2)

                Text("Logs will appear here when tunnels are running.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(emptyStateAccessibilityLabel)
    }

    private var emptyStateAccessibilityLabel: String {
        if viewModel.isFiltering {
            return "No matching logs. Try adjusting your filters or search text."
        } else if viewModel.isLoading {
            return "Loading logs"
        } else {
            return "No logs yet. Logs will appear when tunnels are running."
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            // Entry count
            Text(entryCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(entryCountText)

            if let stats = viewModel.bufferStatistics {
                Text(" | ")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text("\(stats.formattedSize) / \(stats.formattedMaxSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Buffer: \(stats.formattedSize) of \(stats.formattedMaxSize) used")
            }

            Spacer()

            // Auto-scroll toggle
            Toggle(isOn: $viewModel.isAutoScrollEnabled) {
                Label("Auto-scroll", systemImage: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isAutoScrollEnabled ? .primary : .secondary)
            .help(viewModel.isAutoScrollEnabled ? "Auto-scroll enabled" : "Auto-scroll disabled")
            .accessibilityLabel("Auto-scroll")
            .accessibilityValue(viewModel.isAutoScrollEnabled ? "Enabled" : "Disabled")
            .accessibilityHint("Toggle to automatically scroll to new log entries")

            // Scroll to bottom button
            Button(action: { viewModel.scrollToLatest() }) {
                Image(systemName: "arrow.down.to.line.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Scroll to latest")
            .disabled(viewModel.isAutoScrollEnabled)
            .accessibilityLabel("Scroll to bottom")
            .accessibilityHint("Scrolls to the most recent log entry")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Computed Properties

    private var entryCountText: String {
        let displayed = viewModel.displayedEntryCount
        let total = viewModel.totalEntryCount

        if viewModel.isFiltering && displayed != total {
            return "\(displayed.formatted()) of \(total.formatted()) entries"
        } else {
            return "\(total.formatted()) entries"
        }
    }
}

// MARK: - Embedded Log View

/// A compact log view for embedding in other views (e.g., tunnel detail).
struct EmbeddedLogView: View {

    let tunnelId: String

    @Environment(AppState.self) private var appState
    @State private var entries: [LogEntry] = []
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Recent Logs")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse logs" : "Expand logs")
            }

            // Log entries
            if entries.isEmpty {
                Text("No logs available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
                    .accessibilityLabel("No logs available for this tunnel")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries.suffix(isExpanded ? 50 : 10)) { entry in
                            CompactLogEntryView(entry: entry)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(entry.level.displayName): \(entry.message)")
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: isExpanded ? 300 : 150)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tunnel logs section")
    }
}

// MARK: - Preview

#Preview("Logs View") {
    let appState = AppState()
    appState.isAuthenticated = true
    appState.tunnels = [.preview, .inactivePreview]

    return LogsView()
        .environment(appState)
        .frame(width: 800, height: 600)
}

#Preview("Logs View - Empty") {
    let appState = AppState()
    appState.isAuthenticated = true

    return LogsView()
        .environment(appState)
        .frame(width: 800, height: 600)
}

#Preview("Embedded Log View") {
    EmbeddedLogView(tunnelId: "test-tunnel")
        .environment(AppState())
        .frame(width: 400)
        .padding()
}
