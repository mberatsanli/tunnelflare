//
//  KeychainManagerTests.swift
//  TunnelflareTests
//
//  Created on 2026-01-11.
//  Tests for KeychainManager.
//

import XCTest
@testable import Tunnelflare

final class KeychainManagerTests: XCTestCase {

    // MARK: - Properties

    /// Use a unique service identifier for tests to avoid conflicts
    private var keychainManager: KeychainManager!

    // MARK: - Setup and Teardown

    override func setUp() async throws {
        try await super.setUp()
        // Create a keychain manager with a test-specific service to isolate tests
        keychainManager = KeychainManager(service: TestConstants.testKeychainService)
        // Clean up any leftover data from previous test runs
        try await keychainManager.deleteAll()
    }

    override func tearDown() async throws {
        // Clean up all test data after each test
        try await keychainManager.deleteAll()
        keychainManager = nil
        try await super.tearDown()
    }

    // MARK: - Save Tests

    func testSaveData_Success() async throws {
        let testData = "test-value".data(using: .utf8)!
        let key = "test-key"

        // Should not throw
        try await keychainManager.save(testData, for: key)

        // Verify it was saved
        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertEqual(retrieved, testData)
    }

    func testSaveString_Success() async throws {
        let testValue = "test-string-value"
        let key = "test-string-key"

        try await keychainManager.save(testValue, for: key)

        let retrieved = try await keychainManager.retrieveString(for: key)
        XCTAssertEqual(retrieved, testValue)
    }

    func testSave_OverwritesExistingValue() async throws {
        let key = "overwrite-test-key"
        let originalValue = "original-value".data(using: .utf8)!
        let newValue = "new-value".data(using: .utf8)!

        // Save original
        try await keychainManager.save(originalValue, for: key)

        // Overwrite with new value
        try await keychainManager.save(newValue, for: key)

        // Should get the new value
        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertEqual(retrieved, newValue)
    }

    func testSave_EmptyData() async throws {
        let key = "empty-data-key"
        let emptyData = Data()

        try await keychainManager.save(emptyData, for: key)

        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertEqual(retrieved, emptyData)
    }

    func testSave_LargeData() async throws {
        let key = "large-data-key"
        // Create 1MB of data
        let largeData = Data(repeating: 0x42, count: 1024 * 1024)

        try await keychainManager.save(largeData, for: key)

        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertEqual(retrieved, largeData)
    }

    func testSave_SpecialCharactersInKey() async throws {
        let key = "test.key/with-special_chars:123"
        let value = "test-value".data(using: .utf8)!

        try await keychainManager.save(value, for: key)

        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertEqual(retrieved, value)
    }

    // MARK: - Retrieve Tests

    func testRetrieve_NonExistentKey() async throws {
        let key = "non-existent-key"

        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertNil(retrieved)
    }

    func testRetrieveString_NonExistentKey() async throws {
        let key = "non-existent-string-key"

        let retrieved = try await keychainManager.retrieveString(for: key)
        XCTAssertNil(retrieved)
    }

    func testRetrieve_AfterSave() async throws {
        let key = "retrieve-test-key"
        let value = "retrieve-test-value".data(using: .utf8)!

        try await keychainManager.save(value, for: key)
        let retrieved = try await keychainManager.retrieve(for: key)

        XCTAssertEqual(retrieved, value)
    }

    func testRetrieveString_AfterSaveString() async throws {
        let key = "retrieve-string-test-key"
        let value = "retrieve-string-test-value"

        try await keychainManager.save(value, for: key)
        let retrieved = try await keychainManager.retrieveString(for: key)

        XCTAssertEqual(retrieved, value)
    }

    // MARK: - Delete Tests

    func testDelete_ExistingKey() async throws {
        let key = "delete-test-key"
        let value = "delete-test-value".data(using: .utf8)!

        // Save first
        try await keychainManager.save(value, for: key)

        // Delete
        try await keychainManager.delete(for: key)

        // Should be nil now
        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertNil(retrieved)
    }

