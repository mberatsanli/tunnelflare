//
//  AuthEndpoints.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Auth Endpoints

/// Endpoints for authentication-related operations.
enum AuthEndpoints {

    // MARK: - Verify Token

    /// Endpoint to verify an API token.
    ///
    /// This endpoint validates that the current token is valid and
    /// returns information about the token.
    struct VerifyToken: Endpoint {
        typealias Response = TokenVerification

        let path = "user/tokens/verify"
        let method = HTTPMethod.get
    }
}

// MARK: - Token Verification Response

/// Response from token verification.
struct TokenVerification: Decodable {
    /// The token ID.
    let id: String

    /// The token status.
    let status: String

    /// When the token was not valid before.
    let notBefore: Date?

    /// When the token expires.
    let expiresOn: Date?

    /// Whether the token is active.
    var isActive: Bool {
        status.lowercased() == "active"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case notBefore = "not_before"
        case expiresOn = "expires_on"
    }
}
