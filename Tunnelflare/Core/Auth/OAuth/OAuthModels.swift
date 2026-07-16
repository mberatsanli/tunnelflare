//
//  OAuthModels.swift
//  Tunnelflare
//
//  Created on 2026-07-15.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Server Metadata

/// OAuth 2.0 Authorization Server Metadata (RFC 8414).
///
/// Fetched from the discovery endpoint. Only the fields the app needs are
/// decoded; unknown fields are tolerated and ignored.
struct OAuthServerMetadata: Decodable {
    /// The authorization endpoint URL (`authorization_endpoint`).
    let authorizationEndpoint: URL

    /// The token endpoint URL (`token_endpoint`).
    let tokenEndpoint: URL

    private enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
    }
}

// MARK: - Token Response

/// The raw response from the OAuth token endpoint.
///
/// Returned by both the authorization-code exchange and the refresh grant.
struct OAuthTokenResponse: Decodable {
    /// The access token used to authorize API requests.
    let accessToken: String

    /// The token type (typically `Bearer`).
    let tokenType: String?

    /// Lifetime of the access token in seconds, if provided.
    let expiresIn: Int?

    /// The refresh token, if the server issued one.
    let refreshToken: String?

    /// The granted scope, if returned.
    let scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

// MARK: - Persisted Tokens

/// The OAuth tokens persisted to the Keychain.
///
/// Stores the access token, optional refresh token, and the absolute expiry
/// `Date` so expiry can be evaluated without relying on wall-clock deltas.
struct OAuthTokens: Codable, Equatable {
    /// The current access token.
    let accessToken: String

    /// The refresh token, if one was issued.
    let refreshToken: String?

    /// The absolute time at which the access token expires.
    let expiresAt: Date

    /// Whether the access token is expired, allowing a `leeway` window.
    ///
    /// - Parameter leeway: Seconds before the true expiry to treat the token as
    ///   expired. Defaults to 60s so refresh happens before the token lapses.
    /// - Returns: `true` if the token is expired (or within `leeway` of expiry).
    func isExpired(leeway: TimeInterval = 60) -> Bool {
        Date().addingTimeInterval(leeway) >= expiresAt
    }
}

// MARK: - OAuth Errors

/// Errors that can occur during the OAuth flow.
enum OAuthError: LocalizedError {
    /// The client ID placeholder has not been replaced.
    case missingClientID

    /// Discovery of the authorization-server metadata failed.
    case discoveryFailed

    /// The user cancelled the sign-in web session.
    case userCancelled

    /// The local loopback callback listener could not start (e.g. port in use).
    case callbackServerFailed(String)

    /// The redirect callback was missing or malformed (bad code/state).
    case invalidCallback

    /// The authorization-code exchange failed with a server message.
    case tokenExchangeFailed(String)

    /// Refreshing the access token failed.
    case refreshFailed

    /// A refresh was required but no refresh token is stored.
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "OAuth is not configured. The app's OAuth client ID has not been set."
        case .discoveryFailed:
            return "Could not reach Cloudflare's OAuth service. Please try again."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .callbackServerFailed(let message):
            return "Could not start the local sign-in listener: \(message)"
        case .invalidCallback:
            return "The sign-in response was invalid. Please try again."
        case .tokenExchangeFailed(let message):
            return "Failed to complete sign-in: \(message)"
        case .refreshFailed:
            return "Your session could not be refreshed. Please sign in again."
        case .noRefreshToken:
            return "Your session has expired. Please sign in again."
        }
    }
}
