//
//  TunnelNameValidatorTests.swift
//  TunnelflareTests
//
//  Created on 2026-01-11.
//  Tests for TunnelNameValidator.
//

import XCTest
@testable import Tunnelflare

final class TunnelNameValidatorTests: XCTestCase {

    // MARK: - Valid Names Tests

    func testValidNames() {
        let validNames = [
            "abc",                      // Minimum length
            "my-tunnel",                // Simple with hyphen
            "my-tunnel-1",              // With number
            "tunnel123",                // Letters and numbers
            "1tunnel",                  // Starts with number
            "a1b2c3",                   // Alternating
            "my-dev-tunnel-2024",       // Complex valid name
            "a".padding(toLength: 63, withPad: "b", startingAt: 0), // Maximum length
        ]

        for name in validNames {
            let result = TunnelNameValidator.validate(name)
            XCTAssertTrue(result.isValid, "Expected '\(name)' to be valid, but got: \(result.errorMessage ?? "unknown error")")
            XCTAssertNil(result.errorMessage)
        }
    }

    // MARK: - Empty Name Tests

    func testEmptyName() {
        let result = TunnelNameValidator.validate("")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name cannot be empty")
    }

    func testWhitespaceOnlyName() {
        let result = TunnelNameValidator.validate("   ")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name cannot be empty")
    }

    func testWhitespaceWithTabs() {
        let result = TunnelNameValidator.validate(" \t \n ")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name cannot be empty")
    }

    // MARK: - Length Tests

    func testNameTooShort() {
        let shortNames = ["a", "ab"]
        for name in shortNames {
            let result = TunnelNameValidator.validate(name)
            XCTAssertFalse(result.isValid)
            XCTAssertEqual(result.errorMessage, "Tunnel name must be at least 3 characters")
        }
    }

    func testNameExactlyMinimumLength() {
        let result = TunnelNameValidator.validate("abc")
        XCTAssertTrue(result.isValid)
    }

    func testNameTooLong() {
        let longName = String(repeating: "a", count: 64)
        let result = TunnelNameValidator.validate(longName)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name cannot exceed 63 characters")
    }

    func testNameExactlyMaximumLength() {
        let maxName = String(repeating: "a", count: 63)
        let result = TunnelNameValidator.validate(maxName)
        XCTAssertTrue(result.isValid)
    }

    func testNameWayTooLong() {
        let veryLongName = String(repeating: "a", count: 1000)
        let result = TunnelNameValidator.validate(veryLongName)
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name cannot exceed 63 characters")
    }

    // MARK: - Character Set Tests

    func testUppercaseCharacters() {
        let uppercaseNames = ["MyTunnel", "TUNNEL", "My-Tunnel"]
        for name in uppercaseNames {
            let result = TunnelNameValidator.validate(name)
            XCTAssertFalse(result.isValid)
            XCTAssertEqual(result.errorMessage, "Tunnel name can only contain lowercase letters, numbers, and hyphens")
        }
    }

    func testUnderscores() {
        let result = TunnelNameValidator.validate("my_tunnel")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name can only contain lowercase letters, numbers, and hyphens")
    }

    func testSpaces() {
        let result = TunnelNameValidator.validate("my tunnel")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name can only contain lowercase letters, numbers, and hyphens")
    }

    func testSpecialCharacters() {
        let specialNames = [
            "my.tunnel",
            "my@tunnel",
            "my#tunnel",
            "my$tunnel",
            "my%tunnel",
            "my&tunnel",
            "my*tunnel",
            "my!tunnel",
            "my+tunnel",
            "my=tunnel",
            "my/tunnel",
            "my\\tunnel",
        ]
        for name in specialNames {
            let result = TunnelNameValidator.validate(name)
            XCTAssertFalse(result.isValid, "Expected '\(name)' to be invalid")
            XCTAssertEqual(result.errorMessage, "Tunnel name can only contain lowercase letters, numbers, and hyphens")
        }
    }

