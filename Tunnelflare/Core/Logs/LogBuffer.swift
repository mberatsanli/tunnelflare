//
//  LogBuffer.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - LogBuffer

/// Actor-based ring buffer for efficient log storage with size and count limits.
///
/// LogBuffer implements a FIFO ring buffer that:
/// - Stores up to 10,000 log entries
/// - Enforces a 50 MB size limit
/// - Drops oldest entries when limits are reached
/// - Supports multiple observers for new entries
/// - Provides thread-safe access via Swift actors
///
/// ## Usage
/// ```swift
/// let buffer = LogBuffer()
///
/// // Add entries
/// await buffer.append(entry)
///
/// // Get all entries
/// let entries = await buffer.allEntries
///
/// // Observe new entries
/// for await entry in await buffer.observe() {
///     print(entry.message)
/// }
/// ```
actor LogBuffer {

    // MARK: - Types

    /// Identifier for an observer.
    typealias ObserverId = UUID

    // MARK: - Properties

    /// Maximum number of log entries to store.
    let maxLines: Int

    /// Maximum total size in bytes.
    let maxBytes: Int

    /// The stored log entries.
    private var entries: [LogEntry] = []

    /// Current total size in bytes.
    private var currentBytes: Int = 0

    /// Observers waiting for new entries.
    private var observers: [ObserverId: AsyncStream<LogEntry>.Continuation] = [:]

    /// Logger for buffer operations.
    private let logger = Logger.app

    // MARK: - Initialization

    /// Creates a new LogBuffer with default limits.
    ///
    /// - Parameters:
    ///   - maxLines: Maximum number of entries (default: 10,000).
    ///   - maxBytes: Maximum size in bytes (default: 50 MB).
    init(
        maxLines: Int = LogConstants.maxLogLines,
        maxBytes: Int = LogConstants.maxLogBytes
    ) {
        self.maxLines = maxLines
        self.maxBytes = maxBytes
    }

    // MARK: - Public Methods

    /// Appends a new log entry to the buffer.
    ///
    /// If the buffer exceeds limits, oldest entries are dropped.
    ///
    /// - Parameter entry: The log entry to append.
    func append(_ entry: LogEntry) {
        // Enforce limits by removing old entries
        while shouldEvict(newEntrySize: entry.size) {
            evictOldest()
        }

        // Add new entry
        entries.append(entry)
        currentBytes += entry.size

        // Notify all observers
        for continuation in observers.values {
            continuation.yield(entry)
        }
    }

    /// Appends multiple log entries to the buffer.
    ///
    /// - Parameter newEntries: The log entries to append.
    func append(contentsOf newEntries: [LogEntry]) {
        for entry in newEntries {
            append(entry)
        }
    }

    /// Returns all entries in the buffer.
    var allEntries: [LogEntry] {
        entries
    }

    /// Returns the count of entries in the buffer.
    var count: Int {
        entries.count
    }

    /// Returns the current size in bytes.
    var sizeInBytes: Int {
        currentBytes
    }

    /// Returns whether the buffer is empty.
    var isEmpty: Bool {
        entries.isEmpty
    }

    /// Clears all entries from the buffer.
    func clear() {
        entries.removeAll()
        currentBytes = 0
        logger.debug("LogBuffer cleared")
    }

    /// Returns entries filtered by level.
    ///
    /// - Parameter levels: The log levels to include.
    /// - Returns: Filtered entries.
    func entries(matching levels: Set<LogLevel>) -> [LogEntry] {
        guard !levels.isEmpty else { return entries }
        return entries.filter { levels.contains($0.level) }
    }

    /// Returns entries containing the search text.
    ///
    /// - Parameter text: The text to search for.
    /// - Returns: Matching entries.
    func entries(containing text: String) -> [LogEntry] {
        guard !text.isEmpty else { return entries }
        let lowercasedText = text.lowercased()
        return entries.filter { entry in
            entry.message.lowercased().contains(lowercasedText) ||
            entry.rawLine.lowercased().contains(lowercasedText)
        }
    }

    /// Returns entries filtered by level and search text.
    ///
    /// - Parameters:
    ///   - levels: The log levels to include (empty means all).
    ///   - searchText: The text to search for (empty means no filter).
    /// - Returns: Filtered entries.
    func filteredEntries(levels: Set<LogLevel>, searchText: String) -> [LogEntry] {
        var result = entries

        // Filter by levels if specified
        if !levels.isEmpty {
            result = result.filter { levels.contains($0.level) }
        }

        // Filter by search text if specified
        if !searchText.isEmpty {
            let lowercasedText = searchText.lowercased()
            result = result.filter { entry in
                entry.message.lowercased().contains(lowercasedText) ||
                entry.rawLine.lowercased().contains(lowercasedText)
            }
        }

        return result
    }

    /// Returns the most recent entries.
    ///
    /// - Parameter limit: Maximum number of entries to return.
    /// - Returns: The most recent entries.
    func recentEntries(limit: Int) -> [LogEntry] {
        Array(entries.suffix(limit))
    }

    /// Creates an async stream that yields new entries as they arrive.
    ///
    /// - Returns: An async stream of new log entries.
    func observe() -> AsyncStream<LogEntry> {
        let observerId = ObserverId()

        return AsyncStream { continuation in
            self.observers[observerId] = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.removeObserver(observerId)
                }
            }
        }
    }

    /// Returns statistics about the buffer.
    var statistics: BufferStatistics {
        BufferStatistics(
            entryCount: entries.count,
            sizeInBytes: currentBytes,
            maxEntries: maxLines,
            maxBytes: maxBytes,
            utilizationPercent: Double(entries.count) / Double(maxLines) * 100,
            sizeUtilizationPercent: Double(currentBytes) / Double(maxBytes) * 100
        )
    }

    // MARK: - Private Methods

    /// Removes an observer.
    private func removeObserver(_ id: ObserverId) {
        observers.removeValue(forKey: id)
    }

    /// Checks if eviction is needed for a new entry.
    private func shouldEvict(newEntrySize: Int) -> Bool {
        guard !entries.isEmpty else { return false }
        return entries.count >= maxLines || (currentBytes + newEntrySize) > maxBytes
    }

    /// Evicts the oldest entry from the buffer.
    private func evictOldest() {
        guard let oldest = entries.first else { return }
        entries.removeFirst()
        currentBytes -= oldest.size
    }
}

