//
//  LogsViewModel.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI
import os.log

// MARK: - LogsViewModel

/// View model for the logs view.
///
/// LogsViewModel manages the log display state including:
/// - Log entry filtering by tunnel and level
/// - Text search
/// - Auto-scroll behavior
/// - Real-time log streaming
///
/// ## Usage
/// ```swift
/// @State private var viewModel = LogsViewModel()
///
/// LogsView()
///     .onAppear { viewModel.setup(appState: appState) }
/// ```
@Observable
@MainActor
final class LogsViewModel {

    // MARK: - Filter State

    /// The currently selected tunnel ID for filtering (nil = all tunnels).
    var selectedTunnelId: String?

    /// The selected log levels for filtering (empty = all levels).
    var selectedLevels: Set<LogLevel> = Set(LogLevel.allCases)

    /// The search text for filtering log messages.
    var searchText: String = ""

    // MARK: - Display State

    /// All log entries currently displayed (filtered).
    var displayedEntries: [LogEntry] = []

    /// Whether auto-scroll is enabled.
    var isAutoScrollEnabled: Bool = true

    /// Whether logs are currently being loaded.
    var isLoading: Bool = false

    /// Whether the view is actively streaming new logs.
    var isStreaming: Bool = false

    /// The scroll position for programmatic scrolling.
    var scrollToBottom: Bool = false

    // MARK: - Statistics

    /// Total number of entries (before filtering).
    var totalEntryCount: Int = 0

    /// Number of displayed entries (after filtering).
    var displayedEntryCount: Int {
        displayedEntries.count
    }

    /// Buffer statistics.
    var bufferStatistics: LogBuffer.BufferStatistics?

    // MARK: - Dependencies

    /// Reference to the app state.
    weak var appState: AppState?

    /// The log stream manager.
    private var logStreamManager: LogStreamManager?

    /// Task for streaming new logs.
    private var streamTask: Task<Void, Never>?

    /// Logger for view model operations.
    private let logger = Logger.ui

    // MARK: - Computed Properties

    /// Available tunnels for the tunnel picker.
    var availableTunnels: [TunnelOption] {
        var options: [TunnelOption] = [TunnelOption(id: nil, name: "All Tunnels")]

        if let tunnels = appState?.tunnels {
            options += tunnels.map { TunnelOption(id: $0.id, name: $0.name) }
        }

        return options
    }

    /// The name of the currently selected tunnel.
    var selectedTunnelName: String {
        if let tunnelId = selectedTunnelId,
           let tunnel = appState?.tunnels.first(where: { $0.id == tunnelId }) {
            return tunnel.name
        }
        return "All Tunnels"
    }

    /// Whether there are any logs to display.
    var hasLogs: Bool {
        !displayedEntries.isEmpty
    }

    /// Whether filtering is active.
    var isFiltering: Bool {
        selectedTunnelId != nil ||
        selectedLevels.count < LogLevel.allCases.count ||
        !searchText.isEmpty
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    /// Sets up the view model with the app state.
    ///
    /// - Parameter appState: The application state.
    func setup(appState: AppState) {
        self.appState = appState
        self.logStreamManager = LogStreamManager()

        // Start streaming logs if service container is available
        if let container = appState.serviceContainer {
            startLogStreaming(from: container)
        }

        // Load initial entries
        Task {
            await loadEntries()
        }
    }

    /// Updates the log stream manager reference.
    ///
    /// - Parameter manager: The log stream manager.
    func setLogStreamManager(_ manager: LogStreamManager) {
        self.logStreamManager = manager
    }

    // MARK: - Actions

    /// Refreshes the displayed log entries.
    func refresh() async {
        await loadEntries()
    }

    /// Clears all logs.
    func clearLogs() async {
        guard let manager = logStreamManager else { return }
        await manager.clearAllLogs()
        displayedEntries = []
        totalEntryCount = 0
        logger.info("Logs cleared")
    }

    /// Clears logs for the selected tunnel.
    func clearSelectedTunnelLogs() async {
        guard let manager = logStreamManager,
              let tunnelId = selectedTunnelId else { return }
        await manager.clearLogs(for: tunnelId)
        await loadEntries()
        logger.info("Logs cleared for tunnel: \(tunnelId)")
    }

    /// Exports logs with a save panel.
    func exportLogs() async {
        let result = await LogExporter.exportWithSavePanel(
            entries: displayedEntries,
            tunnelName: selectedTunnelId != nil ? selectedTunnelName : nil
        )

        switch result {
        case .success(let url):
            logger.info("Logs exported to: \(url.path)")
        case .cancelled:
            logger.debug("Log export cancelled")
        case .failed(let error):
            logger.error("Log export failed: \(error.localizedDescription)")
        }
    }

    /// Copies all displayed logs to clipboard.
    func copyLogsToClipboard() {
        let success = LogExporter.copyToClipboard(
            entries: displayedEntries,
            tunnelName: selectedTunnelId != nil ? selectedTunnelName : nil
        )

        if success {
            logger.debug("Logs copied to clipboard")
        }
    }

    /// Toggles a log level filter.
    ///
    /// - Parameter level: The log level to toggle.
    func toggleLevel(_ level: LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }

        Task {
            await loadEntries()
        }
    }

