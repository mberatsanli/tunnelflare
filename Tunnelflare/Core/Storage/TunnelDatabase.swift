//
//  TunnelDatabase.swift
//  Tunnelflare
//
//  Created on 2026-01-17.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SQLite3
import os.log

// MARK: - TunnelDatabase

/// SQLite database for storing tunnel metadata.
///
/// Stores tunnel information locally for quick access without API calls.
/// The database is stored in the app's Application Support directory.
///
/// ## Usage
/// ```swift
/// let db = TunnelDatabase.shared
///
/// // Save/update tunnel
/// try await db.upsertTunnel(tunnel)
///
/// // Get all tunnels
/// let tunnels = await db.getAllTunnels()
///
/// // Delete tunnel
/// try await db.deleteTunnel(id: "abc123")
/// ```
actor TunnelDatabase {

    // MARK: - Singleton

    /// Shared instance of the TunnelDatabase.
    static let shared = TunnelDatabase()

    // MARK: - Properties

    /// SQLite database handle.
    private var db: OpaquePointer?

    /// Logger for database operations.
    private let logger = Logger(subsystem: LogConstants.subsystem, category: "database")

    /// Database file URL.
    private let databaseURL: URL

    // MARK: - Initialization

    init() {
        // Store in Application Support/Tunnelflare/
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Tunnelflare", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.databaseURL = appDir.appendingPathComponent("tunnelflare.db")
    }

    /// Creates a TunnelDatabase with a custom path (for testing).
    init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    // MARK: - Database Lifecycle

    /// Opens the database and creates tables if needed.
    func open() throws {
        guard db == nil else { return }

        let result = sqlite3_open(databaseURL.path, &db)
        guard result == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.openFailed(error)
        }

        logger.info("Database opened at: \(self.databaseURL.path)")
        try createTables()
    }

    /// Closes the database.
    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
            logger.info("Database closed")
        }
    }

    /// Creates the required tables.
    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS tunnels (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            account_id TEXT NOT NULL,
            status TEXT,
            created_at TEXT,
            connections_count INTEGER DEFAULT 0,
            cached_at TEXT NOT NULL,
            last_connected_at TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_tunnels_account ON tunnels(account_id);
        """

        try execute(sql)

        // Migrate existing tables to add last_connected_at column
        try migrateIfNeeded()

        logger.debug("Tables created/verified")
    }

    /// Migrates the database schema if needed.
    private func migrateIfNeeded() throws {
        // Check if last_connected_at column exists
        let checkSql = "PRAGMA table_info(tunnels);"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, checkSql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }

        var hasLastConnectedAt = false
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(stmt, 1) {
                let name = String(cString: namePtr)
                if name == "last_connected_at" {
                    hasLastConnectedAt = true
                    break
                }
            }
        }

        // Add column if it doesn't exist
        if !hasLastConnectedAt {
            let alterSql = "ALTER TABLE tunnels ADD COLUMN last_connected_at TEXT;"
            try execute(alterSql)
            logger.info("Migrated database: added last_connected_at column")
        }
    }

    // MARK: - Tunnel Operations

    /// Inserts or updates a tunnel record.
    ///
    /// - Parameter tunnel: The tunnel to save.
    /// - Parameter preserveLastConnected: If true, preserves existing last_connected_at value.
    func upsertTunnel(_ tunnel: TunnelRecord, preserveLastConnected: Bool = true) throws {
        try ensureOpen()

        let sql: String
        if preserveLastConnected {
            // Preserve existing last_connected_at when updating
            sql = """
            INSERT INTO tunnels (id, name, account_id, status, created_at, connections_count, cached_at, last_connected_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                account_id = excluded.account_id,
                status = excluded.status,
                created_at = excluded.created_at,
                connections_count = excluded.connections_count,
                cached_at = excluded.cached_at;
            """
        } else {
            sql = """
            INSERT INTO tunnels (id, name, account_id, status, created_at, connections_count, cached_at, last_connected_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                account_id = excluded.account_id,
                status = excluded.status,
                created_at = excluded.created_at,
                connections_count = excluded.connections_count,
                cached_at = excluded.cached_at,
                last_connected_at = excluded.last_connected_at;
            """
        }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }

        let cachedAt = ISO8601DateFormatter().string(from: Date())

        sqlite3_bind_text(stmt, 1, tunnel.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, tunnel.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, tunnel.accountId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, tunnel.status ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 5, tunnel.createdAt ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 6, Int32(tunnel.connectionsCount))
        sqlite3_bind_text(stmt, 7, cachedAt, -1, SQLITE_TRANSIENT)
        if let lastConnected = tunnel.lastConnectedAt {
            sqlite3_bind_text(stmt, 8, lastConnected, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 8)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(lastError)
        }

        logger.debug("Upserted tunnel: \(tunnel.name)")
    }

    /// Inserts or updates multiple tunnels.
    ///
    /// - Parameter tunnels: The tunnels to save.
    func upsertTunnels(_ tunnels: [TunnelRecord]) throws {
        try ensureOpen()

        try execute("BEGIN TRANSACTION;")
        defer {
            try? execute("COMMIT;")
        }

        for tunnel in tunnels {
            try upsertTunnel(tunnel)
        }
    }

    /// Gets all tunnels for an account.
    ///
    /// - Parameter accountId: The account ID.
    /// - Returns: Array of tunnel records.
    func getTunnels(accountId: String) throws -> [TunnelRecord] {
        try ensureOpen()

        let sql = "SELECT id, name, account_id, status, created_at, connections_count, cached_at, last_connected_at FROM tunnels WHERE account_id = ?;"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }

        sqlite3_bind_text(stmt, 1, accountId, -1, SQLITE_TRANSIENT)

        var tunnels: [TunnelRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let record = parseTunnelRow(stmt) {
                tunnels.append(record)
            }
        }

        return tunnels
    }

    /// Gets all tunnels.
    ///
    /// - Returns: Array of all tunnel records.
    func getAllTunnels() throws -> [TunnelRecord] {
        try ensureOpen()

        let sql = "SELECT id, name, account_id, status, created_at, connections_count, cached_at, last_connected_at FROM tunnels;"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }

        var tunnels: [TunnelRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let record = parseTunnelRow(stmt) {
                tunnels.append(record)
            }
        }

        return tunnels
    }

    /// Gets a single tunnel by ID.
    ///
    /// - Parameter id: The tunnel ID.
    /// - Returns: The tunnel record, or nil if not found.
    func getTunnel(id: String) throws -> TunnelRecord? {
        try ensureOpen()

        let sql = "SELECT id, name, account_id, status, created_at, connections_count, cached_at, last_connected_at FROM tunnels WHERE id = ?;"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return parseTunnelRow(stmt)
        }

        return nil
    }

    /// Deletes a tunnel record.
    ///
    /// - Parameter id: The tunnel ID to delete.
    func deleteTunnel(id: String) throws {
        try ensureOpen()

        let sql = "DELETE FROM tunnels WHERE id = ?;"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(lastError)
        }

        logger.info("Deleted tunnel from database: \(id)")
    }

    /// Deletes all tunnels for an account.
    ///
    /// - Parameter accountId: The account ID.
    func deleteTunnels(accountId: String) throws {
        try ensureOpen()

        let sql = "DELETE FROM tunnels WHERE account_id = ?;"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }

        sqlite3_bind_text(stmt, 1, accountId, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(lastError)
        }

        logger.info("Deleted all tunnels for account: \(accountId)")
    }

    // MARK: - Sync Operations

    /// Syncs tunnels from API - removes tunnels that no longer exist.
    ///
    /// - Parameters:
    ///   - tunnels: Current tunnels from API.
    ///   - accountId: The account ID.
    /// - Returns: IDs of tunnels that were removed.
    func syncTunnels(_ tunnels: [TunnelRecord], accountId: String) throws -> [String] {
        try ensureOpen()

        // Get existing tunnel IDs
        let existing = try getTunnels(accountId: accountId)
        let existingIds = Set(existing.map { $0.id })
        let newIds = Set(tunnels.map { $0.id })

        // Find removed tunnels
        let removedIds = existingIds.subtracting(newIds)

        // Delete removed tunnels
        for id in removedIds {
            try deleteTunnel(id: id)
        }

        // Upsert current tunnels
        try upsertTunnels(tunnels)

        return Array(removedIds)
    }

    // MARK: - Last Connected Time

    /// Updates the last connected time for a tunnel.
    ///
    /// - Parameters:
    ///   - tunnelId: The tunnel ID.
    ///   - date: The connection date.
    func updateLastConnectedAt(tunnelId: String, date: Date) throws {
        try ensureOpen()

        let sql = "UPDATE tunnels SET last_connected_at = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(lastError)
        }

        let dateString = ISO8601DateFormatter().string(from: date)
        sqlite3_bind_text(stmt, 1, dateString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, tunnelId, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.executeFailed(lastError)
        }

        logger.debug("Updated last connected time for tunnel: \(tunnelId)")
    }

    // MARK: - Private Helpers

    /// Ensures the database is open.
    private func ensureOpen() throws {
        if db == nil {
            try open()
        }
    }

    /// Executes a SQL statement.
    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let error = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw DatabaseError.executeFailed(error)
        }
    }

    /// Gets the last SQLite error message.
    private var lastError: String {
        String(cString: sqlite3_errmsg(db))
    }

    /// Parses a tunnel row from a statement.
    private func parseTunnelRow(_ stmt: OpaquePointer?) -> TunnelRecord? {
        guard let stmt = stmt else { return nil }

        guard let idPtr = sqlite3_column_text(stmt, 0),
              let namePtr = sqlite3_column_text(stmt, 1),
              let accountIdPtr = sqlite3_column_text(stmt, 2) else {
            return nil
        }

        let id = String(cString: idPtr)
        let name = String(cString: namePtr)
        let accountId = String(cString: accountIdPtr)

        let status = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let createdAt = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
        let connectionsCount = Int(sqlite3_column_int(stmt, 5))
        // Column 6 is cached_at (not needed in record)
        let lastConnectedAt = sqlite3_column_text(stmt, 7).map { String(cString: $0) }

        return TunnelRecord(
            id: id,
            name: name,
            accountId: accountId,
            status: status,
            createdAt: createdAt,
            connectionsCount: connectionsCount,
            lastConnectedAt: lastConnectedAt
        )
    }
}

// MARK: - SQLITE_TRANSIENT

/// SQLite transient constant for string binding.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - TunnelRecord

/// A record representing a tunnel in the database.
struct TunnelRecord: Sendable {
    let id: String
    let name: String
    let accountId: String
    let status: String?
    let createdAt: String?
    let connectionsCount: Int
    let lastConnectedAt: String?

    /// Creates a TunnelRecord from a Tunnel model.
    init(from tunnel: Tunnel, accountId: String) {
        self.id = tunnel.id
        self.name = tunnel.name
        self.accountId = accountId
        self.status = tunnel.status?.rawValue
        self.createdAt = ISO8601DateFormatter().string(from: tunnel.createdAt)
        self.connectionsCount = tunnel.connections.count
        self.lastConnectedAt = nil
    }

    /// Creates a TunnelRecord directly.
    init(id: String, name: String, accountId: String, status: String?, createdAt: String?, connectionsCount: Int, lastConnectedAt: String? = nil) {
        self.id = id
        self.name = name
        self.accountId = accountId
        self.status = status
        self.createdAt = createdAt
        self.connectionsCount = connectionsCount
        self.lastConnectedAt = lastConnectedAt
    }

    /// Converts the record back to a Tunnel model.
    ///
    /// Note: This creates a Tunnel without connections (empty array).
    /// The connections will be populated when the API data is fetched.
    func toTunnel() -> Tunnel {
        let dateFormatter = ISO8601DateFormatter()
        let createdAtDate = createdAt.flatMap { dateFormatter.date(from: $0) } ?? Date()
        let tunnelStatus = status.flatMap { TunnelStatus(rawValue: $0) }

        return Tunnel(
            id: id,
            name: name,
            createdAt: createdAtDate,
            deletedAt: nil,
            connections: [], // Will be populated from API
            status: tunnelStatus,
            accountTag: accountId,
            connsActiveAt: nil,
            metadata: nil
        )
    }
}

// MARK: - DatabaseError

/// Errors that can occur during database operations.
enum DatabaseError: LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case executeFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Failed to open database: \(message)"
        case .prepareFailed(let message):
            return "Failed to prepare statement: \(message)"
        case .executeFailed(let message):
            return "Failed to execute statement: \(message)"
        }
    }
}
