//
//  TestHelpers.swift
//  TunnelflareTests
//
//  Created on 2026-01-11.
//  Testing utilities and mock helpers.
//

import Foundation
import XCTest

// MARK: - Test Constants

/// Constants used in tests.
enum TestConstants {
    /// A test service identifier for Keychain tests.
    /// Uses a unique identifier to avoid conflicts with the app's Keychain.
    static let testKeychainService = "com.tunnelflare-ui.tests"

    /// A test account ID for API tests.
    static let testAccountId = "test-account-123"

    /// A test tunnel ID for API tests.
    static let testTunnelId = "test-tunnel-456"
}

// MARK: - JSON Decoder for Tests

extension JSONDecoder {
    /// Creates a JSONDecoder configured for Cloudflare API responses.
    /// Mirrors the production decoder configuration.
    static var testCloudflareAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Custom date decoding to handle ISO8601 with fractional seconds
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractional.date(from: dateString) {
                return date
            }

            // Fall back to standard ISO8601
            let standardFormatter = ISO8601DateFormatter()
            if let date = standardFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }

        return decoder
    }
}

// MARK: - XCTestCase Extensions

extension XCTestCase {
    /// Loads JSON data from a string for testing.
    /// - Parameter json: The JSON string.
    /// - Returns: The JSON data.
    func jsonData(_ json: String) -> Data {
        json.data(using: .utf8)!
    }

    /// Decodes a JSON string to a Decodable type using Cloudflare API decoder.
    /// - Parameters:
    ///   - type: The type to decode to.
    ///   - json: The JSON string.
    /// - Returns: The decoded object.
    func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = jsonData(json)
        return try JSONDecoder.testCloudflareAPI.decode(type, from: data)
    }

    /// Asserts that decoding fails with a specific error type.
    /// - Parameters:
    ///   - type: The type to attempt to decode.
    ///   - json: The JSON string.
    ///   - file: The file where the assertion is called.
    ///   - line: The line where the assertion is called.
    func assertDecodingFails<T: Decodable>(
        _ type: T.Type,
        from json: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let data = jsonData(json)
        XCTAssertThrowsError(
            try JSONDecoder.testCloudflareAPI.decode(type, from: data),
            "Expected decoding to fail",
            file: file,
            line: line
        )
    }
}

// MARK: - Async Test Helpers

extension XCTestCase {
    /// Waits for an async operation with a timeout.
    /// - Parameters:
    ///   - timeout: The timeout in seconds.
    ///   - operation: The async operation to run.
    func waitForAsync(
        timeout: TimeInterval = 5.0,
        file: StaticString = #file,
        line: UInt = #line,
        operation: @escaping () async throws -> Void
    ) {
        let expectation = expectation(description: "Async operation")

        Task {
            do {
                try await operation()
                expectation.fulfill()
            } catch {
                XCTFail("Async operation failed: \(error)", file: file, line: line)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: timeout)
    }
}
