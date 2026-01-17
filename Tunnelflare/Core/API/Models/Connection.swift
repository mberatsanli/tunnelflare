//
//  Connection.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Connection

/// Represents a connector/connection to a Cloudflare Tunnel.
///
/// A tunnel can have multiple connections from different connectors,
/// providing high availability. Each connection represents a cloudflared
/// instance connected to Cloudflare's edge.
///
/// ## Example JSON
/// ```json
/// {
///   "uuid": "connection-uuid",
///   "colo_name": "SJC",
///   "is_pending_reconnect": false,
///   "client_id": "client-uuid",
///   "client_version": "2024.1.1",
///   "opened_at": "2024-01-10T12:30:00Z"
/// }
/// ```
struct Connection: Codable, Identifiable, Hashable, Sendable {
    /// The unique identifier for this connection.
    let uuid: String

    /// The Cloudflare data center (colo) name where this connection terminates.
    let coloName: String

    /// Whether the connection is pending reconnection.
    let isPendingReconnect: Bool

    /// The client (cloudflared instance) identifier.
    let clientId: String?

    /// The version of cloudflared for this connector.
    let clientVersion: String?

    /// When this connection was opened.
    let openedAt: Date

    /// The origin IP of the connector.
    let originIp: String?

    /// Architecture of the cloudflared instance.
    let arch: String?

    // MARK: - Identifiable Conformance

    /// The unique identifier for this connection.
    var id: String { uuid }

    // MARK: - Computed Properties

    /// Whether this connection is healthy (not pending reconnect).
    var isHealthy: Bool {
        !isPendingReconnect
    }

    /// The connection duration from when it was opened.
    var connectionDuration: TimeInterval {
        Date().timeIntervalSince(openedAt)
    }

    /// A human-readable connection duration.
    var formattedDuration: String {
        let duration = connectionDuration

        if duration < 60 {
            return "Just now"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s")"
        } else if duration < 86400 {
            let hours = Int(duration / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let days = Int(duration / 86400)
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }

    /// Formatted opened date.
    var formattedOpenedAt: String {
        openedAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// A display string for the client version.
    var versionDisplay: String {
        clientVersion ?? "Unknown"
    }

    /// A display string for the architecture.
    var architectureDisplay: String {
        arch ?? "Unknown"
    }

    /// Combined version and architecture info.
    var connectorInfo: String {
        if let version = clientVersion, let arch = arch {
            return "\(version) (\(arch))"
        } else if let version = clientVersion {
            return version
        }
        return "Unknown version"
    }
}

// MARK: - Connection Extensions

extension Connection {
    /// Creates a placeholder connection for preview and testing.
    static var preview: Connection {
        Connection(
            uuid: "preview-connection-uuid",
            coloName: "SJC",
            isPendingReconnect: false,
            clientId: "preview-client-id",
            clientVersion: "2024.1.1",
            openedAt: Date().addingTimeInterval(-3600), // 1 hour ago
            originIp: "192.168.1.100",
            arch: "darwin_arm64"
        )
    }

    /// Creates a placeholder pending connection for preview and testing.
    static var pendingPreview: Connection {
        Connection(
            uuid: "preview-pending-connection-uuid",
            coloName: "LAX",
            isPendingReconnect: true,
            clientId: "preview-client-id-2",
            clientVersion: "2024.1.0",
            openedAt: Date().addingTimeInterval(-300), // 5 minutes ago
            originIp: nil,
            arch: "linux_amd64"
        )
    }
}

// MARK: - Connection Comparison

extension Connection: Comparable {
    static func < (lhs: Connection, rhs: Connection) -> Bool {
        // Sort by opened time, most recent first
        lhs.openedAt > rhs.openedAt
    }
}

// MARK: - Grouped Connector

/// Represents a cloudflared connector with its connections grouped together.
///
/// A single cloudflared instance (connector) typically creates 4 connections
/// to different Cloudflare edge data centers for high availability.
/// This struct groups those connections for display purposes.
struct GroupedConnector: Identifiable, Hashable {
    /// The unique identifier for this connector (clientId).
    let id: String

    /// The version of cloudflared.
    let version: String?

    /// The architecture of the connector.
    let arch: String?

    /// The origin IP of the connector.
    let originIp: String?

    /// Individual connections from this connector.
    let connections: [Connection]

    /// When this connector was first connected (earliest connection).
    var connectedAt: Date {
        connections.map(\.openedAt).min() ?? Date()
    }

    /// The data centers this connector is connected to.
    var datacenters: [String] {
        connections.map(\.coloName).sorted()
    }

    /// Comma-separated list of data centers.
    var datacentersList: String {
        datacenters.joined(separator: ", ")
    }

    /// Number of healthy connections.
    var healthyConnectionCount: Int {
        connections.filter(\.isHealthy).count
    }

    /// Whether all connections are healthy.
    var isHealthy: Bool {
        connections.allSatisfy(\.isHealthy)
    }

    /// Whether some connections are pending reconnect.
    var hasPendingConnections: Bool {
        connections.contains { $0.isPendingReconnect }
    }

    /// Combined version and architecture info.
    var connectorInfo: String {
        if let version = version, let arch = arch {
            return "\(version) (\(arch))"
        } else if let version = version {
            return version
        }
        return "Unknown version"
    }

    /// Connection duration from when first connected.
    var formattedDuration: String {
        let duration = Date().timeIntervalSince(connectedAt)

        if duration < 60 {
            return "Just now"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s")"
        } else if duration < 86400 {
            let hours = Int(duration / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else {
            let days = Int(duration / 86400)
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }

    /// Creates grouped connectors from a list of connections.
    static func group(from connections: [Connection]) -> [GroupedConnector] {
        // Group by clientId (or uuid if clientId is nil)
        let grouped = Dictionary(grouping: connections) { connection in
            connection.clientId ?? connection.uuid
        }

        return grouped.map { (clientId, connections) in
            let first = connections.first
            return GroupedConnector(
                id: clientId,
                version: first?.clientVersion,
                arch: first?.arch,
                originIp: first?.originIp,
                connections: connections.sorted { $0.openedAt < $1.openedAt }
            )
        }.sorted { $0.connectedAt < $1.connectedAt }
    }
}

// MARK: - Connector

/// Represents a cloudflared connector (used in some API responses).
///
/// This is an alternative representation of connection information
/// that may appear in certain API responses.
struct Connector: Codable, Identifiable, Hashable, Sendable {
    /// The unique identifier for the connector.
    let id: String

    /// The connector's run ID.
    let runId: String?

    /// The version of cloudflared.
    let version: String?

    /// The platform/architecture.
    let arch: String?

    /// Active connections for this connector.
    let connections: [ConnectorConnection]?

    enum CodingKeys: String, CodingKey {
        case id
        case runId = "run_id"
        case version
        case arch
        case connections
    }
}

/// A connection from a specific connector.
struct ConnectorConnection: Codable, Hashable, Sendable {
    /// The Cloudflare data center name.
    let coloName: String?

    /// Whether this connection is pending reconnect.
    let isPendingReconnect: Bool?

    /// The origin IP of the connector.
    let originIp: String?

    /// When this connection was opened.
    let openedAt: Date?

    enum CodingKeys: String, CodingKey {
        case coloName = "colo_name"
        case isPendingReconnect = "is_pending_reconnect"
        case originIp = "origin_ip"
        case openedAt = "opened_at"
    }
}
