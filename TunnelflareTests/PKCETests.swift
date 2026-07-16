//
//  PKCETests.swift
//  TunnelflareTests
//
//  Created on 2026-07-15.
//  Tests for OAuth PKCE helpers.
//

import CryptoKit
import XCTest
@testable import Tunnelflare

final class PKCETests: XCTestCase {

    func testGenerateVerifier_UsesValidLengthAndCharacters() {
        let verifier = PKCE.generateVerifier()
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        XCTAssertNil(verifier.rangeOfCharacter(from: allowedCharacters.inverted))
    }

    func testChallenge_MatchesRFC7636Example() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        let challenge = PKCE.challenge(for: verifier)

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testChallenge_IsDeterministic() {
        let verifier = PKCE.generateVerifier()

        XCTAssertEqual(PKCE.challenge(for: verifier), PKCE.challenge(for: verifier))
    }

    func testBase64URL_UsesURLSafeAlphabetWithoutPadding() {
        let data = Data([0xfb, 0xff, 0xff])

        let encoded = data.base64URLEncodedString()

        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(encoded, "-___")
    }
}
