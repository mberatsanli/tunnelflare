//
//  LogFileWriter.swift
//  Tunnelflare
//
//  Created on 2026-01-13.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - LogFileWriter

/// Manages writing tunnel logs to disk.
///
/// LogFileWriter creates and maintains log files for each tunnel session.
/// Logs are stored in `~/.tunnelflare/logs/<tunnel-id>-<timestamp>.log`.
///
/// ## Usage
/// ```swift
/// let writer = LogFileWriter()
///
/// // Start logging for a tunnel
/// try await writer.startLogging(tunnelId: "my-tunnel")
///
/// // Write log entries
/// await writer.writeLog(tunnelId: "my-tunnel", entry: logEntry)
///
/// // Stop logging
/// await writer.stopLogging(tunnelId: "my-tunnel")
/// ```
actor LogFileWriter {

    // MARK: - Properties

    /// Active log file handles, keyed by tunnel ID.
    private var fileHandles: [String: FileHandle] = [:]

    /// Log file paths, keyed by tunnel ID.
    private var filePaths: [String: URL] = [:]

    /// Start timestamps for each tunnel session.
    private var startTimestamps: [String: Date] = [:]

    /// Logger for file operations.
    private let logger = Logger.app

    /// The base directory for log files.
    private let logsDirectory: URL

    /// Date formatter for log file timestamps.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    // MARK: - Initialization

    init() {
        // Set up logs directory at ~/.tunnelflare/logs/
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.logsDirectory = homeDirectory
            .appendingPathComponent(".tunnelflare", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }

    // MARK: - Public Methods

    /// Starts logging for a tunnel session.
    ///
    /// Creates a new log file and begins writing logs.
    ///
    /// - Parameter tunnelId: The tunnel ID to start logging for.
    /// - Throws: If the log file cannot be created.
    func startLogging(tunnelId: String) throws {
        // Close any existing file for this tunnel
        closeFile(for: tunnelId)

        // Ensure logs directory exists
        try ensureLogsDirectoryExists()

        // Create log file with timestamp
        let timestamp = Date()
        let timestampString = Self.timestampFormatter.string(from: timestamp)
        let filename = "\(tunnelId)-\(timestampString).log"
        let filePath = logsDirectory.appendingPathComponent(filename)

        // Create the file
        FileManager.default.createFile(atPath: filePath.path, contents: nil)

        // Open for writing
        let fileHandle = try FileHandle(forWritingTo: filePath)

        // Seek to end (in case file already had content)
        try fileHandle.seekToEnd()

        // Store references
        fileHandles[tunnelId] = fileHandle
        filePaths[tunnelId] = filePath
        startTimestamps[tunnelId] = timestamp

        // Write header
        let header = "# Cloudflare Tunnel Log\n# Tunnel ID: \(tunnelId)\n# Started: \(timestamp.ISO8601Format())\n\n"
        if let data = header.data(using: .utf8) {
            try fileHandle.write(contentsOf: data)
        }

        logger.info("Started logging for tunnel \(tunnelId) at \(filePath.path)")
    }

    /// Writes a log entry to the file.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID.
    ///   - entry: The log entry to write.
    func writeLog(tunnelId: String, entry: LogEntry) {
        guard let fileHandle = fileHandles[tunnelId] else {
            return
        }

        let line = "[\(entry.formattedTimestamp)] [\(entry.level.rawValue.uppercased())] \(entry.message)\n"
        if let data = line.data(using: .utf8) {
            do {
                try fileHandle.write(contentsOf: data)
            } catch {
                logger.error("Failed to write log entry: \(error.localizedDescription)")
            }
        }
    }

    /// Writes a raw log line to the file.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID.
    ///   - line: The raw log line.
    func writeRawLog(tunnelId: String, line: String) {
        guard let fileHandle = fileHandles[tunnelId] else {
            return
        }

        let formattedLine = line.hasSuffix("\n") ? line : line + "\n"
        if let data = formattedLine.data(using: .utf8) {
            do {
                try fileHandle.write(contentsOf: data)
            } catch {
                logger.error("Failed to write raw log: \(error.localizedDescription)")
            }
        }
    }

    /// Stops logging for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID to stop logging for.
    func stopLogging(tunnelId: String) {
        guard let fileHandle = fileHandles[tunnelId] else {
            return
        }

        // Write footer
        let footer = "\n# Session ended: \(Date().ISO8601Format())\n"
        if let data = footer.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }

        closeFile(for: tunnelId)

        if let path = filePaths[tunnelId] {
            logger.info("Stopped logging for tunnel \(tunnelId), saved to \(path.path)")
        }

        filePaths.removeValue(forKey: tunnelId)
        startTimestamps.removeValue(forKey: tunnelId)
    }

    /// Gets the log file path for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID.
    /// - Returns: The log file URL, or nil if not logging.
    func getLogFilePath(tunnelId: String) -> URL? {
        filePaths[tunnelId]
    }

    /// Gets all log files in the logs directory.
    ///
    /// - Returns: Array of log file URLs.
    func getAllLogFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: logsDirectory.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return contents
            .filter { $0.pathExtension == "log" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 > date2
            }
    }

    /// Cleans up old log files.
    ///
    /// - Parameter daysToKeep: Number of days of logs to keep.
    func cleanupOldLogs(daysToKeep: Int = 30) throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: Date()) ?? Date()

        let logFiles = try getAllLogFiles()

        for file in logFiles {
            guard let modificationDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
                continue
            }

            if modificationDate < cutoffDate {
                try FileManager.default.removeItem(at: file)
                logger.info("Deleted old log file: \(file.lastPathComponent)")
            }
        }
    }

    /// Closes all open log files.
    func closeAll() {
        for tunnelId in fileHandles.keys {
            closeFile(for: tunnelId)
        }
        fileHandles.removeAll()
        filePaths.removeAll()
        startTimestamps.removeAll()
    }

    // MARK: - Private Methods

    /// Ensures the logs directory exists.
    private func ensureLogsDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: logsDirectory.path) {
            try FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            logger.info("Created logs directory at \(self.logsDirectory.path)")
        }
    }

    /// Closes a file handle for a tunnel.
    private func closeFile(for tunnelId: String) {
        if let fileHandle = fileHandles[tunnelId] {
            try? fileHandle.close()
            fileHandles.removeValue(forKey: tunnelId)
        }
    }
}

// MARK: - Sendable Conformance

extension LogFileWriter: Sendable {}
