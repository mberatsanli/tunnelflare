//
//  TunnelStorageManager.swift
//  Tunnelflare
//
//  Created on 2026-01-17.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - TunnelStorageManager

/// Manages per-tunnel local storage for configuration caches and logs.
///
/// TunnelStorageManager provides a centralized way to manage tunnel-specific
/// files on disk. Each tunnel gets its own directory structure:
///
/// ```
/// ~/.tunnelflare/tunnels/<tunnel-id>/
/// ├── config.yml      # Cached tunnel configuration
/// └── logs/
///     └── <timestamp>.log
/// ```
///
/// ## Thread Safety
/// This is an actor, ensuring all file operations are thread-safe.
///
/// ## Usage
/// ```swift
/// let storage = TunnelStorageManager.shared
///
/// // Get tunnel directory
/// let dir = try await storage.tunnelDirectory(for: "abc123")
///
/// // Save config
/// try await storage.saveConfig(config, for: "abc123")
///
/// // Load cached ingress rules
/// let rules = await storage.loadCachedIngressRules(for: "abc123")
///
/// // Delete all tunnel data
/// try await storage.deleteTunnelData(for: "abc123")
/// ```
actor TunnelStorageManager {

    // MARK: - Singleton

    /// Shared instance of the TunnelStorageManager.
    static let shared = TunnelStorageManager()

    // MARK: - Properties

    /// Base directory for all tunnel data: ~/.tunnelflare/tunnels/
    let baseDirectory: URL

    /// Logger for storage operations.
    private let logger = Logger(subsystem: LogConstants.subsystem, category: "storage")

    /// File manager for file operations.
    private let fileManager = FileManager.default

    /// UserDefaults key for migration status.
    private let migrationKey = "v2_per_tunnel_storage_migration_complete"

    // MARK: - Initialization

    init() {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        self.baseDirectory = homeDirectory
            .appendingPathComponent(".tunnelflare", isDirectory: true)
            .appendingPathComponent("tunnels", isDirectory: true)
    }

    /// Creates a TunnelStorageManager with a custom base directory (for testing).
    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // MARK: - Directory Management

    /// Returns the directory for a tunnel, creating it if needed.
    ///
    /// - Parameter tunnelId: The tunnel's unique identifier.
    /// - Returns: The URL to the tunnel's directory.
    /// - Throws: If the directory cannot be created.
    func tunnelDirectory(for tunnelId: String) throws -> URL {
        let directory = baseDirectory.appendingPathComponent(tunnelId, isDirectory: true)

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            logger.info("Created tunnel directory: \(tunnelId)")
        }

        return directory
    }

    /// Returns the logs directory for a tunnel, creating it if needed.
    ///
    /// - Parameter tunnelId: The tunnel's unique identifier.
    /// - Returns: The URL to the tunnel's logs directory.
    /// - Throws: If the directory cannot be created.
    func logsDirectory(for tunnelId: String) throws -> URL {
        let tunnelDir = try tunnelDirectory(for: tunnelId)
        let logsDir = tunnelDir.appendingPathComponent("logs", isDirectory: true)

        if !fileManager.fileExists(atPath: logsDir.path) {
            try fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
            logger.info("Created logs directory for tunnel: \(tunnelId)")
        }

        return logsDir
    }

    /// Deletes all data for a tunnel (config cache and logs).
    ///
    /// - Parameter tunnelId: The tunnel's unique identifier.
    /// - Throws: If the directory cannot be deleted.
    func deleteTunnelData(for tunnelId: String) throws {
        let directory = baseDirectory.appendingPathComponent(tunnelId, isDirectory: true)

        guard fileManager.fileExists(atPath: directory.path) else {
            logger.debug("No data to delete for tunnel: \(tunnelId)")
            return
        }

        try fileManager.removeItem(at: directory)
        logger.info("Deleted all data for tunnel: \(tunnelId)")
    }

    /// Ensures the base tunnels directory exists.
    ///
    /// - Throws: If the directory cannot be created.
    func ensureBaseDirectoryExists() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
            logger.info("Created base tunnels directory")
        }
    }

    /// Returns all tunnel IDs that have local storage.
    ///
    /// - Returns: Array of tunnel IDs.
    func allStoredTunnelIds() -> [String] {
        guard fileManager.fileExists(atPath: baseDirectory.path) else {
            return []
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            return contents.compactMap { url in
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    return url.lastPathComponent
                }
                return nil
            }
        } catch {
            logger.error("Failed to list stored tunnels: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Config File

    /// Saves tunnel configuration as cloudflared config.yml.
    ///
    /// The configuration is saved as a valid cloudflared config file.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel's unique identifier.
    ///   - ingressRules: The ingress rules to save.
    /// - Throws: If the file cannot be written.
    func saveConfig(tunnelId: String, ingressRules: [IngressRule]) throws {
        let directory = try tunnelDirectory(for: tunnelId)
        let configPath = directory.appendingPathComponent("config.yml")

        let yaml = generateYAML(tunnelId: tunnelId, ingressRules: ingressRules)

        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        logger.debug("Saved config for tunnel: \(tunnelId)")
    }

    /// Loads ingress rules for a tunnel from config.yml.
    ///
    /// - Parameter tunnelId: The tunnel's unique identifier.
    /// - Returns: Array of ingress rules, or empty if not found.
    func loadIngressRules(for tunnelId: String) -> [IngressRule] {
        let configPath = baseDirectory
            .appendingPathComponent(tunnelId, isDirectory: true)
            .appendingPathComponent("config.yml")

        guard fileManager.fileExists(atPath: configPath.path) else {
            return []
        }

        do {
            let content = try String(contentsOf: configPath, encoding: .utf8)
            return parseIngressRules(from: content)
        } catch {
            logger.warning("Failed to load config for tunnel \(tunnelId): \(error.localizedDescription)")
            return []
        }
    }

    /// Checks if a config.yml exists for a tunnel.
    ///
    /// - Parameter tunnelId: The tunnel's unique identifier.
    /// - Returns: True if config exists.
    func hasConfig(for tunnelId: String) -> Bool {
        let configPath = baseDirectory
            .appendingPathComponent(tunnelId, isDirectory: true)
            .appendingPathComponent("config.yml")
        return fileManager.fileExists(atPath: configPath.path)
    }

    /// Returns the primary service URL for a tunnel.
    ///
    /// The primary service is the first ingress rule with a hostname (not catch-all).
    /// This is typically what the tunnel connects to (e.g., `http://localhost:3000`).
    ///
    /// - Parameter tunnelId: The tunnel's unique identifier.
    /// - Returns: The service URL string, or nil if not configured.
    func primaryServiceURL(for tunnelId: String) -> String? {
        let rules = loadIngressRules(for: tunnelId)

        // Find first rule with a hostname (not catch-all)
        for rule in rules {
            if rule.hostname != nil {
                return rule.service
            }
        }

        // If no hostname-based rules, check for non-catch-all service
        // (catch-all typically has service like "http_status:404")
        for rule in rules {
            let service = rule.service.lowercased()
            if !service.hasPrefix("http_status:") {
                return rule.service
            }
        }

        return nil
    }

    // MARK: - Migration

    /// Performs one-time migration from old storage structure.
    ///
    /// This deletes the old ~/.tunnelflare/logs/ directory and sets up
    /// the new per-tunnel structure.
    func performMigrationIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            return
        }

        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let oldLogsDir = homeDirectory
            .appendingPathComponent(".tunnelflare", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        // Delete old logs directory if it exists
        if fileManager.fileExists(atPath: oldLogsDir.path) {
            do {
                try fileManager.removeItem(at: oldLogsDir)
                logger.info("Migration: Deleted old logs directory")
            } catch {
                logger.error("Migration: Failed to delete old logs: \(error.localizedDescription)")
            }
        }

        // Ensure new structure exists
        do {
            try ensureBaseDirectoryExists()
        } catch {
            logger.error("Migration: Failed to create base directory: \(error.localizedDescription)")
        }

        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: migrationKey)
        logger.info("Migration to per-tunnel storage complete")
    }

    // MARK: - Private: YAML Handling

    /// Generates YAML content for cloudflared config.
    ///
    /// The output is a valid cloudflared config file.
    private func generateYAML(tunnelId: String, ingressRules: [IngressRule]) -> String {
        var yaml = """
        tunnel: \(tunnelId)

        ingress:
        """

        for rule in ingressRules {
            if let hostname = rule.hostname {
                yaml += "\n  - hostname: \(hostname)"
                if let path = rule.path {
                    yaml += "\n    path: \"\(path)\""
                }
                yaml += "\n    service: \(rule.service)"
            } else {
                yaml += "\n  - service: \(rule.service)"
            }
        }

        return yaml + "\n"
    }

    /// Parses ingress rules from YAML content.
    private func parseIngressRules(from content: String) -> [IngressRule] {
        var ingressRules: [IngressRule] = []

        let lines = content.components(separatedBy: .newlines)
        var currentRule: (hostname: String?, path: String?, service: String?)?
        var inIngress = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Ingress section
            if trimmed == "ingress:" {
                inIngress = true
            } else if inIngress {
                if trimmed.hasPrefix("- hostname:") || trimmed.hasPrefix("- service:") {
                    // Save previous rule if exists
                    if let rule = currentRule, let service = rule.service {
                        ingressRules.append(IngressRule(
                            hostname: rule.hostname,
                            path: rule.path,
                            service: service,
                            originRequest: nil
                        ))
                    }

                    // Start new rule
                    if trimmed.hasPrefix("- hostname:") {
                        currentRule = (
                            hostname: extractValue(from: trimmed, key: "- hostname:"),
                            path: nil,
                            service: nil
                        )
                    } else {
                        currentRule = (
                            hostname: nil,
                            path: nil,
                            service: extractValue(from: trimmed, key: "- service:")
                        )
                    }
                } else if trimmed.hasPrefix("path:"), var rule = currentRule {
                    rule.path = extractValue(from: trimmed, key: "path:")
                    currentRule = rule
                } else if trimmed.hasPrefix("service:"), var rule = currentRule {
                    rule.service = extractValue(from: trimmed, key: "service:")
                    currentRule = rule
                }
            }
        }

        // Don't forget the last rule
        if let rule = currentRule, let service = rule.service {
            ingressRules.append(IngressRule(
                hostname: rule.hostname,
                path: rule.path,
                service: service,
                originRequest: nil
            ))
        }

        return ingressRules
    }

    /// Extracts a value from a YAML line.
    private func extractValue(from line: String, key: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        var value = String(line[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)

        // Remove surrounding quotes
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }

        return value.isEmpty ? nil : value
    }
}
