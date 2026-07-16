//
//  PKCE.swift
//  Tunnelflare
//
//  Created on 2026-07-15.
//  Copyright 2026. All rights reserved.
//

import CryptoKit
import Foundation
import Security

/// Proof Key for Code Exchange (PKCE) helpers per RFC 7636.
///
/// Used by the OAuth authorization-code flow to protect against authorization
/// code interception. The public client generates a random `code_verifier`,
/// derives an S256 `code_challenge` from it, and sends the challenge with the
/// authorization request. The verifier is later presented at token exchange.
enum PKCE {

    /// Generates a cryptographically random code verifier.
    ///
    /// The verifier is 32 random bytes base64url-encoded (no padding), yielding
    /// a 43-character string of RFC 7636 unreserved characters, within the
    /// allowed 43–128 range.
    ///
    /// - Returns: A URL-safe code verifier string.
    static func generateVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        if status != errSecSuccess {
            // Fall back to the system RNG if SecRandomCopyBytes is unavailable.
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices {
                bytes[index] = UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
            }
        }

        return Data(bytes).base64URLEncodedString()
    }

    /// Derives the S256 code challenge for a given verifier.
    ///
    /// Computes `BASE64URL(SHA256(verifier))` with no padding.
    ///
    /// - Parameter verifier: The code verifier produced by ``generateVerifier()``.
    /// - Returns: The base64url-encoded SHA-256 challenge.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

// MARK: - Base64URL Encoding

extension Data {
    /// Returns a base64url-encoded string (RFC 4648 §5) without padding.
    ///
    /// Replaces `+`/`/` with `-`/`_` and strips trailing `=` padding.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
