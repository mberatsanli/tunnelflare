//
//  LogStreamManager.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - LogStreamManager

/// Actor-based manager for streaming and storing logs from cloudflared processes.
///
/// LogStreamManager captures logs from tunnel processes, parses them into structured
/// entries, and stores them in per-tunnel buffers. It provides real-time streaming
/// of new entries to observers.
///
/// ## Features
/// - Per-tunnel log buffers with configurable limits
/// - Real-time log parsing via LogParser
/// - AsyncStream-based observation for new entries
/// - Thread-safe access via Swift actors
///
/// ## Usage
/// ```swift
/// let logManager = LogStreamManager()
///
/// // Process a log line from a tunnel
/// await logManager.processLogLine("2024-01-10T12:34:56.789Z INF Starting tunnel", tunnelId: "my-tunnel")
///
/// // Get all entries for a tunnel
/// let entries = await logManager.getEntries(for: "my-tunnel")
///
/// // Observe new entries
/// for await entry in await logManager.observeAllLogs() {
///     print(entry.message)
/// }
/// ```
actor LogStreamManager {

    // MARK: - Types

    /// Observer identifier.
    typealias ObserverId = UUID

    /// Event types emitted by the log stream manager.
    enum Event: Sendable {
        case entryAdded(LogEntry)
        case bufferCleared(tunnelId: String)
    }

    // MARK: - Properties

    /// Per-tunnel log buffers.
    private var buffers: [String: LogBuffer] = [:]

    /// Global buffer for all logs (aggregated view).
    private let globalBuffer: LogBuffer

    /// Observers for all logs.
    private var globalObservers: [ObserverId: AsyncStream<LogEntry>.Continuation] = [:]

    /// Observers for specific tunnels.
    private var tunnelObservers: [String: [ObserverId: AsyncStream<LogEntry>.Continuation]] = [:]

    /// Logger for log stream operations.
    private let logger = Logger.app

    // MARK: - Initialization

    /// Creates a new LogStreamManager.
    ///
    /// - Parameters:
    ///   - maxLinesPerTunnel: Maximum lines per tunnel buffer (default: 10,000).
    ///   - maxBytesPerTunnel: Maximum bytes per tunnel buffer (default: 50 MB).
    init(
        maxLinesPerTunnel: Int = LogConstants.maxLogLines,
        maxBytesPerTunnel: Int = LogConstants.maxLogBytes
    ) {
        // Global buffer can be larger to hold aggregated logs
        self.globalBuffer = LogBuffer(maxLines: maxLinesPerTunnel, maxBytes: maxBytesPerTunnel)
    }

    // MARK: - Public Methods

    /// Processes a raw log line from a tunnel.
    ///
    /// Parses the line into a structured LogEntry and stores it in the
    /// appropriate buffer.
    ///
    /// - Parameters:
    ///   - line: The raw log line from cloudflared.
    ///   - tunnelId: The ID of the tunnel that generated the log.
    func processLogLine(_ line: String, tunnelId: String) async {
        // Parse the log line
        guard let entry = LogParser.parse(line, tunnelId: tunnelId) else {
            return
        }

        // Add to tunnel-specific buffer
        let buffer = getOrCreateBuffer(for: tunnelId)
        await buffer.append(entry)

        // Add to global buffer
        await globalBuffer.append(entry)

        // Notify global observers
        for continuation in globalObservers.values {
            continuation.yield(entry)
        }

        // Notify tunnel-specific observers
        if let observers = tunnelObservers[tunnelId] {
            for continuation in observers.values {
                continuation.yield(entry)
            }
        }
    }

    /// Processes multiple log lines from a tunnel.
    ///
    /// - Parameters:
    ///   - lines: The raw log lines from cloudflared.
    ///   - tunnelId: The ID of the tunnel that generated the logs.
    func processLogLines(_ lines: [String], tunnelId: String) async {
        for line in lines {
            await processLogLine(line, tunnelId: tunnelId)
        }
    }

    /// Processes text that may contain multiple log lines.
    ///
    /// - Parameters:
    ///   - text: Text containing one or more log lines.
    ///   - tunnelId: The ID of the tunnel that generated the logs.
    func processLogText(_ text: String, tunnelId: String) async {
        let lines = text.components(separatedBy: .newlines)
        await processLogLines(lines, tunnelId: tunnelId)
    }

    /// Gets all log entries for a specific tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: Array of log entries for the tunnel.
    func getEntries(for tunnelId: String) async -> [LogEntry] {
        guard let buffer = buffers[tunnelId] else {
            return []
        }
        return await buffer.allEntries
    }

    /// Gets all log entries across all tunnels.
    ///
    /// - Returns: Array of all log entries.
    func getAllEntries() async -> [LogEntry] {
        await globalBuffer.allEntries
    }

    /// Gets filtered entries for a specific tunnel.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID (nil for all tunnels).
    ///   - levels: Log levels to include (empty for all).
    ///   - searchText: Text to search for (empty for no filter).
    /// - Returns: Filtered log entries.
    func getFilteredEntries(
        tunnelId: String?,
        levels: Set<LogLevel>,
        searchText: String
    ) async -> [LogEntry] {
        if let tunnelId = tunnelId, let buffer = buffers[tunnelId] {
            return await buffer.filteredEntries(levels: levels, searchText: searchText)
        } else {
            return await globalBuffer.filteredEntries(levels: levels, searchText: searchText)
        }
    }

    /// Gets the count of entries for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The entry count.
    func getEntryCount(for tunnelId: String) async -> Int {
        guard let buffer = buffers[tunnelId] else {
            return 0
        }
        return await buffer.count
    }

    /// Gets the total count of all entries.
    ///
    /// - Returns: The total entry count.
    func getTotalEntryCount() async -> Int {
        await globalBuffer.count
    }

    /// Gets buffer statistics for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: Buffer statistics.
    func getStatistics(for tunnelId: String) async -> LogBuffer.BufferStatistics? {
        guard let buffer = buffers[tunnelId] else {
            return nil
        }
        return await buffer.statistics
    }

    /// Gets global buffer statistics.
    ///
    /// - Returns: Global buffer statistics.
    func getGlobalStatistics() async -> LogBuffer.BufferStatistics {
        await globalBuffer.statistics
    }

    /// Clears all logs for a specific tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    func clearLogs(for tunnelId: String) async {
        guard let buffer = buffers[tunnelId] else {
            return
        }
        await buffer.clear()
        logger.info("Cleared logs for tunnel: \(tunnelId)")
    }

    /// Clears all logs for all tunnels.
    func clearAllLogs() async {
        for buffer in buffers.values {
            await buffer.clear()
        }
        await globalBuffer.clear()
        logger.info("Cleared all logs")
    }

    /// Creates an async stream that yields new log entries for all tunnels.
    ///
    /// - Returns: An async stream of new log entries.
    func observeAllLogs() -> AsyncStream<LogEntry> {
        let observerId = ObserverId()

        return AsyncStream { continuation in
            self.globalObservers[observerId] = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.removeGlobalObserver(observerId)
                }
            }
        }
    }

    /// Creates an async stream that yields new log entries for a specific tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID to observe.
    /// - Returns: An async stream of new log entries for the tunnel.
    func observeTunnel(_ tunnelId: String) -> AsyncStream<LogEntry> {
        let observerId = ObserverId()

        return AsyncStream { continuation in
            if self.tunnelObservers[tunnelId] == nil {
                self.tunnelObservers[tunnelId] = [:]
            }
            self.tunnelObservers[tunnelId]?[observerId] = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.removeTunnelObserver(observerId, tunnelId: tunnelId)
                }
            }
        }
    }

    /// Exports logs for a tunnel as formatted text.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID (nil for all tunnels).
    ///   - tunnelName: Optional tunnel name for the header.
    /// - Returns: Formatted log text.
    func exportLogs(tunnelId: String?, tunnelName: String?) async -> String {
        if let tunnelId = tunnelId, let buffer = buffers[tunnelId] {
            return await buffer.exportAsText(tunnelName: tunnelName)
        } else {
            return await globalBuffer.exportAsText(tunnelName: tunnelName ?? "All Tunnels")
        }
    }

    /// Gets the list of tunnel IDs that have log buffers.
    ///
    /// - Returns: Array of tunnel IDs.
    var trackedTunnelIds: [String] {
        Array(buffers.keys)
    }

    // MARK: - Private Methods

    /// Gets or creates a buffer for a tunnel.
    private func getOrCreateBuffer(for tunnelId: String) -> LogBuffer {
        if let existing = buffers[tunnelId] {
            return existing
        }

        let buffer = LogBuffer()
        buffers[tunnelId] = buffer
        return buffer
    }

    /// Removes a global observer.
    private func removeGlobalObserver(_ id: ObserverId) {
        globalObservers.removeValue(forKey: id)
    }

    /// Removes a tunnel-specific observer.
    private func removeTunnelObserver(_ id: ObserverId, tunnelId: String) {
        tunnelObservers[tunnelId]?.removeValue(forKey: id)
        if tunnelObservers[tunnelId]?.isEmpty == true {
            tunnelObservers.removeValue(forKey: tunnelId)
        }
    }
}

// MARK: - LogStreamManager Integration

extension LogStreamManager {
    /// Creates a task that processes log events from a service container.
    ///
    /// This connects the LogStreamManager to the ServiceContainer's event stream
    /// to automatically capture and store tunnel logs.
    ///
    /// - Parameter eventStream: The event stream from the service container.
    /// - Returns: A task that processes events.
    func createLogProcessingTask(from eventStream: AsyncStream<ServiceEvent>) -> Task<Void, Never> {
        Task {
            for await event in eventStream {
                switch event {
                case .logReceived(let tunnelId, let line):
                    await processLogLine(line, tunnelId: tunnelId)
                default:
                    break
                }
            }
        }
    }
}

// MARK: - Sendable Conformance

extension LogStreamManager: Sendable {}