    func testDelete_NonExistentKey() async throws {
        // Should not throw for non-existent key
        try await keychainManager.delete(for: "definitely-does-not-exist")
    }

    func testDeleteAll_ClearsAllItems() async throws {
        let items = [
            ("key1", "value1"),
            ("key2", "value2"),
            ("key3", "value3")
        ]

        // Save multiple items
        for (key, value) in items {
            try await keychainManager.save(value, for: key)
        }

        // Verify they exist
        for (key, _) in items {
            let exists = await keychainManager.exists(for: key)
            XCTAssertTrue(exists)
        }

        // Delete all
        try await keychainManager.deleteAll()

        // Verify all are gone
        for (key, _) in items {
            let exists = await keychainManager.exists(for: key)
            XCTAssertFalse(exists)
        }
    }

    func testDeleteAll_EmptyKeychain() async throws {
        // Should not throw when keychain is already empty
        try await keychainManager.deleteAll()
    }

    // MARK: - Exists Tests

    func testExists_ExistingKey() async throws {
        let key = "exists-test-key"
        let value = "exists-test-value".data(using: .utf8)!

        try await keychainManager.save(value, for: key)

        let exists = await keychainManager.exists(for: key)
        XCTAssertTrue(exists)
    }

    func testExists_NonExistentKey() async throws {
        let exists = await keychainManager.exists(for: "non-existent-key")
        XCTAssertFalse(exists)
    }

    func testExists_AfterDelete() async throws {
        let key = "exists-after-delete-key"
        let value = "test".data(using: .utf8)!

        try await keychainManager.save(value, for: key)
        var exists = await keychainManager.exists(for: key)
        XCTAssertTrue(exists)

        try await keychainManager.delete(for: key)
        exists = await keychainManager.exists(for: key)
        XCTAssertFalse(exists)
    }

    // MARK: - Update Tests

    func testUpdate_ExistingKey() async throws {
        let key = "update-test-key"
        let originalValue = "original".data(using: .utf8)!
        let updatedValue = "updated".data(using: .utf8)!

        // Save original
        try await keychainManager.save(originalValue, for: key)

        // Update
        try await keychainManager.update(updatedValue, for: key)

        // Should have updated value
        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertEqual(retrieved, updatedValue)
    }

    func testUpdate_NonExistentKey_CreatesNew() async throws {
        let key = "update-new-key"
        let value = "new-value".data(using: .utf8)!

        // Update should create if not exists
        try await keychainManager.update(value, for: key)

        let retrieved = try await keychainManager.retrieve(for: key)
        XCTAssertEqual(retrieved, value)
    }

    // MARK: - API Token Convenience Methods Tests

    func testSaveAPIToken() async throws {
        let token = "cf-api-token-12345"
        try await keychainManager.saveAPIToken(token)
        let retrieved = try await keychainManager.retrieveAPIToken()
        XCTAssertEqual(retrieved, token)
    }

    func testRetrieveAPIToken_NotSet() async throws {
        let retrieved = try await keychainManager.retrieveAPIToken()
        XCTAssertNil(retrieved)
    }

    func testDeleteAPIToken() async throws {
        let token = "cf-api-token-67890"
        try await keychainManager.saveAPIToken(token)

        let beforeDelete = try await keychainManager.retrieveAPIToken()
        XCTAssertNotNil(beforeDelete)

        try await keychainManager.deleteAPIToken()

        let afterDelete = try await keychainManager.retrieveAPIToken()
        XCTAssertNil(afterDelete)
    }

    func testSaveAPIToken_OverwritesExisting() async throws {
        let originalToken = "original-api-token"
        let newToken = "new-api-token"
        try await keychainManager.saveAPIToken(originalToken)
        try await keychainManager.saveAPIToken(newToken)
        let retrieved = try await keychainManager.retrieveAPIToken()
        XCTAssertEqual(retrieved, newToken)
    }

    // MARK: - Tunnel Token Convenience Methods Tests

