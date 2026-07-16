//
//  KeychainManager.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import Security
import os.log

/// An actor-based secure wrapper for macOS Keychain operations.
///
/// `KeychainManager` provides thread-safe access to the macOS Keychain for storing,
/// retrieving, and deleting sensitive data such as API tokens and tunnel credentials.
///
/// ## Security
/// - All items are stored with `kSecAttrAccessibleAfterFirstUnlock` protection level
/// - Items are isolated to the app's Keychain service identifier
/// - The actor model ensures thread-safe operations
///
/// ## Usage
/// ```swift
/// let keychain = KeychainManager.shared
///
/// // Save API token
/// try await keychain.saveAPIToken("your-api-token")
///
/// // Retrieve API token
/// if let token = try await keychain.retrieveAPIToken() {
///     // Use token
/// }
///
/// // Delete API token
/// try await keychain.deleteAPIToken()
/// ```
actor KeychainManager {

    // MARK: - Singleton

    /// Shared instance of the KeychainManager.
    static let shared = KeychainManager()

    // MARK: - Properties

    /// The service identifier for Keychain items.
    private let service: String

    /// Logger for Keychain operations.
    private let logger = Logger.keychain

    // MARK: - Initialization

    /// Creates a new KeychainManager with the default service identifier.
    init() {
        self.service = KeychainConstants.service
    }

    /// Creates a new KeychainManager with a custom service identifier.
    /// - Parameter service: The service identifier for Keychain items.
    init(service: String) {
        self.service = service
    }

    // MARK: - Public Methods

    /// Saves data to the Keychain.
    ///
    /// If an item with the same key already exists, it will be overwritten.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The key to associate with the data.
    /// - Throws: `KeychainError` if the save operation fails.
    func save(_ data: Data, for key: String) throws {
        logger.debug("Saving item for key: \(key)")

        // First, try to delete any existing item
        let deleteQuery = baseQuery(for: key)
        SecItemDelete(deleteQuery as CFDictionary)

        // Prepare the new item
        var query = baseQuery(for: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        // Add the item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            let error = KeychainError.saveFailed(status)
            logger.error("Failed to save item for key \(key): \(error.localizedDescription)")
            throw error
        }

        logger.info("Successfully saved item for key: \(key)")
    }

    /// Saves a string value to the Keychain.
    ///
    /// - Parameters:
    ///   - value: The string value to store.
    ///   - key: The key to associate with the value.
    /// - Throws: `KeychainError` if the save operation fails.
    func save(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        try save(data, for: key)
    }

    /// Retrieves data from the Keychain.
    ///
    /// - Parameter key: The key associated with the data.
    /// - Returns: The data if found, or `nil` if the item doesn't exist.
    /// - Throws: `KeychainError` if the retrieve operation fails for reasons other than item not found.
    func retrieve(for key: String) throws -> Data? {
        logger.debug("Retrieving item for key: \(key)")

        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                logger.error("Retrieved item is not Data type for key: \(key)")
                throw KeychainError.invalidData
            }
            logger.debug("Successfully retrieved item for key: \(key)")
            return data

        case errSecItemNotFound:
            logger.debug("Item not found for key: \(key)")
            return nil

        default:
            let error = KeychainError.retrieveFailed(status)
            logger.error("Failed to retrieve item for key \(key): \(error.localizedDescription)")
            throw error
        }
    }

    /// Retrieves a string value from the Keychain.
    ///
    /// - Parameter key: The key associated with the value.
    /// - Returns: The string value if found, or `nil` if the item doesn't exist.
    /// - Throws: `KeychainError` if the retrieve operation fails.
    func retrieveString(for key: String) throws -> String? {
        guard let data = try retrieve(for: key) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    /// Deletes an item from the Keychain.
    ///
    /// - Parameter key: The key of the item to delete.
    /// - Throws: `KeychainError` if the delete operation fails for reasons other than item not found.
    func delete(for key: String) throws {
        logger.debug("Deleting item for key: \(key)")

        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            let error = KeychainError.deleteFailed(status)
            logger.error("Failed to delete item for key \(key): \(error.localizedDescription)")
            throw error
        }

        logger.info("Successfully deleted item for key: \(key)")
    }

    /// Deletes all items associated with this app from the Keychain.
    ///
    /// This method is typically used during logout to clear all stored credentials.
    ///
    /// - Throws: `KeychainError` if the delete operation fails.
    func deleteAll() throws {
        let serviceName = self.service
        logger.debug("Deleting all items for service: \(serviceName)")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        // errSecItemNotFound is acceptable - means nothing to delete
        guard status == errSecSuccess || status == errSecItemNotFound else {
            let error = KeychainError.deleteFailed(status)
            logger.error("Failed to delete all items: \(error.localizedDescription)")
            throw error
        }

        logger.info("Successfully deleted all items for service: \(serviceName)")
    }

    /// Checks if an item exists in the Keychain.
    ///
    /// - Parameter key: The key to check.
    /// - Returns: `true` if the item exists, `false` otherwise.
    func exists(for key: String) -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanFalse

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Updates an existing item in the Keychain.
    ///
    /// - Parameters:
    ///   - data: The new data to store.
    ///   - key: The key of the item to update.
    /// - Throws: `KeychainError` if the update operation fails.
    func update(_ data: Data, for key: String) throws {
        logger.debug("Updating item for key: \(key)")

        let query = baseQuery(for: key)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        switch status {
        case errSecSuccess:
            logger.info("Successfully updated item for key: \(key)")

        case errSecItemNotFound:
            // Item doesn't exist, create it
            try save(data, for: key)

        default:
            let error = KeychainError.updateFailed(status)
            logger.error("Failed to update item for key \(key): \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Methods

    /// Creates the base query dictionary for Keychain operations.
    ///
    /// - Parameter key: The key for the Keychain item.
    /// - Returns: A dictionary containing the base query parameters.
    private func baseQuery(for key: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

// MARK: - KeychainError

/// Errors that can occur during Keychain operations.
enum KeychainError: LocalizedError {
    /// Failed to save an item to the Keychain.
    case saveFailed(OSStatus)

    /// Failed to retrieve an item from the Keychain.
    case retrieveFailed(OSStatus)

    /// Failed to delete an item from the Keychain.
    case deleteFailed(OSStatus)

    /// Failed to update an item in the Keychain.
    case updateFailed(OSStatus)

    /// The data is invalid or cannot be converted.
    case invalidData

    /// A human-readable description of the error.
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save item to Keychain (status: \(status)): \(securityErrorMessage(for: status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve item from Keychain (status: \(status)): \(securityErrorMessage(for: status))"
        case .deleteFailed(let status):
            return "Failed to delete item from Keychain (status: \(status)): \(securityErrorMessage(for: status))"
        case .updateFailed(let status):
            return "Failed to update item in Keychain (status: \(status)): \(securityErrorMessage(for: status))"
        case .invalidData:
            return "Invalid data format for Keychain operation"
        }
    }

    /// Converts an OSStatus to a human-readable message.
    private func securityErrorMessage(for status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "Success"
        case errSecItemNotFound:
            return "Item not found"
        case errSecDuplicateItem:
            return "Duplicate item"
        case errSecAuthFailed:
            return "Authentication failed"
        case errSecUserCanceled:
            return "User canceled"
        case errSecParam:
            return "Invalid parameter"
        case errSecAllocate:
            return "Memory allocation failed"
        case errSecInteractionNotAllowed:
            return "Interaction not allowed (device locked)"
        case errSecDecode:
            return "Unable to decode data"
        case errSecMissingEntitlement:
            return "Missing entitlement"
        default:
            if let message = SecCopyErrorMessageString(status, nil) {
                return message as String
            }
            return "Unknown error"
        }
    }
}

// MARK: - API Token Convenience Methods

extension KeychainManager {
    /// Saves the Cloudflare API token to the Keychain.
    ///
    /// - Parameter token: The API token to store.
    func saveAPIToken(_ token: String) throws {
        try save(token, for: KeychainConstants.apiTokenKey)
    }

    /// Retrieves the Cloudflare API token from the Keychain.
    ///
    /// - Returns: The API token if found, or `nil` if not stored.
    func retrieveAPIToken() throws -> String? {
        try retrieveString(for: KeychainConstants.apiTokenKey)
    }

    /// Deletes the Cloudflare API token from the Keychain.
    func deleteAPIToken() throws {
        try delete(for: KeychainConstants.apiTokenKey)
    }
}

// MARK: - OAuth Convenience Methods

extension KeychainManager {
    /// Saves the OAuth tokens (access/refresh/expiry) to the Keychain.
    ///
    /// - Parameter tokens: The OAuth tokens to persist.
    func saveOAuthTokens(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try save(data, for: KeychainConstants.oauthTokensKey)
    }

    /// Retrieves the persisted OAuth tokens from the Keychain.
    ///
    /// - Returns: The stored ``OAuthTokens``, or `nil` if none are stored.
    func retrieveOAuthTokens() throws -> OAuthTokens? {
        guard let data = try retrieve(for: KeychainConstants.oauthTokensKey) else {
            return nil
        }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    /// Deletes the persisted OAuth tokens from the Keychain.
    func deleteOAuthTokens() throws {
        try delete(for: KeychainConstants.oauthTokensKey)
    }

    /// Persists which authentication method the current session used.
    ///
    /// - Parameter method: The authentication method to store.
    func saveAuthMethod(_ method: AuthenticationManager.AuthMethod) throws {
        try save(method.rawValue, for: KeychainConstants.authMethodKey)
    }

    /// Retrieves the persisted authentication method.
    ///
    /// - Returns: The stored method, or `nil` if none is stored/recognized.
    func retrieveAuthMethod() throws -> AuthenticationManager.AuthMethod? {
        guard let raw = try retrieveString(for: KeychainConstants.authMethodKey) else {
            return nil
        }
        return AuthenticationManager.AuthMethod(rawValue: raw)
    }
}

// MARK: - Tunnel Token Convenience Methods

extension KeychainManager {
    /// Saves a tunnel token to the Keychain.
    ///
    /// - Parameters:
    ///   - token: The tunnel token to store.
    ///   - tunnelId: The ID of the tunnel.
    func saveTunnelToken(_ token: String, for tunnelId: String) throws {
        let key = KeychainConstants.tunnelTokenKey(for: tunnelId)
        try save(token, for: key)
    }

    /// Retrieves a tunnel token from the Keychain.
    ///
    /// - Parameter tunnelId: The ID of the tunnel.
    /// - Returns: The tunnel token if found, or `nil` if not stored.
    func retrieveTunnelToken(for tunnelId: String) throws -> String? {
        let key = KeychainConstants.tunnelTokenKey(for: tunnelId)
        return try retrieveString(for: key)
    }

    /// Deletes a tunnel token from the Keychain.
    ///
    /// - Parameter tunnelId: The ID of the tunnel.
    func deleteTunnelToken(for tunnelId: String) throws {
        let key = KeychainConstants.tunnelTokenKey(for: tunnelId)
        try delete(for: key)
    }
}
