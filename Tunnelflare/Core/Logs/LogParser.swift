//
//  LogParser.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - LogParser

/// Parses cloudflared log output into structured LogEntry objects.
///
/// cloudflared log format:
/// ```
/// 2024-01-10T12:34:56.789Z INF Starting tunnel tunnelID=abc-123
/// 2024-01-10T12:34:57.123Z DBG Processing request
/// 2024-01-10T12:34:58.456Z WRN Connection unstable
/// 2024-01-10T12:34:59.789Z ERR Failed to connect
/// ```
///
/// ## Usage
/// ```swift
/// if let entry = LogParser.parse(
///     "2024-01-10T12:34:56.789Z INF Starting tunnel",
///     tunnelId: "my-tunnel"
/// ) {
///     print("Level: \(entry.level)")
/// }
/// ```
enum LogParser {

    // MARK: - Constants

    /// Regex pattern for parsing cloudflared log lines.
    /// Matches: TIMESTAMP LEVEL MESSAGE
    /// Example: 2024-01-10T12:34:56.789Z INF Starting tunnel tunnelID=abc-123
    private static let logPattern = #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\s+(DBG|INF|WRN|ERR)\s+(.+)$"#

    /// Compiled regex for better performance.
    private static let logRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: logPattern, options: [])
    }()

    /// ISO8601 date formatter for parsing timestamps.
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Fallback date formatter without fractional seconds.
    private static let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Public Methods

    /// Parses a raw log line into a structured LogEntry.
    ///
    /// Handles the standard cloudflared log format:
    /// `TIMESTAMP LEVEL MESSAGE`
    ///
    /// For malformed lines, returns a LogEntry with the raw line as the message
    /// and an info level.
    ///
    /// - Parameters:
    ///   - line: The raw log line to parse.
    ///   - tunnelId: The ID of the tunnel that generated this log.
    /// - Returns: A LogEntry if parsing succeeds, nil for empty lines.
    static func parse(_ line: String, tunnelId: String) -> LogEntry? {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip empty lines
        guard !trimmedLine.isEmpty else {
            return nil
        }

        // Try to parse structured log format
        if let entry = parseStructured(trimmedLine, tunnelId: tunnelId) {
            return entry
        }

        // For unstructured lines, create a basic entry
        return LogEntry(
            timestamp: Date(),
            level: inferLevel(from: trimmedLine),
            message: trimmedLine,
            tunnelId: tunnelId,
            rawLine: trimmedLine
        )
    }

    /// Parses multiple log lines.
    ///
    /// - Parameters:
    ///   - text: Text containing multiple log lines.
    ///   - tunnelId: The ID of the tunnel that generated these logs.
    /// - Returns: An array of LogEntry objects.
    static func parseMultiple(_ text: String, tunnelId: String) -> [LogEntry] {
        text.components(separatedBy: .newlines)
            .compactMap { parse($0, tunnelId: tunnelId) }
    }

    // MARK: - Private Methods

    /// Attempts to parse a structured log line.
    private static func parseStructured(_ line: String, tunnelId: String) -> LogEntry? {
        guard let regex = logRegex else { return nil }

        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range) else {
            return nil
        }

        // Extract timestamp
        guard let timestampRange = Range(match.range(at: 1), in: line),
              let timestamp = parseTimestamp(String(line[timestampRange])) else {
            return nil
        }

        // Extract level
        guard let levelRange = Range(match.range(at: 2), in: line),
              let level = parseLevel(String(line[levelRange])) else {
            return nil
        }

        // Extract message
        guard let messageRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        let message = String(line[messageRange])

        return LogEntry(
            timestamp: timestamp,
            level: level,
            message: message,
            tunnelId: tunnelId,
            rawLine: line
        )
    }

    /// Parses an ISO8601 timestamp string.
    private static func parseTimestamp(_ string: String) -> Date? {
        if let date = dateFormatter.date(from: string) {
            return date
        }
        return fallbackDateFormatter.date(from: string)
    }

    /// Parses a log level string.
    private static func parseLevel(_ string: String) -> LogLevel? {
        LogLevel(rawValue: string)
    }

    /// Infers log level from line content for unstructured logs.
    private static func inferLevel(from line: String) -> LogLevel {
        let lowercased = line.lowercased()

        if lowercased.contains("error") || lowercased.contains("failed") || lowercased.contains("fatal") {
            return .error
        } else if lowercased.contains("warn") || lowercased.contains("warning") {
            return .warning
        } else if lowercased.contains("debug") || lowercased.contains("trace") {
            return .debug
        } else {
            return .info
        }
    }
}

// MARK: - LogParser Statistics

extension LogParser {

    /// Statistics about parsed log entries.
    struct Statistics {
        /// Total number of entries.
        let totalCount: Int

        /// Count by log level.
        let countByLevel: [LogLevel: Int]

        /// Earliest timestamp.
        let earliestTimestamp: Date?

        /// Latest timestamp.
        let latestTimestamp: Date?

        /// Time span of logs in seconds.
        var timeSpan: TimeInterval? {
            guard let earliest = earliestTimestamp, let latest = latestTimestamp else {
                return nil
            }
            return latest.timeIntervalSince(earliest)
        }
    }

    /// Computes statistics for a collection of log entries.
    ///
    /// - Parameter entries: The log entries to analyze.
    /// - Returns: Statistics about the entries.
    static func computeStatistics(for entries: [LogEntry]) -> Statistics {
        var countByLevel: [LogLevel: Int] = [:]
        var earliestTimestamp: Date?
        var latestTimestamp: Date?

        for entry in entries {
            // Count by level
            countByLevel[entry.level, default: 0] += 1

            // Track timestamps
            if earliestTimestamp == nil || entry.timestamp < earliestTimestamp! {
                earliestTimestamp = entry.timestamp
            }
            if latestTimestamp == nil || entry.timestamp > latestTimestamp! {
                latestTimestamp = entry.timestamp
            }
        }

        return Statistics(
            totalCount: entries.count,
            countByLevel: countByLevel,
            earliestTimestamp: earliestTimestamp,
            latestTimestamp: latestTimestamp
        )
    }
}

// MARK: - LogParser Validation

extension LogParser {

    /// Validates that a string appears to be a cloudflared log line.
    ///
    /// - Parameter line: The line to validate.
    /// - Returns: True if the line appears to be a valid log line.
    static func isValidLogLine(_ line: String) -> Bool {
        guard let regex = logRegex else { return false }
        let range = NSRange(line.startIndex..., in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }
}