    func testSaveTunnelToken() async throws {
        let tunnelId = "tunnel-123"
        let token = "tunnel-token-abc"

        try await keychainManager.saveTunnelToken(token, for: tunnelId)

        let retrieved = try await keychainManager.retrieveTunnelToken(for: tunnelId)
        XCTAssertEqual(retrieved, token)
    }

    func testRetrieveTunnelToken_NotSet() async throws {
        let retrieved = try await keychainManager.retrieveTunnelToken(for: "non-existent-tunnel")
        XCTAssertNil(retrieved)
    }

    func testDeleteTunnelToken() async throws {
        let tunnelId = "tunnel-456"
        let token = "tunnel-token-def"

        try await keychainManager.saveTunnelToken(token, for: tunnelId)

        let beforeDelete = try await keychainManager.retrieveTunnelToken(for: tunnelId)
        XCTAssertNotNil(beforeDelete)

        try await keychainManager.deleteTunnelToken(for: tunnelId)

        let afterDelete = try await keychainManager.retrieveTunnelToken(for: tunnelId)
        XCTAssertNil(afterDelete)
    }

    func testMultipleTunnelTokens() async throws {
        let tokens = [
            ("tunnel-1", "token-1"),
            ("tunnel-2", "token-2"),
            ("tunnel-3", "token-3")
        ]

        // Save all tokens
        for (tunnelId, token) in tokens {
            try await keychainManager.saveTunnelToken(token, for: tunnelId)
        }

        // Retrieve and verify each
        for (tunnelId, expectedToken) in tokens {
            let retrieved = try await keychainManager.retrieveTunnelToken(for: tunnelId)
            XCTAssertEqual(retrieved, expectedToken)
        }
    }

    // MARK: - Test Isolation Tests

    func testDifferentServiceIsolation() async throws {
        let key = "isolation-test-key"
        let value1 = "value-from-service1".data(using: .utf8)!
        let value2 = "value-from-service2".data(using: .utf8)!

        let manager1 = KeychainManager(service: "com.test.service1")
        let manager2 = KeychainManager(service: "com.test.service2")

        // Save different values under same key with different services
        try await manager1.save(value1, for: key)
        try await manager2.save(value2, for: key)

        // Each should retrieve their own value
        let retrieved1 = try await manager1.retrieve(for: key)
        let retrieved2 = try await manager2.retrieve(for: key)

        XCTAssertEqual(retrieved1, value1)
        XCTAssertEqual(retrieved2, value2)

        // Cleanup
        try await manager1.deleteAll()
        try await manager2.deleteAll()
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentWrites() async throws {
        let key = "concurrent-key"

        // Perform many concurrent writes
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let value = "value-\(i)".data(using: .utf8)!
                    try? await self.keychainManager.save(value, for: key)
                }
            }
        }

        // Should have some value (doesn't matter which one won the race)
        let exists = await keychainManager.exists(for: key)
        XCTAssertTrue(exists)
    }

    func testConcurrentReads() async throws {
        let key = "concurrent-read-key"
        let value = "stable-value".data(using: .utf8)!

        try await keychainManager.save(value, for: key)

        // Perform many concurrent reads
        await withTaskGroup(of: Data?.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    try? await self.keychainManager.retrieve(for: key)
                }
            }

            for await result in group {
                XCTAssertEqual(result, value)
            }
        }
    }
}

// MARK: - KeychainError Tests

final class KeychainErrorTests: XCTestCase {

    func testErrorDescription_SaveFailed() {
        let error = KeychainError.saveFailed(errSecDuplicateItem)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Failed to save"))
    }

    func testErrorDescription_RetrieveFailed() {
        let error = KeychainError.retrieveFailed(errSecAuthFailed)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Failed to retrieve"))
    }

    func testErrorDescription_DeleteFailed() {
        let error = KeychainError.deleteFailed(errSecParam)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Failed to delete"))
    }

    func testErrorDescription_UpdateFailed() {
        let error = KeychainError.updateFailed(errSecAllocate)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Failed to update"))
    }

    func testErrorDescription_InvalidData() {
        let error = KeychainError.invalidData
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Invalid data"))
    }
}