    func testUnicodeCharacters() {
        let unicodeNames = [
            "my-tunnel-\u{00E9}",   // e with accent
            "my-tunnel-\u{00F1}",   // n with tilde
            "my-tunnel-\u{4E2D}",   // Chinese character
            "\u{1F680}-tunnel",     // Emoji
        ]
        for name in unicodeNames {
            let result = TunnelNameValidator.validate(name)
            XCTAssertFalse(result.isValid, "Expected '\(name)' to be invalid")
        }
    }

    // MARK: - Start/End Character Tests

    func testStartsWithHyphen() {
        let result = TunnelNameValidator.validate("-my-tunnel")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name must start with a letter or number")
    }

    func testEndsWithHyphen() {
        let result = TunnelNameValidator.validate("my-tunnel-")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name must end with a letter or number")
    }

    func testStartsAndEndsWithHyphen() {
        let result = TunnelNameValidator.validate("-my-tunnel-")
        XCTAssertFalse(result.isValid)
        // Should catch the first error (starts with hyphen)
        XCTAssertEqual(result.errorMessage, "Tunnel name must start with a letter or number")
    }

    func testStartsWithNumber() {
        let result = TunnelNameValidator.validate("123-tunnel")
        XCTAssertTrue(result.isValid)
    }

    func testEndsWithNumber() {
        let result = TunnelNameValidator.validate("tunnel-123")
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Consecutive Hyphens Tests

    func testConsecutiveHyphens() {
        let result = TunnelNameValidator.validate("my--tunnel")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name cannot contain consecutive hyphens")
    }

    func testMultipleConsecutiveHyphens() {
        let result = TunnelNameValidator.validate("my---tunnel")
        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errorMessage, "Tunnel name cannot contain consecutive hyphens")
    }

    func testConsecutiveHyphensAtStart() {
        let result = TunnelNameValidator.validate("--mytunnel")
        XCTAssertFalse(result.isValid)
        // Should catch "must start with letter or number" first
        XCTAssertEqual(result.errorMessage, "Tunnel name must start with a letter or number")
    }

    func testConsecutiveHyphensAtEnd() {
        let result = TunnelNameValidator.validate("mytunnel--")
        XCTAssertFalse(result.isValid)
        // Should catch "must end with letter or number" first
        XCTAssertEqual(result.errorMessage, "Tunnel name must end with a letter or number")
    }

    func testMultipleHyphensNonConsecutive() {
        let result = TunnelNameValidator.validate("my-dev-test-tunnel")
        XCTAssertTrue(result.isValid)
    }

    // MARK: - Whitespace Handling Tests

    func testLeadingWhitespace() {
        let result = TunnelNameValidator.validate("  my-tunnel")
        XCTAssertTrue(result.isValid)
    }

    func testTrailingWhitespace() {
        let result = TunnelNameValidator.validate("my-tunnel  ")
        XCTAssertTrue(result.isValid)
    }

    func testLeadingAndTrailingWhitespace() {
        let result = TunnelNameValidator.validate("  my-tunnel  ")
        XCTAssertTrue(result.isValid)
    }

    // MARK: - isValid Method Tests

    func testIsValidMethod() {
        XCTAssertTrue(TunnelNameValidator.isValid("my-tunnel"))
        XCTAssertFalse(TunnelNameValidator.isValid(""))
        XCTAssertFalse(TunnelNameValidator.isValid("My-Tunnel"))
        XCTAssertFalse(TunnelNameValidator.isValid("-tunnel"))
    }

    // MARK: - Result Properties Tests

    func testResultIsValid_True() {
        let result = TunnelNameValidator.validate("my-tunnel")
        XCTAssertTrue(result.isValid)
        XCTAssertNil(result.errorMessage)
    }

    func testResultIsValid_False() {
        let result = TunnelNameValidator.validate("")
        XCTAssertFalse(result.isValid)
        XCTAssertNotNil(result.errorMessage)
    }

