//
//  Zone.swift
//  Tunnelflare
//
//  Created on 2026-01-12.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Zone

/// Represents a Cloudflare Zone (domain).
///
/// A zone is a domain that has been added to Cloudflare. Zones contain
/// DNS records and other configuration for the domain.
///
/// ## Example JSON
/// ```json
/// {
///   "id": "zone-uuid",
///   "name": "example.com",
///   "status": "active",
///   "paused": false,
///   "type": "full",
///   "development_mode": 0,
///   "name_servers": ["ns1.cloudflare.com", "ns2.cloudflare.com"],
///   "created_on": "2024-01-10T12:00:00Z",
///   "modified_on": "2024-01-10T12:00:00Z"
/// }
/// ```
struct Zone: Codable, Identifiable, Hashable, Sendable {
    /// The unique identifier for the zone.
    let id: String

    /// The domain name of the zone.
    let name: String

    /// The status of the zone (e.g., "active", "pending", "initializing").
    let status: ZoneStatus

    /// Whether the zone is paused.
    let paused: Bool

    /// The type of zone setup (e.g., "full", "partial").
    let type: String?

    /// Development mode status (0 = off, positive = seconds remaining).
    let developmentMode: Int?

    /// The name servers assigned to this zone.
    let nameServers: [String]?

    /// Original name servers before adding to Cloudflare.
    let originalNameServers: [String]?

    /// The date the zone was created.
    let createdOn: Date?

    /// The date the zone was last modified.
    let modifiedOn: Date?

    /// The account this zone belongs to.
    let account: ZoneAccount?

    // MARK: - Computed Properties

    /// Whether the zone is active and can be used for tunnels.
    var isActive: Bool {
        status == .active && !paused
    }

    /// A display-friendly status string.
    var statusDescription: String {
        if paused {
            return "Paused"
        }
        return status.displayName
    }
}

// MARK: - Zone Status

/// The status of a Cloudflare zone.
enum ZoneStatus: String, Codable, Sendable {
    /// Zone is active and fully functional.
    case active

    /// Zone is pending activation (name server change needed).
    case pending

    /// Zone is initializing.
    case initializing

    /// Zone is in a moved state.
    case moved

    /// Zone has been deleted.
    case deleted

    /// Zone is deactivated.
    case deactivated

    /// Unknown status.
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = ZoneStatus(rawValue: rawValue) ?? .unknown
    }

    /// A display-friendly name for the status.
    var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .pending:
            return "Pending"
        case .initializing:
            return "Initializing"
        case .moved:
            return "Moved"
        case .deleted:
            return "Deleted"
        case .deactivated:
            return "Deactivated"
        case .unknown:
            return "Unknown"
        }
    }
}

// MARK: - Zone Account

/// Minimal account information associated with a zone.
struct ZoneAccount: Codable, Hashable, Sendable {
    /// The account ID.
    let id: String

    /// The account name.
    let name: String?
}

// MARK: - DNS Record

/// Represents a DNS record in a Cloudflare zone.
///
/// Used for checking if a subdomain already exists.
struct DNSRecord: Codable, Identifiable, Hashable, Sendable {
    /// The unique identifier for the record.
    let id: String

    /// The record type (e.g., "A", "AAAA", "CNAME", "TXT").
    let type: String

    /// The DNS record name (e.g., "app.example.com").
    let name: String

    /// The record content/value.
    let content: String

    /// Whether the record is proxied through Cloudflare.
    let proxied: Bool?

    /// The TTL for the record (1 = auto).
    let ttl: Int?

    /// The date the record was created.
    let createdOn: Date?

    /// The date the record was last modified.
    let modifiedOn: Date?

    // MARK: - Computed Properties

    /// The subdomain part of the name (without the zone).
    func subdomain(for zone: String) -> String? {
        guard name.hasSuffix(".\(zone)") else {
            return name == zone ? nil : name
        }
        return String(name.dropLast(zone.count + 1))
    }

    /// Whether this is a CNAME record (commonly used for tunnels).
    var isCNAME: Bool {
        type == "CNAME"
    }
}

// MARK: - Zone Extensions

extension Zone {
    /// Creates a placeholder zone for preview and testing.
    static var preview: Zone {
        Zone(
            id: "preview-zone-id",
            name: "example.com",
            status: .active,
            paused: false,
            type: "full",
            developmentMode: 0,
            nameServers: ["ns1.cloudflare.com", "ns2.cloudflare.com"],
            originalNameServers: nil,
            createdOn: Date(),
            modifiedOn: Date(),
            account: ZoneAccount(id: "account-id", name: "My Account")
        )
    }
}
