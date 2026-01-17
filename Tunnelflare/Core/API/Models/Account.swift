//
//  Account.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Account

/// Represents a Cloudflare account (organization).
///
/// An account can be a personal account or an organization that the user
/// has access to. Tunnels are scoped to accounts.
///
/// ## Example JSON
/// ```json
/// {
///   "id": "account-id-123",
///   "name": "Personal Account",
///   "type": "standard"
/// }
/// ```
struct Account: Codable, Identifiable, Hashable, Sendable {
    /// The unique identifier for the account.
    let id: String

    /// The display name of the account.
    let name: String

    /// The type of account (e.g., "standard", "enterprise").
    let type: String?

    /// Settings for the account.
    let settings: AccountSettings?

    /// The date the account was created.
    let createdOn: Date?

    // MARK: - Computed Properties

    /// Whether this is an enterprise account.
    var isEnterprise: Bool {
        type?.lowercased() == "enterprise"
    }

    /// A short description of the account type.
    var typeDescription: String {
        switch type?.lowercased() {
        case "enterprise":
            return "Enterprise"
        case "standard":
            return "Standard"
        case "free":
            return "Free"
        default:
            return type ?? "Standard"
        }
    }
}

// MARK: - AccountSettings

/// Settings for a Cloudflare account.
struct AccountSettings: Codable, Hashable, Sendable {
    /// Whether enforcement mode is on.
    let enforceTwofactor: Bool?

    /// Whether the account uses legacy name servers.
    let useLegacyNs: Bool?

    /// Access approval expiration.
    let accessApprovalExpiry: String?

    enum CodingKeys: String, CodingKey {
        case enforceTwofactor = "enforce_twofactor"
        case useLegacyNs = "use_legacy_ns"
        case accessApprovalExpiry = "access_approval_expiry"
    }
}

// MARK: - Organization Type Alias

/// Type alias for Account, as organizations are equivalent to accounts
/// in the Cloudflare API context.
typealias Organization = Account

// MARK: - Account Extensions

extension Account {
    /// Creates a placeholder account for preview and testing.
    static var preview: Account {
        Account(
            id: "preview-account-id",
            name: "Personal Account",
            type: "standard",
            settings: nil,
            createdOn: Date()
        )
    }

    /// Creates a placeholder enterprise account for preview and testing.
    static var enterprisePreview: Account {
        Account(
            id: "preview-enterprise-id",
            name: "Acme Corporation",
            type: "enterprise",
            settings: AccountSettings(
                enforceTwofactor: true,
                useLegacyNs: false,
                accessApprovalExpiry: nil
            ),
            createdOn: Date()
        )
    }
}

// MARK: - Account Comparison

extension Account: Comparable {
    static func < (lhs: Account, rhs: Account) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
