//
//  IngressRuleValidator.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - IngressRuleValidator

/// Validates a set of ingress rules before saving to the Cloudflare API.
///
/// Checks for problems that would produce a broken or rejected tunnel
/// configuration:
/// - Duplicate hostname + path combinations
/// - Invalid or empty service URLs
/// - Missing catch-all rule at the end
///
/// ## Usage
/// ```swift
/// let issues = IngressRuleValidator.validate(rules)
/// guard issues.isEmpty else { /* show errors */ }
/// ```
enum IngressRuleValidator {

    // MARK: - Issue

    /// A validation issue found in a set of ingress rules.
    enum Issue: Equatable, Sendable {
        /// Two or more rules share the same hostname and path.
        case duplicateHostname(String)

        /// A rule has an invalid service URL.
        case invalidService(hostname: String, service: String)

        /// A rule has an invalid hostname.
        case invalidHostname(String)

        /// The last rule is not a catch-all rule.
        case missingCatchAll

        /// A human-readable description of the issue.
        var errorMessage: String {
            switch self {
            case .duplicateHostname(let hostname):
                return "Duplicate hostname: \(hostname)"
            case .invalidService(let hostname, let service):
                return "Invalid service \"\(service)\" for \(hostname)"
            case .invalidHostname(let hostname):
                return "Invalid hostname: \(hostname)"
            case .missingCatchAll:
                return "The last rule must be a catch-all (no hostname)"
            }
        }
    }

    // MARK: - Validation

    /// Validates a complete set of ingress rules (including the catch-all).
    ///
    /// - Parameter rules: The rules to validate, in evaluation order.
    /// - Returns: All issues found; empty if the rules are valid.
    static func validate(_ rules: [IngressRule]) -> [Issue] {
        var issues: [Issue] = []

        // The last rule must be a catch-all with no hostname
        if rules.last?.isCatchAll != true {
            issues.append(.missingCatchAll)
        }

        // Check each rule
        var seenKeys: Set<String> = []
        for rule in rules {
            if let hostname = rule.hostname {
                if !isValidHostname(hostname) {
                    issues.append(.invalidHostname(hostname))
                }

                // Duplicate detection by hostname + path (case-insensitive)
                let key = "\(hostname.lowercased())\(rule.path ?? "")"
                if seenKeys.contains(key) {
                    issues.append(.duplicateHostname(rule.displayHostname))
                } else {
                    seenKeys.insert(key)
                }
            }

            if !isValidService(rule.service) {
                issues.append(.invalidService(
                    hostname: rule.displayHostname,
                    service: rule.service
                ))
            }
        }

        return issues
    }

    /// Whether a service string is a valid ingress service.
    ///
    /// Accepts `http(s)://`, `tcp://`, `ssh://`, `rdp://` URLs with a host,
    /// `unix:` socket paths, and `http_status:NNN` responses.
    ///
    /// - Parameter service: The service string to check.
    /// - Returns: `true` if the service is valid.
    static func isValidService(_ service: String) -> Bool {
        let trimmed = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowercased = trimmed.lowercased()

        // http_status:NNN - status code must be a valid HTTP status
        if lowercased.hasPrefix("http_status:") {
            let code = String(trimmed.dropFirst("http_status:".count))
            guard let status = Int(code) else { return false }
            return (100...599).contains(status)
        }

        // unix socket - just needs a non-empty path
        if lowercased.hasPrefix("unix:") || lowercased.hasPrefix("unix+tls:") {
            let path = trimmed.drop(while: { $0 != ":" }).dropFirst()
            return !path.isEmpty
        }

        // Scheme-based services require a parseable URL with a host
        let validSchemes = ["http", "https", "tcp", "ssh", "rdp"]
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              validSchemes.contains(scheme) else {
            return false
        }

        guard let host = url.host, !host.isEmpty else { return false }

        if let port = url.port, !(1...65535).contains(port) {
            return false
        }

        return true
    }

    /// Whether a hostname is plausibly valid for an ingress rule.
    ///
    /// - Parameter hostname: The hostname to check.
    /// - Returns: `true` if the hostname looks valid.
    static func isValidHostname(_ hostname: String) -> Bool {
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 253 else { return false }

        // No whitespace or scheme fragments allowed
        guard !trimmed.contains(" "), !trimmed.contains("://") else { return false }

        // Each label: alphanumeric + hyphens/underscores, not starting/ending
        // with a hyphen. Underscores are allowed anywhere (Cloudflare accepts
        // names like "_dmarc.example.com"). A leading wildcard label ("*")
        // is allowed.
        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }

        for (index, label) in labels.enumerated() {
            if index == 0 && label == "*" { continue }
            guard !label.isEmpty, label.count <= 63 else { return false }
            guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
            guard label.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                return false
            }
        }

        return true
    }

    // MARK: - Normalization

    /// The default catch-all rule used when a configuration has none.
    static var defaultCatchAll: IngressRule {
        IngressRule(hostname: nil, path: nil, service: "http_status:404", originRequest: nil)
    }

    /// Normalizes a set of rules so exactly one catch-all rule is pinned last.
    ///
    /// Any catch-all rules found mid-list are removed; the first one found is
    /// preserved and moved to the end. If none exists, a default
    /// `http_status:404` catch-all is appended.
    ///
    /// - Parameter rules: The rules to normalize.
    /// - Returns: The normalized rules with the catch-all last.
    static func normalized(_ rules: [IngressRule]) -> [IngressRule] {
        let hostnameRules = rules.filter { !$0.isCatchAll }
        let catchAll = rules.first(where: { $0.isCatchAll }) ?? defaultCatchAll
        return hostnameRules + [catchAll]
    }
}
