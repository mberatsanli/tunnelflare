//
//  LogEntry.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - LogEntry

/// Represents a single log entry from a cloudflared process.
///
/// LogEntry stores structured log information including:
/// - Unique identifier for SwiftUI list rendering
/// - Timestamp of the log event
/// - Log level (debug, info, warning, error)
/// - Parsed message content
/// - Associated tunnel ID
/// - Original raw log line
///
/// ## Usage
/// ```swift
/// let entry = LogEntry(
///     timestamp: Date(),
///     level: .info,
///     message: "Connection established",
///     tunnelId: "my-tunnel",
///     rawLine: "2024-01-10T12:34:56.789Z INF Connection established"
/// )
///
/// print("Size: \(entry.size) bytes")
/// ```
struct LogEntry: Identifiable, Equatable, Hashable, Sendable {

    // MARK: - Properties

    /// Unique identifier for the log entry.
    let id: UUID

    /// Timestamp when the log was generated.
    let timestamp: Date

    /// Log level indicating severity.
    let level: LogLevel

    /// The parsed message content.
    let message: String

    /// ID of the tunnel that generated this log.
    let tunnelId: String

    /// The original raw log line from cloudflared.
    let rawLine: String

    // MARK: - Initialization

    /// Creates a new log entry.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID).
    ///   - timestamp: When the log was generated.
    ///   - level: The log level.
    ///   - message: The parsed message content.
    ///   - tunnelId: The tunnel that generated this log.
    ///   - rawLine: The original log line.
    init(
        id: UUID = UUID(),
        timestamp: Date,
        level: LogLevel,
        message: String,
        tunnelId: String,
        rawLine: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.tunnelId = tunnelId
        self.rawLine = rawLine
    }

    // MARK: - Computed Properties

    /// The size of this log entry in bytes (based on raw line UTF-8 encoding).
    var size: Int {
        rawLine.utf8.count
    }

    /// Formatted timestamp for display (HH:mm:ss.SSS).
    var formattedTime: String {
        Self.timeFormatter.string(from: timestamp)
    }

    /// Formatted timestamp with date for export.
    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    // MARK: - Static Formatters

    /// Time formatter for display (HH:mm:ss.SSS).
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Full timestamp formatter for export.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // MARK: - Equatable

    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - LogLevel Extension

extension LogLevel {
    /// The color to use for displaying this log level.
    var color: Color {
        switch self {
        case .debug:
            return .secondary
        case .info:
            return .primary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    /// Background color for level badges.
    var backgroundColor: Color {
        switch self {
        case .debug:
            return .gray.opacity(0.2)
        case .info:
            return .blue.opacity(0.2)
        case .warning:
            return .orange.opacity(0.2)
        case .error:
            return .red.opacity(0.2)
        }
    }

    /// Whether this level represents an important event.
    var isImportant: Bool {
        switch self {
        case .warning, .error:
            return true
        case .debug, .info:
            return false
        }
    }

    /// Comparison for filtering (higher severity is greater).
    var severity: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension LogEntry {
    /// Sample log entries for previews.
    static let previewEntries: [LogEntry] = [
        LogEntry(
            timestamp: Date().addingTimeInterval(-120),
            level: .info,
            message: "Starting tunnel tunnelID=abc-123-def",
            tunnelId: "preview-tunnel",
            rawLine: "2026-01-10T12:34:56.789Z INF Starting tunnel tunnelID=abc-123-def"
        ),
        LogEntry(
            timestamp: Date().addingTimeInterval(-60),
            level: .info,
            message: "Connection established connIndex=0 location=SJC",
            tunnelId: "preview-tunnel",
            rawLine: "2026-01-10T12:35:00.123Z INF Connection established connIndex=0 location=SJC"
        ),
        LogEntry(
            timestamp: Date().addingTimeInterval(-30),
            level: .warning,
            message: "Retrying connection attempt=2",
            tunnelId: "preview-tunnel",
            rawLine: "2026-01-10T12:35:30.456Z WRN Retrying connection attempt=2"
        ),
        LogEntry(
            timestamp: Date().addingTimeInterval(-10),
            level: .error,
            message: "Connection failed error=timeout",
            tunnelId: "preview-tunnel",
            rawLine: "2026-01-10T12:35:50.789Z ERR Connection failed error=timeout"
        ),
        LogEntry(
            timestamp: Date(),
            level: .debug,
            message: "Sending heartbeat",
            tunnelId: "preview-tunnel",
            rawLine: "2026-01-10T12:36:00.000Z DBG Sending heartbeat"
        )
    ]
}
#endif