// MARK: - Buffer Statistics

extension LogBuffer {

    /// Statistics about the log buffer.
    struct BufferStatistics: Sendable {
        /// Current number of entries.
        let entryCount: Int

        /// Current size in bytes.
        let sizeInBytes: Int

        /// Maximum allowed entries.
        let maxEntries: Int

        /// Maximum allowed bytes.
        let maxBytes: Int

        /// Percentage of entry limit used.
        let utilizationPercent: Double

        /// Percentage of size limit used.
        let sizeUtilizationPercent: Double

        /// Formatted size string.
        var formattedSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(sizeInBytes), countStyle: .file)
        }

        /// Formatted max size string.
        var formattedMaxSize: String {
            ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file)
        }
    }
}

// MARK: - LogBuffer Exporting

extension LogBuffer {

    /// Exports all entries as formatted text.
    ///
    /// - Parameter tunnelName: Optional tunnel name for the header.
    /// - Returns: Formatted log text.
    func exportAsText(tunnelName: String? = nil) -> String {
        var lines: [String] = []

        // Add header
        lines.append("# Tunnelflare - Log Export")
        if let name = tunnelName {
            lines.append("# Tunnel: \(name)")
        }
        lines.append("# Exported: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("# Lines: \(entries.count)")
        lines.append("")

        // Add log entries
        for entry in entries {
            lines.append(entry.rawLine)
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Sendable Conformance

extension LogBuffer: Sendable {}