    func testResultEquality() {
        let valid1 = TunnelNameValidator.Result.valid
        let valid2 = TunnelNameValidator.Result.valid
        let invalid1 = TunnelNameValidator.Result.invalid("Error 1")
        let invalid2 = TunnelNameValidator.Result.invalid("Error 1")
        let invalid3 = TunnelNameValidator.Result.invalid("Error 2")

        XCTAssertEqual(valid1, valid2)
        XCTAssertEqual(invalid1, invalid2)
        XCTAssertNotEqual(valid1, invalid1)
        XCTAssertNotEqual(invalid1, invalid3)
    }

    // MARK: - Sanitize Method Tests

    func testSanitize_Lowercase() {
        let sanitized = TunnelNameValidator.sanitize("MyTunnel")
        XCTAssertEqual(sanitized, "mytunnel")
    }

    func testSanitize_Whitespace() {
        let sanitized = TunnelNameValidator.sanitize("  my tunnel  ")
        XCTAssertEqual(sanitized, "my-tunnel")
    }

    func testSanitize_Underscores() {
        let sanitized = TunnelNameValidator.sanitize("my_tunnel_name")
        XCTAssertEqual(sanitized, "my-tunnel-name")
    }

    func testSanitize_SpecialCharacters() {
        let sanitized = TunnelNameValidator.sanitize("my@tunnel#name!")
        XCTAssertEqual(sanitized, "mytunnelname")
    }

    func testSanitize_ConsecutiveHyphens() {
        let sanitized = TunnelNameValidator.sanitize("my--tunnel--name")
        XCTAssertEqual(sanitized, "my-tunnel-name")
    }

    func testSanitize_LeadingTrailingHyphens() {
        let sanitized = TunnelNameValidator.sanitize("-my-tunnel-")
        XCTAssertEqual(sanitized, "my-tunnel")
    }

    func testSanitize_TooLong() {
        let longName = String(repeating: "a", count: 100)
        let sanitized = TunnelNameValidator.sanitize(longName)
        XCTAssertEqual(sanitized.count, 63)
    }

    func testSanitize_ComplexCase() {
        let sanitized = TunnelNameValidator.sanitize("  My_Cool--Tunnel__Name!! ")
        XCTAssertEqual(sanitized, "my-cool-tunnel-name")
    }

    func testSanitize_ResultMayStillBeInvalid() {
        // Sanitizing a too-short name may still result in an invalid name
        let sanitized = TunnelNameValidator.sanitize("a")
        XCTAssertFalse(TunnelNameValidator.isValid(sanitized))
    }

    // MARK: - String Extension Tests

    func testStringExtension_TunnelNameValidation() {
        let valid = "my-tunnel"
        let invalid = "My_Tunnel"

        XCTAssertTrue(valid.tunnelNameValidation.isValid)
        XCTAssertFalse(invalid.tunnelNameValidation.isValid)
    }

    func testStringExtension_IsValidTunnelName() {
        XCTAssertTrue("my-tunnel".isValidTunnelName)
        XCTAssertFalse("My_Tunnel".isValidTunnelName)
    }

    func testStringExtension_SanitizedTunnelName() {
        XCTAssertEqual("My_Tunnel".sanitizedTunnelName, "my-tunnel")
        XCTAssertEqual("  test  ".sanitizedTunnelName, "test")
    }

    // MARK: - Edge Cases

    func testOnlyHyphens() {
        let result = TunnelNameValidator.validate("---")
        XCTAssertFalse(result.isValid)
    }

    func testOnlyNumbers() {
        let result = TunnelNameValidator.validate("123")
        XCTAssertTrue(result.isValid)
    }

    func testOnlyLetters() {
        let result = TunnelNameValidator.validate("abc")
        XCTAssertTrue(result.isValid)
    }

    func testHyphenInMiddle() {
        let result = TunnelNameValidator.validate("a-b")
        XCTAssertTrue(result.isValid)
    }

    func testSingleHyphenBetweenChars() {
        let result = TunnelNameValidator.validate("a-1")
        XCTAssertTrue(result.isValid)
    }
}
