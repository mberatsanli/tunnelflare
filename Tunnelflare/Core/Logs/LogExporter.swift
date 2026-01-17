//
//  LogExporter.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import AppKit
import os.log

// MARK: - LogExporter

/// Utility for exporting logs to files.
///
/// LogExporter handles exporting log entries to text files with proper
/// formatting and metadata headers. It uses NSSavePanel for file location
/// selection and handles large exports efficiently.
///
/// ## Usage
/// ```swift
/// let exporter = LogExporter()
///
/// // Export with save panel
/// let success = await exporter.exportWithSavePanel(
///     entries: logEntries,
///     tunnelName: "my-tunnel"
/// )
///
/// // Export to specific URL
/// try await exporter.exportToFile(
///     entries: logEntries,
///     tunnelName: "my-tunnel",
///     destination: fileURL
/// )
/// ```
enum LogExporter {

    // MARK: - Types

    /// Export format options.
    enum ExportFormat {
        case plainText
        case rawLines

        var fileExtension: String {
            switch self {
            case .plainText: return "txt"
            case .rawLines: return "log"
            }
        }

        var contentType: String {
            switch self {
            case .plainText: return "public.plain-text"
            case .rawLines: return "public.plain-text"
            }
        }
    }

    /// Result of an export operation.
    enum ExportResult {
        case success(URL)
        case cancelled
        case failed(Error)
    }

    /// Export errors.
    enum ExportError: LocalizedError {
        case noEntries
        case writeFailed(Error)
        case invalidDestination

        var errorDescription: String? {
            switch self {
            case .noEntries:
                return "No log entries to export."
            case .writeFailed(let error):
                return "Failed to write log file: \(error.localizedDescription)"
            case .invalidDestination:
                return "Invalid export destination."
            }
        }
    }

    // MARK: - Properties

    /// Logger for export operations.
    private static let logger = Logger.app

    // MARK: - Public Methods

    /// Exports log entries with a save panel for file location selection.
    ///
    /// Shows a save panel allowing the user to choose where to save the
    /// exported logs.
    ///
    /// - Parameters:
    ///   - entries: The log entries to export.
    ///   - tunnelName: Optional tunnel name for filename and header.
    ///   - format: The export format (default: plainText).
    /// - Returns: The export result.
    @MainActor
    static func exportWithSavePanel(
        entries: [LogEntry],
        tunnelName: String?,
        format: ExportFormat = .plainText
    ) async -> ExportResult {
        guard !entries.isEmpty else {
            return .failed(ExportError.noEntries)
        }

        // Create save panel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Logs"
        savePanel.message = "Choose a location to save the log file."
        savePanel.nameFieldLabel = "Export As:"
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false
        savePanel.allowedContentTypes = [.plainText]

        // Generate suggested filename
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .prefix(19)
        let tunnelPart = tunnelName ?? "all-tunnels"
        let suggestedName = "cloudflare-tunnel-logs-\(tunnelPart)-\(timestamp).\(format.fileExtension)"
        savePanel.nameFieldStringValue = suggestedName

        // Show panel
        let response = await savePanel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow())

        guard response == .OK, let url = savePanel.url else {
            return .cancelled
        }

