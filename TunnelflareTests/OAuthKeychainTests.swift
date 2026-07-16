//
//  OAuthKeychainTests.swift
//  TunnelflareTests
//
//  Created on 2026-07-15.
//  Tests for OAuth Keychain persistence.
//

import XCTest
@testable import Tunnelflare

final class OAuthKeychainTests: XCTestCase {

    private var keychainManager: KeychainManager!

    override func setUp() async throws {
        try await super.setUp()
        keychainManager = KeychainManager(service: "\(TestConstants.testKeychainService).oauth")
        try await keychainManager.deleteAll()
    }

    override func tearDown() async throws {
        try await keychainManager.deleteAll()
        keychainManager = nil
        try await super.tearDown()
    }

    func testSaveRetrieveDeleteOAuthTokens() async throws {
        let tokens = OAuthTokens(
            accessToken: "oauth-access-token",
            refreshToken: "oauth-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        try await keychainManager.saveOAuthTokens(tokens)
        let retrieved = try await keychainManager.retrieveOAuthTokens()

        XCTAssertEqual(retrieved?.accessToken, tokens.accessToken)
        XCTAssertEqual(retrieved?.refreshToken, tokens.refreshToken)
        XCTAssertEqual(retrieved?.expiresAt, tokens.expiresAt)

        try await keychainManager.deleteOAuthTokens()

        let deleted = try await keychainManager.retrieveOAuthTokens()
        XCTAssertNil(deleted)
    }

    func testSaveRetrieveAuthMethod() async throws {
        try await keychainManager.saveAuthMethod(.oauth)

        let retrieved = try await keychainManager.retrieveAuthMethod()

        XCTAssertEqual(retrieved, .oauth)
    }
}