    /// Selects all log levels.
    func selectAllLevels() {
        selectedLevels = Set(LogLevel.allCases)
        Task {
            await loadEntries()
        }
    }

    /// Deselects all log levels.
    func deselectAllLevels() {
        selectedLevels = []
        Task {
            await loadEntries()
        }
    }

    /// Selects a tunnel for filtering.
    ///
    /// - Parameter tunnelId: The tunnel ID (nil for all tunnels).
    func selectTunnel(_ tunnelId: String?) {
        selectedTunnelId = tunnelId
        Task {
            await loadEntries()
        }
    }

    /// Updates the search text.
    ///
    /// - Parameter text: The new search text.
    func updateSearchText(_ text: String) {
        searchText = text
        Task {
            await loadEntries()
        }
    }

    /// Clears all filters.
    func clearFilters() {
        selectedTunnelId = nil
        selectedLevels = Set(LogLevel.allCases)
        searchText = ""
        Task {
            await loadEntries()
        }
    }

    /// Toggles auto-scroll.
    func toggleAutoScroll() {
        isAutoScrollEnabled.toggle()
        if isAutoScrollEnabled {
            scrollToBottom = true
        }
    }

    /// Scrolls to the bottom of the log list.
    func scrollToLatest() {
        scrollToBottom = true
    }

    // MARK: - Private Methods

    /// Loads entries from the log stream manager.
    private func loadEntries() async {
        guard let manager = logStreamManager else { return }

        isLoading = true
        defer { isLoading = false }

        displayedEntries = await manager.getFilteredEntries(
            tunnelId: selectedTunnelId,
            levels: selectedLevels,
            searchText: searchText
        )

        totalEntryCount = await manager.getTotalEntryCount()
        bufferStatistics = await manager.getGlobalStatistics()
    }

    /// Starts streaming logs from the service container.
    private func startLogStreaming(from container: ServiceContainer) {
        // Cancel any existing stream
        streamTask?.cancel()

        isStreaming = true

        streamTask = Task {
            for await event in await container.eventStream() {
                guard !Task.isCancelled else { break }

                switch event {
                case .logReceived(let tunnelId, let line):
                    await processNewLog(line, tunnelId: tunnelId)
                default:
                    break
                }
            }
        }
    }

    /// Processes a new log line.
    private func processNewLog(_ line: String, tunnelId: String) async {
        guard let manager = logStreamManager else { return }

        // Add to the log manager
        await manager.processLogLine(line, tunnelId: tunnelId)

        // Check if the entry matches current filters
        if let entry = LogParser.parse(line, tunnelId: tunnelId) {
            if matchesFilters(entry) {
                displayedEntries.append(entry)
                totalEntryCount += 1

                // Trigger scroll if auto-scroll is enabled
                if isAutoScrollEnabled {
                    scrollToBottom = true
                }
            }
        }
    }

    /// Checks if an entry matches current filters.
    private func matchesFilters(_ entry: LogEntry) -> Bool {
        // Check tunnel filter
        if let selectedTunnelId = selectedTunnelId, entry.tunnelId != selectedTunnelId {
            return false
        }

        // Check level filter
        if !selectedLevels.isEmpty && !selectedLevels.contains(entry.level) {
            return false
        }

        // Check search text
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            if !entry.message.lowercased().contains(searchLower) &&
               !entry.rawLine.lowercased().contains(searchLower) {
                return false
            }
        }

        return true
    }

    /// Stops log streaming.
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
}

// MARK: - Supporting Types

extension LogsViewModel {
    /// Represents a tunnel option in the picker.
    struct TunnelOption: Identifiable, Hashable {
        let id: String?
        let name: String

        var displayName: String {
            name
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension LogsViewModel {
    /// Creates a view model with preview data.
    static var preview: LogsViewModel {
        let viewModel = LogsViewModel()
        viewModel.displayedEntries = LogEntry.previewEntries
        viewModel.totalEntryCount = LogEntry.previewEntries.count
        return viewModel
    }
}
#endif
