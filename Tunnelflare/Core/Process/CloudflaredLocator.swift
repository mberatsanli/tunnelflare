//
//  CloudflaredLocator.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - CloudflaredLocator

/// Locates the cloudflared binary on the system.
///
/// CloudflaredLocator searches for the cloudflared binary in the following order:
/// 1. Custom path (from settings)
/// 2. App bundle: `Bundle.main.resourceURL/cloudflared`
/// 3. Homebrew (Apple Silicon): `/opt/homebrew/bin/cloudflared`
/// 4. Homebrew (Intel): `/usr/local/bin/cloudflared`
///
/// ## Usage
/// ```swift
/// let locator = CloudflaredLocator()
///
/// if let path = locator.locateBinary() {
///     print("Found cloudflared at: \(path.path)")
/// }
/// ```
struct CloudflaredLocator {

    // MARK: - Properties

    /// Logger for binary location operations.
    private let logger = Logger.process

    /// Custom path from user settings.
    private let customPath: String?

    // MARK: - Initialization

    /// Creates a new CloudflaredLocator.
    ///
    /// - Parameter customPath: Optional custom path from user settings.
    init(customPath: String? = nil) {
        self.customPath = customPath
    }

    // MARK: - Public Methods

    /// Locates the cloudflared binary.
    ///
    /// Searches for the binary in the following order:
    /// 1. Custom path (from settings)
    /// 2. App bundle
    /// 3. Homebrew (Apple Silicon)
    /// 4. Homebrew (Intel)
    ///
    /// - Returns: The URL to the cloudflared binary, or nil if not found.
    func locateBinary() -> URL? {
        // 1. Check custom path first
        if let customPath = customPath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            if isExecutable(url) {
                logger.info("Found cloudflared at custom path: \(customPath)")
                return url
            }
            logger.warning("Custom cloudflared path not found or not executable: \(customPath)")
        }

        // 2. Check app bundle
        if let bundleURL = bundledBinaryURL(), isExecutable(bundleURL) {
            logger.info("Found cloudflared in app bundle: \(bundleURL.path)")
            return bundleURL
        }

        // 3. Check Homebrew (Apple Silicon)
        let homebrewARM = URL(fileURLWithPath: CloudflaredConstants.homebrewPathARM)
        if isExecutable(homebrewARM) {
            logger.info("Found cloudflared at Homebrew (ARM): \(homebrewARM.path)")
            return homebrewARM
        }

        // 4. Check Homebrew (Intel) / system path
        let homebrewIntel = URL(fileURLWithPath: CloudflaredConstants.homebrewPathIntel)
        if isExecutable(homebrewIntel) {
            logger.info("Found cloudflared at Homebrew (Intel): \(homebrewIntel.path)")
            return homebrewIntel
        }

        logger.error("cloudflared binary not found in any location")
        return nil
    }

    /// Gets the version of cloudflared at the specified path.
    ///
    /// - Parameter binaryURL: The URL to the cloudflared binary.
    /// - Returns: The version string, or nil if version could not be determined.
    func getVersion(at binaryURL: URL) async throws -> String {
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw CloudflaredError.versionCheckFailed
        }

        // Parse version from output
        // Format: "cloudflared version 2024.x.x (built ...)"
        return parseVersion(from: output)
    }

    /// Validates that the binary at the given path is a valid cloudflared executable.
    ///
    /// - Parameter url: The URL to validate.
    /// - Returns: A validation result with details.
    func validate(_ url: URL) async -> BinaryValidationResult {
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BinaryValidationResult(
                isValid: false,
                path: url,
                version: nil,
                error: .notFound
            )
        }

        // Check is executable
        guard isExecutable(url) else {
            return BinaryValidationResult(
                isValid: false,
                path: url,
                version: nil,
                error: .notExecutable
            )
        }

        // Try to get version
        do {
            let version = try await getVersion(at: url)
            return BinaryValidationResult(
                isValid: true,
                path: url,
                version: version,
                error: nil
            )
        } catch {
            return BinaryValidationResult(
                isValid: false,
                path: url,
                version: nil,
                error: .versionCheckFailed
            )
        }
    }

    // MARK: - Private Methods

    /// Returns the URL to the bundled cloudflared binary.
    private func bundledBinaryURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(CloudflaredConstants.binaryName)
    }

    /// Checks if the file at the given URL is executable.
    private func isExecutable(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.isExecutableFile(atPath: url.path)
    }

    /// Parses the version string from cloudflared output.
    private func parseVersion(from output: String) -> String {
        // Format: "cloudflared version 2024.x.x (built ...)"
        let pattern = #"cloudflared version (\d+\.\d+\.\d+)"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(
               in: output,
               range: NSRange(output.startIndex..., in: output)
           ),
           let versionRange = Range(match.range(at: 1), in: output) {
            return String(output[versionRange])
        }

        // Fallback: return trimmed first line
        return output.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespaces) ?? output
    }
}

// MARK: - Binary Validation Result

/// Result of validating a cloudflared binary.
struct BinaryValidationResult {
    /// Whether the binary is valid.
    let isValid: Bool

    /// The path to the binary.
    let path: URL

    /// The version of cloudflared, if determined.
    let version: String?

    /// The validation error, if any.
    let error: BinaryValidationError?
}

/// Errors that can occur during binary validation.
enum BinaryValidationError: Error, LocalizedError {
    case notFound
    case notExecutable
    case versionCheckFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "cloudflared binary not found"
        case .notExecutable:
            return "cloudflared binary is not executable"
        case .versionCheckFailed:
            return "Failed to determine cloudflared version"
        }
    }
}

// MARK: - Cloudflared Errors

/// Errors related to cloudflared operations.
enum CloudflaredError: Error, LocalizedError {
    case binaryNotFound
    case versionCheckFailed
    case startFailed(String)
    case processTerminated(exitCode: Int32)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "cloudflared binary not found. Please install cloudflared or specify a custom path in Settings."
        case .versionCheckFailed:
            return "Failed to determine cloudflared version."
        case .startFailed(let reason):
            return "Failed to start cloudflared: \(reason)"
        case .processTerminated(let exitCode):
            return "cloudflared process terminated with exit code \(exitCode)"
        }
    }
}
