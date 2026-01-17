//
//  TunnelNameValidator.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Tunnel Name Validator

/// Validates tunnel names according to Cloudflare naming rules.
///
/// Tunnel names must follow these rules:
/// - Cannot be empty (after trimming whitespace)
/// - Minimum 3 characters
/// - Maximum 63 characters
/// - Only lowercase letters (a-z), numbers (0-9), and hyphens (-)
/// - Must start with a lowercase letter or number
/// - Must end with a lowercase letter or number
///
/// ## Usage
/// ```swift
/// let result = TunnelNameValidator.validate("my-tunnel-1")
/// switch result {
/// case .valid:
///     print("Name is valid")
/// case .invalid(let error):
///     print("Invalid: \(error)")
/// }
/// ```
enum TunnelNameValidator {

    // MARK: - Constants

    /// Minimum allowed length for tunnel names.
    static let minLength = 3

    /// Maximum allowed length for tunnel names.
    static let maxLength = 63

    /// Regex pattern for valid tunnel names.
    /// Pattern: starts with alphanumeric, middle can be alphanumeric or hyphen, ends with alphanumeric.
    static let validPattern = "^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$|^[a-z0-9]{1,2}$"

    /// Regex for allowed characters only.
    static let allowedCharactersPattern = "^[a-z0-9-]+$"

    // MARK: - Validation Result

    /// The result of tunnel name validation.
    enum Result: Equatable {
        /// The name is valid.
        case valid

        /// The name is invalid with the specified error message.
        case invalid(String)

        /// Whether the result indicates a valid name.
        var isValid: Bool {
            if case .valid = self {
                return true
            }
            return false
        }

        /// The error message if invalid, nil if valid.
        var errorMessage: String? {
            if case .invalid(let message) = self {
                return message
            }
            return nil
        }
    }

    // MARK: - Validation Methods

    /// Validates a tunnel name according to Cloudflare naming rules.
    ///
    /// - Parameter name: The tunnel name to validate.
    /// - Returns: A validation result indicating whether the name is valid.
    static func validate(_ name: String) -> Result {
        // Trim whitespace
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for empty name
        if trimmedName.isEmpty {
            return .invalid("Tunnel name cannot be empty")
        }

        // Check minimum length
        if trimmedName.count < minLength {
            return .invalid("Tunnel name must be at least \(minLength) characters")
        }

        // Check maximum length
        if trimmedName.count > maxLength {
            return .invalid("Tunnel name cannot exceed \(maxLength) characters")
        }

        // Check for uppercase characters
        if trimmedName != trimmedName.lowercased() {
            return .invalid("Tunnel name can only contain lowercase letters, numbers, and hyphens")
        }

        // Check for allowed characters
        if !matches(trimmedName, pattern: allowedCharactersPattern) {
            return .invalid("Tunnel name can only contain lowercase letters, numbers, and hyphens")
        }

        // Check start character
        let firstChar = trimmedName.first!
        if !firstChar.isLetter && !firstChar.isNumber {
            return .invalid("Tunnel name must start with a letter or number")
        }

        // Check end character
        let lastChar = trimmedName.last!
        if !lastChar.isLetter && !lastChar.isNumber {
            return .invalid("Tunnel name must end with a letter or number")
        }

        // Check for consecutive hyphens
        if trimmedName.contains("--") {
            return .invalid("Tunnel name cannot contain consecutive hyphens")
        }

        return .valid
    }

    /// Validates a tunnel name and returns a Boolean indicating validity.
    ///
    /// - Parameter name: The tunnel name to validate.
    /// - Returns: `true` if the name is valid, `false` otherwise.
    static func isValid(_ name: String) -> Bool {
        validate(name).isValid
    }

    /// Sanitizes a tunnel name by applying common fixes.
    ///
    /// This method:
    /// - Trims whitespace
    /// - Converts to lowercase
    /// - Replaces spaces with hyphens
    /// - Removes invalid characters
    /// - Truncates to maximum length
    ///
    /// Note: The result may still be invalid (e.g., if too short).
    ///
    /// - Parameter name: The tunnel name to sanitize.
    /// - Returns: A sanitized version of the name.
    static func sanitize(_ name: String) -> String {
        var sanitized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "_", with: "-")

        // Remove invalid characters
        sanitized = sanitized.filter { char in
            char.isLetter || char.isNumber || char == "-"
        }

        // Remove consecutive hyphens
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        // Trim leading/trailing hyphens
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Truncate to max length
        if sanitized.count > maxLength {
            sanitized = String(sanitized.prefix(maxLength))
            // Ensure we don't end with a hyphen after truncation
            sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return sanitized
    }

    // MARK: - Private Helpers

    /// Checks if a string matches a regex pattern.
    private static func matches(_ string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, options: [], range: range) != nil
    }
}

// MARK: - String Extension

extension String {
    /// Validates this string as a tunnel name.
    var tunnelNameValidation: TunnelNameValidator.Result {
        TunnelNameValidator.validate(self)
    }

    /// Whether this string is a valid tunnel name.
    var isValidTunnelName: Bool {
        TunnelNameValidator.isValid(self)
    }

    /// A sanitized version of this string suitable for a tunnel name.
    var sanitizedTunnelName: String {
        TunnelNameValidator.sanitize(self)
    }
}
