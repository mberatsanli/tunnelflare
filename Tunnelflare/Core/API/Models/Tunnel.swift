//
//  Tunnel.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Tunnel

/// Represents a Cloudflare Tunnel.
///
/// A tunnel provides a secure connection between your origin server and
/// Cloudflare's edge network without exposing your origin IP.
///
/// ## Example JSON
/// ```json
/// {
///   "id": "tunnel-uuid",
///   "name": "my-tunnel",
///   "created_at": "2024-01-10T12:00:00Z",
///   "deleted_at": null,
///   "connections": [...],
///   "status": "healthy"
/// }
/// ```
struct Tunnel: Codable, Identifiable, Hashable, Sendable {
    /// The unique identifier for the tunnel.
    let id: String

    /// The name of the tunnel.
    let name: String

    /// The date the tunnel was created.
    let createdAt: Date

    /// The date the tunnel was deleted, if applicable.
    let deletedAt: Date?

    /// Active connections for this tunnel.
    let connections: [Connection]

    /// The overall status of the tunnel.
    let status: TunnelStatus?

    /// The account tag (account ID) this tunnel belongs to.
    let accountTag: String?

    /// Whether tunnel connectivity is expected.
    let connsActiveAt: Date?

    /// The tunnel's metadata.
    let metadata: TunnelMetadata?

    // MARK: - Computed Properties

    /// Whether the tunnel is active (not deleted and has connections).
    var isActive: Bool {
        deletedAt == nil && !connections.isEmpty
    }

    /// Whether the tunnel has been deleted.
    var isDeleted: Bool {
        deletedAt != nil
    }

    /// Whether the tunnel is healthy.
    var isHealthy: Bool {
        status == .healthy
    }

    /// The number of active connections.
    var activeConnectionCount: Int {
        connections.count
    }

    /// The number of connectors (cloudflared instances).
    var connectorCount: Int {
        groupedConnectors.count
    }

    /// Connections grouped by connector (clientId).
    var groupedConnectors: [GroupedConnector] {
        GroupedConnector.group(from: connections)
    }

    /// Whether this tunnel has any connections.
    var hasConnections: Bool {
        !connections.isEmpty
    }

    /// The most recent connection, if any.
    var latestConnection: Connection? {
        connections.sorted { $0.openedAt > $1.openedAt }.first
    }

    /// Formatted creation date.
    var formattedCreatedAt: String {
        createdAt.formatted(date: .abbreviated, time: .shortened)
    }

    /// A human-readable status description.
    var statusDescription: String {
        if isDeleted {
            return "Deleted"
        } else if isActive {
            return status?.rawValue.capitalized ?? "Active"
        } else {
            return "Inactive"
        }
    }
}

// MARK: - TunnelStatus

/// The status of a tunnel.
enum TunnelStatus: String, Codable, Sendable {
    /// Tunnel is healthy with all connections active.
    case healthy

    /// Tunnel is degraded with some connections having issues.
    case degraded

    /// Tunnel has no active connections.
    case inactive

    /// Tunnel is in the process of reconnecting.
    case down

    /// Display name for the status.
    var displayName: String {
        switch self {
        case .healthy:
            return "Healthy"
        case .degraded:
            return "Degraded"
        case .inactive:
            return "Inactive"
        case .down:
            return "Down"
        }
    }

    /// System image name for the status.
    var systemImage: String {
        switch self {
        case .healthy:
            return "checkmark.circle.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        case .inactive:
            return "minus.circle.fill"
        case .down:
            return "xmark.circle.fill"
        }
    }
}

// MARK: - TunnelMetadata

/// Metadata associated with a tunnel.
struct TunnelMetadata: Codable, Hashable, Sendable {
    /// Whether this is a legacy CNAME tunnel.
    let isLegacy: Bool?

    /// The source of the tunnel configuration.
    let configSrc: String?

    enum CodingKeys: String, CodingKey {
        case isLegacy = "is_legacy"
        case configSrc = "config_src"
    }
}

// MARK: - Tunnel Extensions

extension Tunnel {
    /// Creates a placeholder tunnel for preview and testing.
    static var preview: Tunnel {
        Tunnel(
            id: "preview-tunnel-id",
            name: "my-dev-tunnel",
            createdAt: Date().addingTimeInterval(-86400 * 7), // 1 week ago
            deletedAt: nil,
            connections: [.preview],
            status: .healthy,
            accountTag: "preview-account",
            connsActiveAt: Date(),
            metadata: TunnelMetadata(isLegacy: false, configSrc: "cloudflare")
        )
    }

    /// Creates a placeholder inactive tunnel for preview and testing.
    static var inactivePreview: Tunnel {
        Tunnel(
            id: "preview-inactive-tunnel-id",
            name: "api-tunnel",
            createdAt: Date().addingTimeInterval(-86400 * 30), // 30 days ago
            deletedAt: nil,
            connections: [],
            status: .inactive,
            accountTag: "preview-account",
            connsActiveAt: nil,
            metadata: nil
        )
    }
}

// MARK: - Tunnel Comparison

extension Tunnel: Comparable {
    static func < (lhs: Tunnel, rhs: Tunnel) -> Bool {
        // Sort by: active status, then by name
        if lhs.isActive != rhs.isActive {
            return lhs.isActive
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - Create Tunnel Request

/// Request body for creating a new tunnel.
struct CreateTunnelRequest: Encodable {
    /// The name for the new tunnel.
    let name: String

    /// The configuration source (usually "cloudflare").
    let configSrc: String

    /// The tunnel secret (for legacy tunnels, usually omitted).
    let tunnelSecret: String?

    init(name: String, configSrc: String = "cloudflare", tunnelSecret: String? = nil) {
        self.name = name
        self.configSrc = configSrc
        self.tunnelSecret = tunnelSecret
    }

    enum CodingKeys: String, CodingKey {
        case name
        case configSrc = "config_src"
        case tunnelSecret = "tunnel_secret"
    }
}
