//
//  TunnelDetailViewModel.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import AppKit
import Foundation
import SwiftUI

/// View model for the tunnel detail view.
///
/// TunnelDetailViewModel manages the state for viewing and controlling
/// a specific tunnel's details, including its configuration and logs.
@Observable
@MainActor
final class TunnelDetailViewModel {

    // MARK: - Types

    /// The available tabs in the detail view.
    enum DetailTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case ingressRules = "Ingress Rules"
        case logs = "Logs"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .overview: return "info.circle"
            case .ingressRules: return "arrow.triangle.branch"
            case .logs: return "doc.text"
            }
        }
    }

    // MARK: - Tunnel State

    /// The tunnel being displayed.
    var tunnel: Tunnel?

    /// The tunnel's configuration.
    var configuration: TunnelConfiguration?

    /// The local run state for this tunnel.
    var localState: TunnelRunState?

    /// Log entries for this tunnel.
    var logEntries: [LogEntry] = []

    /// Selected log entry IDs for multi-select copying.
    var selectedLogIds: Set<UUID> = []

    /// Whether selection mode is active.
    var isSelectionMode: Bool = false

    /// The public hostname for this tunnel (if any).
    var publicHostname: String?

    /// Saved ingress rules for quick display (loaded from local config).
    var savedIngressRules: [IngressRule] = []

    /// The last connected time for this tunnel.
    var lastConnectedAt: Date?

    // MARK: - Log History State

    /// The current log view mode.
    enum LogViewMode: String, CaseIterable, Identifiable {
        case active = "Active"
        case history = "History"

        var id: String { rawValue }
    }

    /// Current log view mode.
    var logViewMode: LogViewMode = .active

    /// List of historical log files for this tunnel.
    var logHistoryFiles: [LogHistoryFile] = []

    /// Currently selected historical log file.
    var selectedHistoryFile: LogHistoryFile?

    /// Content of the selected historical log file.
    var historyLogContent: String = ""

    /// Whether loading history log content.
    var isLoadingHistoryContent: Bool = false

    /// The active log file path (if logging is enabled).
    var activeLogFilePath: URL?

    // MARK: - UI State

    /// The currently selected tab.
    var selectedTab: DetailTab = .overview

    /// Whether the tunnel ID has been copied.
    var hasCopiedId: Bool = false

    /// Whether logs are being loaded.
    var isLoadingLogs: Bool = false

    /// Timer for refreshing logs.
    private var logRefreshTask: Task<Void, Never>?

    // MARK: - Loading State

    /// Whether configuration is being loaded.
    var isLoadingConfiguration: Bool = false

    /// Whether a control action is in progress.
    var isPerformingAction: Bool = false

    // MARK: - Error State

    /// The current error, if any.
    var error: String?

    // MARK: - Deletion State

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

    /// Callback when tunnel is deleted (for navigation).
    var onTunnelDeleted: (() -> Void)?

    // MARK: - Connector Cleanup State

    /// Whether the cleanup confirmation dialog is showing.
    var showCleanupConfirmation: Bool = false

    /// Whether a connection cleanup is in progress.
    var isCleaningUpConnections: Bool = false

    /// Error message from failed cleanup.
    var cleanupError: String?

    /// Whether to show the cleanup error alert.
    var showCleanupError: Bool = false

    // MARK: - Dependencies

    /// Reference to the app state.
    weak var appState: AppState?

    // MARK: - Initialization

    init(tunnel: Tunnel? = nil, appState: AppState? = nil) {
        self.tunnel = tunnel
        self.appState = appState
    }

    // MARK: - Setup

    /// Sets up the view model for a specific tunnel.
    func setup(tunnel: Tunnel, appState: AppState) {
        self.tunnel = tunnel
        self.appState = appState
        self.localState = appState.localTunnelStates[tunnel.id]
    }

    /// Loads the tunnel configuration.
    func loadConfiguration() async {
        guard let tunnel = tunnel, !isLoadingConfiguration else { return }

        isLoadingConfiguration = true
        error = nil

        defer { isLoadingConfiguration = false }

        // Load last connected time from database
        do {
            if let record = try await TunnelDatabase.shared.getTunnel(id: tunnel.id),
               let lastConnectedString = record.lastConnectedAt {
                let formatter = ISO8601DateFormatter()
                self.lastConnectedAt = formatter.date(from: lastConnectedString)
            }
        } catch {
            // Ignore database errors for lastConnectedAt
        }

        // Try to load saved ingress rules for quick display
        let rules = await TunnelStorageManager.shared.loadIngressRules(for: tunnel.id)
        if !rules.isEmpty {
            self.savedIngressRules = rules
            // Extract hostname from saved rules immediately
            extractPublicHostname(from: rules)
        }

        do {
            // Fetch actual configuration from API
            if let accountId = appState?.selectedOrganization?.id {
                let apiClient = CloudflareAPIClient(authManager: .shared)
                configuration = try await apiClient.fetchTunnelConfiguration(
                    accountId: accountId,
                    tunnelId: tunnel.id
                )
                // Update hostname from API response
                extractPublicHostname(from: configuration?.config?.ingress)

                // Save the configuration locally
                try? await TunnelStorageManager.shared.saveConfig(
                    tunnelId: tunnel.id,
                    ingressRules: configuration?.config?.ingress ?? []
                )
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Refreshes the tunnel data.
    func refresh() async {
        if let tunnelId = tunnel?.id,
           let updatedTunnel = appState?.tunnels.first(where: { $0.id == tunnelId }) {
            tunnel = updatedTunnel
            localState = appState?.localTunnelStates[tunnelId]
        }

        await loadConfiguration()
    }

    /// Loads logs for this tunnel.
    func loadLogs() async {
        guard let tunnelId = tunnel?.id,
              let container = appState?.serviceContainer else { return }

        isLoadingLogs = true
        defer { isLoadingLogs = false }

        logEntries = await container.getLogsForTunnel(tunnelId)
    }

    /// Starts continuous log refresh while on logs tab.
    func startLogRefresh() {
        stopLogRefresh()
        logRefreshTask = Task {
            while !Task.isCancelled {
                await loadLogs()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Stops log refresh.
    func stopLogRefresh() {
        logRefreshTask?.cancel()
        logRefreshTask = nil
    }

    /// Opens the public hostname in browser.
    func visitHostname() {
        guard let hostname = publicHostname,
              let url = URL(string: "https://\(hostname)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Extracts public hostname from ingress rules.
    private func extractPublicHostname(from rules: [IngressRule]?) {
        guard let rules = rules else {
            return
        }
        // Find first non-catch-all rule with a hostname
        if let hostname = rules.first(where: { !$0.isCatchAll })?.hostname {
            publicHostname = hostname
        }
    }

    // MARK: - Computed Properties

    /// Whether this tunnel is running locally.
    var isRunningLocally: Bool {
        localState?.isRunning == true
    }

    /// Whether this tunnel is remote (running on another machine).
    /// Only consider it remote if there are actual connections AND we're not running locally
    /// AND we don't have any local state (stopped/stopping counts as local)
    var isRemote: Bool {
        guard let tunnel = tunnel else { return false }
        // If we have any local state, it's not remote
        if localState != nil {
            return false
        }
        // Only remote if there are active connections and we have no local state
        return !tunnel.connections.isEmpty
    }

    /// Whether control buttons should be disabled.
    var controlsDisabled: Bool {
        isRemote || isPerformingAction || (localState?.isTransitioning == true)
    }

    /// The status text for display.
    var statusText: String {
        if let localState = localState {
            switch localState {
            case .running:
                return "Running locally"
            case .starting:
                return "Starting..."
            case .stopping:
                return "Stopping..."
            case .stopped:
                return "Stopped"
            case .error(let message):
                return "Error: \(message)"
            }
        }

        if let tunnel = tunnel, tunnel.isActive {
            return "Running remotely"
        }

        return "Not connected"
    }

    /// The status color.
    var statusColor: Color {
        if let localState = localState {
            switch localState {
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

        if let tunnel = tunnel, tunnel.isActive {
            return .blue
        }

        return .gray
    }

    /// The formatted creation date.
    var createdAtText: String {
        tunnel?.formattedCreatedAt ?? "Unknown"
    }

    /// The formatted last connected time.
    var lastConnectedText: String {
        guard let date = lastConnectedAt else {
            return "Never connected"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last connected \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    /// The connector count text.
    var connectorCountText: String {
        let count = tunnel?.connections.count ?? 0
        return "\(count) connector\(count == 1 ? "" : "s")"
    }

    /// The ingress rules.
    var ingressRules: [IngressRule] {
        configuration?.config?.ingress ?? []
    }

    /// Applies ingress rules saved by the ingress editor.
    ///
    /// Updates the cached configuration and public hostname so the header
    /// reflects the new routing without another API round trip.
    func applySavedIngressRules(_ rules: [IngressRule]) {
        if let existing = configuration {
            configuration = TunnelConfiguration(
                config: IngressConfig(
                    ingress: rules,
                    warpRouting: existing.config?.warpRouting,
                    originRequest: existing.config?.originRequest,
                    raw: existing.config?.raw
                ),
                source: existing.source,
                version: existing.version
            )
        } else {
            configuration = TunnelConfiguration(
                config: IngressConfig(ingress: rules, warpRouting: nil, originRequest: nil),
                source: nil,
                version: nil
            )
        }

        savedIngressRules = rules
        publicHostname = rules.first(where: { !$0.isCatchAll })?.hostname
    }

    // MARK: - Actions

    /// Starts the tunnel.
    func startTunnel() async {
        guard let tunnel = tunnel, let appState = appState else { return }

        isPerformingAction = true
        error = nil

        defer { isPerformingAction = false }

        do {
            try await appState.startTunnel(tunnelId: tunnel.id)
            localState = appState.localTunnelStates[tunnel.id]
        } catch {
            self.error = error.localizedDescription
            localState = appState.localTunnelStates[tunnel.id]
        }
    }

    /// Stops the tunnel.
    func stopTunnel() async {
        guard let tunnel = tunnel, let appState = appState else { return }

        isPerformingAction = true
        error = nil

        defer { isPerformingAction = false }

        await appState.stopTunnel(tunnelId: tunnel.id)
        localState = appState.localTunnelStates[tunnel.id]
    }

    /// Restarts the tunnel.
    func restartTunnel() async {
        guard let tunnel = tunnel, let appState = appState else { return }

        isPerformingAction = true
        error = nil

        defer { isPerformingAction = false }

        do {
            try await appState.restartTunnel(tunnelId: tunnel.id)
            localState = appState.localTunnelStates[tunnel.id]
        } catch {
            self.error = error.localizedDescription
            localState = appState.localTunnelStates[tunnel.id]
        }
    }

    /// Copies the tunnel ID to the clipboard.
    func copyTunnelId() {
        guard let id = tunnel?.id else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)

        hasCopiedId = true

        // Reset the copied state after a delay
        Task {
            try? await Task.sleep(for: .seconds(2))
            hasCopiedId = false
        }
    }

    // MARK: - Deletion Actions

    /// Whether the tunnel can be deleted (not running locally or remotely).
    var canDelete: Bool {
        !isRunningLocally && !isRemote && !(tunnel?.isActive ?? false) && !isDeletingTunnel && !isPerformingAction
    }

    /// Requests deletion of the tunnel (shows confirmation dialog).
    func requestDeleteTunnel() {
        guard canDelete else { return }
        showDeleteConfirmation = true
    }

    /// Confirms and performs the tunnel deletion with progress tracking.
    func confirmDeleteTunnel() async {
        guard let tunnel = tunnel else { return }

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

            // Reset and navigate back
            isDeletingTunnel = false
            onTunnelDeleted?()

        } catch {
            deletionStep = .failed(error.localizedDescription)
            deletionError = error.localizedDescription

            // Wait before showing error
            try? await Task.sleep(for: .seconds(1))
            isDeletingTunnel = false
            showDeletionError = true
        }
    }

    /// Cancels the pending tunnel deletion.
    func cancelDeleteTunnel() {
        showDeleteConfirmation = false
    }

    /// Dismisses the deletion error alert.
    func dismissDeletionError() {
        deletionError = nil
        showDeletionError = false
    }

    // MARK: - Connector Cleanup Actions

    /// Requests cleanup of all connections (shows confirmation dialog).
    func requestCleanupConnections() {
        showCleanupConfirmation = true
    }

    /// Cancels the pending cleanup.
    func cancelCleanupConnections() {
        showCleanupConfirmation = false
    }

    /// Confirms and performs the connection cleanup.
    func confirmCleanupConnections() async {
        guard let tunnel = tunnel else { return }

        showCleanupConfirmation = false
        isCleaningUpConnections = true
        cleanupError = nil

        defer {
            isCleaningUpConnections = false
        }

        do {
            guard let accountId = appState?.selectedOrganization?.id else {
                throw NSError(domain: "ConnectorCleanup", code: -1, userInfo: [NSLocalizedDescriptionKey: "No organization selected"])
            }

            let apiClient = CloudflareAPIClient(authManager: .shared)

            // Clean up all connections via API
            try await apiClient.cleanUpConnections(accountId: accountId, tunnelId: tunnel.id)

            // Refresh tunnel from API and update local storage
            await refreshTunnelFromAPI()

        } catch {
            cleanupError = error.localizedDescription
            showCleanupError = true
        }
    }

    /// Dismisses the cleanup error alert.
    func dismissCleanupError() {
        cleanupError = nil
        showCleanupError = false
    }

    /// Refreshes tunnel data from API and updates local storage.
    private func refreshTunnelFromAPI() async {
        guard let tunnel = tunnel,
              let accountId = appState?.selectedOrganization?.id else { return }

        do {
            let apiClient = CloudflareAPIClient(authManager: .shared)

            // Fetch fresh tunnel data from API
            let updatedTunnel = try await apiClient.fetchTunnel(
                accountId: accountId,
                tunnelId: tunnel.id
            )

            // Update local tunnel reference
            self.tunnel = updatedTunnel

            // Update in appState's tunnel list
            if let index = appState?.tunnels.firstIndex(where: { $0.id == tunnel.id }) {
                appState?.tunnels[index] = updatedTunnel
            }

            // Update local state
            localState = appState?.localTunnelStates[tunnel.id]

            // Fetch and update configuration
            let configuration = try await apiClient.fetchTunnelConfiguration(
                accountId: accountId,
                tunnelId: tunnel.id
            )
            self.configuration = configuration

            // Update hostname from fresh config
            extractPublicHostname(from: configuration.config?.ingress)

            // Save updated config to local storage
            try? await TunnelStorageManager.shared.saveConfig(
                tunnelId: tunnel.id,
                ingressRules: configuration.config?.ingress ?? []
            )

            // Update saved ingress rules
            self.savedIngressRules = configuration.config?.ingress ?? []

        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Copies all log entries to the clipboard.
    func copyAllLogs() {
        guard !logEntries.isEmpty else { return }

        let text = logEntries.map { entry in
            "[\(entry.formattedTime)] [\(entry.level.rawValue.uppercased())] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Clears all log entries.
    func clearAllLogs() {
        logEntries.removeAll()
        selectedLogIds.removeAll()

        // Also clear logs in the service container
        if let tunnelId = tunnel?.id,
           let container = appState?.serviceContainer {
            Task {
                await container.clearLogsForTunnel(tunnelId)
            }
        }
    }

    // MARK: - Log Selection

    /// Toggles selection mode.
    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedLogIds.removeAll()
        }
    }

    /// Toggles selection of a log entry.
    func toggleLogSelection(_ entry: LogEntry) {
        if selectedLogIds.contains(entry.id) {
            selectedLogIds.remove(entry.id)
        } else {
            selectedLogIds.insert(entry.id)
        }
    }

    /// Whether a log entry is selected.
    func isLogSelected(_ entry: LogEntry) -> Bool {
        selectedLogIds.contains(entry.id)
    }

    /// Selects all log entries.
    func selectAllLogs() {
        selectedLogIds = Set(logEntries.map { $0.id })
    }

    /// Deselects all log entries.
    func deselectAllLogs() {
        selectedLogIds.removeAll()
    }

    /// Copies selected log entries to the clipboard.
    func copySelectedLogs() {
        let selectedEntries = logEntries.filter { selectedLogIds.contains($0.id) }
        guard !selectedEntries.isEmpty else { return }

        let text = selectedEntries.map { entry in
            "[\(entry.formattedTime)] [\(entry.level.rawValue.uppercased())] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// The count of selected logs.
    var selectedLogCount: Int {
        selectedLogIds.count
    }

    /// Updates the local state from app state.
    func updateLocalState() {
        if let tunnelId = tunnel?.id {
            localState = appState?.localTunnelStates[tunnelId]
        }
    }

    // MARK: - Log History

    /// Loads the list of historical log files for this tunnel.
    func loadLogHistory() async {
        guard let tunnelId = tunnel?.id else { return }

        // Logs are stored per-tunnel at ~/.tunnelflare/tunnels/<tunnelId>/logs/
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tunnelflare", isDirectory: true)
            .appendingPathComponent("tunnels", isDirectory: true)
            .appendingPathComponent(tunnelId, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        guard FileManager.default.fileExists(atPath: logsDirectory.path) else {
            logHistoryFiles = []
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            // All .log files in this directory belong to this tunnel
            let tunnelLogs = contents.filter { $0.pathExtension == "log" }

            // Convert to LogHistoryFile objects
            logHistoryFiles = tunnelLogs.compactMap { url -> LogHistoryFile? in
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                    return nil
                }

                return LogHistoryFile(
                    url: url,
                    filename: url.lastPathComponent,
                    modificationDate: values.contentModificationDate ?? Date.distantPast,
                    fileSize: values.fileSize ?? 0
                )
            }.sorted { $0.modificationDate > $1.modificationDate }

        } catch {
            logHistoryFiles = []
        }
    }

    /// Loads the active log file path.
    func loadActiveLogFilePath() async {
        guard let tunnelId = tunnel?.id,
              let container = appState?.serviceContainer else {
            activeLogFilePath = nil
            return
        }

        activeLogFilePath = await container.logFileWriter.getLogFilePath(tunnelId: tunnelId)
    }

    /// Loads the content of a historical log file.
    func loadHistoryLogContent(_ file: LogHistoryFile) async {
        selectedHistoryFile = file
        isLoadingHistoryContent = true

        defer { isLoadingHistoryContent = false }

        do {
            historyLogContent = try String(contentsOf: file.url, encoding: .utf8)
        } catch {
            historyLogContent = "Error loading log file: \(error.localizedDescription)"
        }
    }

    /// Opens the log file in Finder.
    func revealLogFileInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Opens the logs directory in Finder.
    func openLogsDirectory() {
        guard let tunnelId = tunnel?.id else { return }

        // Logs are stored per-tunnel at ~/.tunnelflare/tunnels/<tunnelId>/logs/
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tunnelflare", isDirectory: true)
            .appendingPathComponent("tunnels", isDirectory: true)
            .appendingPathComponent(tunnelId, isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        if FileManager.default.fileExists(atPath: logsDirectory.path) {
            NSWorkspace.shared.open(logsDirectory)
        } else {
            // If logs directory doesn't exist yet, open the tunnel directory
            let tunnelDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".tunnelflare", isDirectory: true)
                .appendingPathComponent("tunnels", isDirectory: true)
                .appendingPathComponent(tunnelId, isDirectory: true)

            if FileManager.default.fileExists(atPath: tunnelDirectory.path) {
                NSWorkspace.shared.open(tunnelDirectory)
            }
        }
    }

    /// Deletes a historical log file.
    func deleteHistoryLogFile(_ file: LogHistoryFile) async {
        do {
            try FileManager.default.removeItem(at: file.url)
            logHistoryFiles.removeAll { $0.url == file.url }

            if selectedHistoryFile?.url == file.url {
                selectedHistoryFile = nil
                historyLogContent = ""
            }
        } catch {
            // Handle error silently
        }
    }
}

// MARK: - LogHistoryFile

/// Represents a historical log file.
struct LogHistoryFile: Identifiable, Equatable, Hashable {
    let id: String
    let url: URL
    let filename: String
    let modificationDate: Date
    let fileSize: Int

    init(url: URL, filename: String, modificationDate: Date, fileSize: Int) {
        self.id = url.path
        self.url = url
        self.filename = filename
        self.modificationDate = modificationDate
        self.fileSize = fileSize
    }

    /// Formatted file size.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    /// Formatted modification date.
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }

    /// Extract the timestamp from the filename.
    var sessionTimestamp: String {
        // Format: yyyy-MM-dd_HH-mm-ss.log (logs are now stored in per-tunnel directories)
        // Example: 2026-01-13_14-30-00.log
        let name = filename.replacingOccurrences(of: ".log", with: "")

        // Parse the date pattern (yyyy-MM-dd_HH-mm-ss)
        let pattern = #"^(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
            var parts: [String] = []
            for i in 1...4 {
                if let range = Range(match.range(at: i), in: name) {
                    parts.append(String(name[range]))
                }
            }
            if parts.count == 4 {
                // Format: 2026-01-13 14:30:00
                return "\(parts[0]) \(parts[1]):\(parts[2]):\(parts[3])"
            }
        }
        return formattedDate
    }

    static func == (lhs: LogHistoryFile, rhs: LogHistoryFile) -> Bool {
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
