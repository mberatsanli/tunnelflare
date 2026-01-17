//
//  User.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - User

/// Represents a Cloudflare user profile.
///
/// Contains the user's basic profile information from the `/user` endpoint.
///
/// ## Example JSON
/// ```json
/// {
///   "id": "user-id-123",
///   "email": "user@example.com",
///   "first_name": "John",
///   "last_name": "Doe",
///   "username": "johndoe"
/// }
/// ```
struct User: Codable, Identifiable, Hashable, Sendable {
    /// The unique identifier for the user.
    let id: String

    /// The user's email address.
    let email: String

    /// The user's first name.
    let firstName: String?

    /// The user's last name.
    let lastName: String?

    /// The user's username.
    let username: String?

    /// Two-factor authentication status.
    let twoFactorAuthenticationEnabled: Bool?

    /// Whether the user's email has been verified.
    let suspended: Bool?

    /// The date the user was created.
    let createdOn: Date?

    /// The date the user was last modified.
    let modifiedOn: Date?

    // MARK: - Computed Properties

    /// The user's display name.
    ///
    /// Returns the full name if available, otherwise the email.
    var displayName: String {
        if let first = firstName, let last = lastName, !first.isEmpty && !last.isEmpty {
            return "\(first) \(last)"
        } else if let first = firstName, !first.isEmpty {
            return first
        } else if let username = username, !username.isEmpty {
            return username
        }
        return email
    }

    /// The user's initials for avatar display.
    var initials: String {
        if let first = firstName?.first, let last = lastName?.first {
            return "\(first)\(last)".uppercased()
        } else if let first = email.first {
            return String(first).uppercased()
        }
        return "?"
    }

    /// Whether two-factor authentication is enabled.
    var has2FA: Bool {
        twoFactorAuthenticationEnabled ?? false
    }
}

// MARK: - User Extensions

extension User {
    /// Creates a placeholder user for preview and testing.
    static var preview: User {
        User(
            id: "preview-user-id",
            email: "user@example.com",
            firstName: "John",
            lastName: "Doe",
            username: "johndoe",
            twoFactorAuthenticationEnabled: true,
            suspended: false,
            createdOn: Date(),
            modifiedOn: Date()
        )
    }
}