        // Perform export
        do {
            try await exportToFile(entries: entries, tunnelName: tunnelName, destination: url, format: format)
            logger.info("Exported \(entries.count) log entries to \(url.path)")
            return .success(url)
        } catch {
            logger.error("Export failed: \(error.localizedDescription)")
            return .failed(error)
        }
    }

    /// Exports log entries to a specific file URL.
    ///
    /// - Parameters:
    ///   - entries: The log entries to export.
    ///   - tunnelName: Optional tunnel name for the header.
    ///   - destination: The file URL to write to.
    ///   - format: The export format.
    /// - Throws: `ExportError` if the export fails.
    static func exportToFile(
        entries: [LogEntry],
        tunnelName: String?,
        destination: URL,
        format: ExportFormat = .plainText
    ) async throws {
        guard !entries.isEmpty else {
            throw ExportError.noEntries
        }

        let content: String
        switch format {
        case .plainText:
            content = formatAsPlainText(entries: entries, tunnelName: tunnelName)
        case .rawLines:
            content = formatAsRawLines(entries: entries)
        }

        do {
            try content.write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(error)
        }
    }

    /// Exports log entries directly from a LogBuffer.
    ///
    /// - Parameters:
    ///   - buffer: The log buffer to export from.
    ///   - tunnelName: Optional tunnel name for the header.
    /// - Returns: The export result.
    @MainActor
    static func exportBuffer(
        _ buffer: LogBuffer,
        tunnelName: String?
    ) async -> ExportResult {
        let entries = await buffer.allEntries
        return await exportWithSavePanel(entries: entries, tunnelName: tunnelName)
    }

    /// Generates formatted text content for export.
    ///
    /// - Parameters:
    ///   - entries: The log entries to format.
    ///   - tunnelName: Optional tunnel name for the header.
    /// - Returns: Formatted text content.
    static func generateExportContent(
        entries: [LogEntry],
        tunnelName: String?
    ) -> String {
        formatAsPlainText(entries: entries, tunnelName: tunnelName)
    }

    // MARK: - Private Methods

    /// Formats entries as plain text with a header.
    private static func formatAsPlainText(entries: [LogEntry], tunnelName: String?) -> String {
        var lines: [String] = []

        // Header
        lines.append("# Tunnelflare - Log Export")
        if let name = tunnelName {
            lines.append("# Tunnel: \(name)")
        }
        lines.append("# Exported: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("# Lines: \(entries.count)")

        // Calculate statistics
        let stats = LogParser.computeStatistics(for: entries)
        if let earliest = stats.earliestTimestamp, let latest = stats.latestTimestamp {
            lines.append("# Time Range: \(formatTimestamp(earliest)) to \(formatTimestamp(latest))")
        }

        // Level breakdown
        let levelCounts = stats.countByLevel
        let levelSummary = LogLevel.allCases
            .compactMap { level -> String? in
                guard let count = levelCounts[level], count > 0 else { return nil }
                return "\(level.displayName): \(count)"
            }
            .joined(separator: ", ")
        if !levelSummary.isEmpty {
            lines.append("# Levels: \(levelSummary)")
        }

        lines.append("#")
        lines.append("")

        // Log entries
        for entry in entries {
            lines.append(entry.rawLine)
        }

        return lines.joined(separator: "\n")
    }

    /// Formats entries as raw log lines only.
    private static func formatAsRawLines(entries: [LogEntry]) -> String {
        entries.map { $0.rawLine }.joined(separator: "\n")
    }

    /// Formats a timestamp for display.
    private static func formatTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

// MARK: - Clipboard Export

extension LogExporter {
    /// Copies log entries to the clipboard.
    ///
    /// - Parameters:
    ///   - entries: The log entries to copy.
    ///   - tunnelName: Optional tunnel name for the header.
    ///   - includeHeader: Whether to include the header (default: true).
    /// - Returns: True if the copy succeeded.
    @MainActor
    static func copyToClipboard(
        entries: [LogEntry],
        tunnelName: String?,
        includeHeader: Bool = true
    ) -> Bool {
        guard !entries.isEmpty else { return false }

        let content: String
        if includeHeader {
            content = formatAsPlainText(entries: entries, tunnelName: tunnelName)
        } else {
            content = formatAsRawLines(entries: entries)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(content, forType: .string)
    }

    /// Copies a single log entry to the clipboard.
    ///
    /// - Parameter entry: The log entry to copy.
    /// - Returns: True if the copy succeeded.
    @MainActor
    static func copyEntryToClipboard(_ entry: LogEntry) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(entry.rawLine, forType: .string)
    }
}
