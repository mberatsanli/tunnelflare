//
//  IngressRuleValidatorTests.swift
//  TunnelflareTests
//
//  Created on 2026-07-16.
//  Tests for IngressRuleValidator and IngressRule Codable round-trips.
//

import XCTest
@testable import Tunnelflare

final class IngressRuleValidatorTests: XCTestCase {

    // MARK: - Helpers

    private func rule(_ hostname: String?, path: String? = nil, service: String) -> IngressRule {
        IngressRule(hostname: hostname, path: path, service: service, originRequest: nil)
    }

    private var catchAll: IngressRule {
        rule(nil, service: "http_status:404")
    }

    // MARK: - Validation: Valid Sets

    func testValidRuleSet() {
        let rules = [
            rule("app.example.com", service: "http://localhost:3000"),
            rule("api.example.com", service: "https://localhost:8443"),
            catchAll,
        ]

        XCTAssertTrue(IngressRuleValidator.validate(rules).isEmpty)
    }

    func testCatchAllOnlyIsValid() {
        XCTAssertTrue(IngressRuleValidator.validate([catchAll]).isEmpty)
    }

    func testSameHostnameDifferentPathsIsValid() {
        let rules = [
            rule("app.example.com", path: "/api", service: "http://localhost:8080"),
            rule("app.example.com", path: "/web", service: "http://localhost:3000"),
            catchAll,
        ]

        XCTAssertTrue(IngressRuleValidator.validate(rules).isEmpty)
    }

    // MARK: - Validation: Missing Catch-all

    func testMissingCatchAll() {
        let rules = [
            rule("app.example.com", service: "http://localhost:3000")
        ]

        let issues = IngressRuleValidator.validate(rules)
        XCTAssertTrue(issues.contains(.missingCatchAll))
    }

    func testEmptyRulesReportMissingCatchAll() {
        let issues = IngressRuleValidator.validate([])
        XCTAssertEqual(issues, [.missingCatchAll])
    }

    func testCatchAllNotLastReportsMissingCatchAll() {
        let rules = [
            catchAll,
            rule("app.example.com", service: "http://localhost:3000"),
        ]

        let issues = IngressRuleValidator.validate(rules)
        XCTAssertTrue(issues.contains(.missingCatchAll))
    }

    // MARK: - Validation: Duplicates

    func testDuplicateHostname() {
        let rules = [
            rule("app.example.com", service: "http://localhost:3000"),
            rule("app.example.com", service: "http://localhost:8080"),
            catchAll,
        ]

        let issues = IngressRuleValidator.validate(rules)
        XCTAssertTrue(issues.contains(.duplicateHostname("app.example.com")))
    }

    func testDuplicateHostnameIsCaseInsensitive() {
        let rules = [
            rule("App.Example.com", service: "http://localhost:3000"),
            rule("app.example.com", service: "http://localhost:8080"),
            catchAll,
        ]

        let issues = IngressRuleValidator.validate(rules)
        XCTAssertTrue(issues.contains(.duplicateHostname("app.example.com")))
    }

    // MARK: - Validation: Services

    func testValidServices() {
        let validServices = [
            "http://localhost:3000",
            "https://127.0.0.1:8443",
            "http://localhost",
            "tcp://localhost:5432",
            "ssh://localhost:22",
            "rdp://localhost:3389",
            "unix:/var/run/app.sock",
            "http_status:404",
            "http_status:200",
        ]

        for service in validServices {
            XCTAssertTrue(
                IngressRuleValidator.isValidService(service),
                "Expected '\(service)' to be valid"
            )
        }
    }

    func testInvalidServices() {
        let invalidServices = [
            "",
            "   ",
            "localhost:3000",           // Missing scheme
            "ftp://localhost:21",       // Unsupported scheme
            "http://",                  // Missing host
            "http_status:abc",          // Non-numeric status
            "http_status:99",           // Status out of range
            "http_status:600",          // Status out of range
            "unix:",                    // Missing socket path
        ]

        for service in invalidServices {
            XCTAssertFalse(
                IngressRuleValidator.isValidService(service),
                "Expected '\(service)' to be invalid"
            )
        }
    }

    func testInvalidServiceReported() {
        let rules = [
            rule("app.example.com", service: "not a url"),
            catchAll,
        ]

        let issues = IngressRuleValidator.validate(rules)
        XCTAssertTrue(issues.contains(.invalidService(hostname: "app.example.com", service: "not a url")))
    }

    // MARK: - Validation: Hostnames

    func testValidHostnames() {
        let validHostnames = [
            "app.example.com",
            "example.com",
            "a.b.c.example.com",
            "*.example.com",
            "my-app.example.com",
        ]

        for hostname in validHostnames {
            XCTAssertTrue(
                IngressRuleValidator.isValidHostname(hostname),
                "Expected '\(hostname)' to be valid"
            )
        }
    }

    func testInvalidHostnames() {
        let invalidHostnames = [
            "",
            "   ",
            "no-dots",
            "has space.example.com",
            "http://app.example.com",
            "-bad.example.com",
            "bad-.example.com",
            "under_score.example.com",
        ]

        for hostname in invalidHostnames {
            XCTAssertFalse(
                IngressRuleValidator.isValidHostname(hostname),
                "Expected '\(hostname)' to be invalid"
            )
        }
    }

    // MARK: - Normalization

    func testNormalizedAppendsMissingCatchAll() {
        let rules = [
            rule("app.example.com", service: "http://localhost:3000")
        ]

        let normalized = IngressRuleValidator.normalized(rules)
        XCTAssertEqual(normalized.count, 2)
        XCTAssertTrue(normalized.last?.isCatchAll == true)
        XCTAssertEqual(normalized.last?.service, "http_status:404")
    }

    func testNormalizedPinsCatchAllLast() {
        let rules = [
            catchAll,
            rule("app.example.com", service: "http://localhost:3000"),
        ]

        let normalized = IngressRuleValidator.normalized(rules)
        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized.first?.hostname, "app.example.com")
        XCTAssertTrue(normalized.last?.isCatchAll == true)
    }

    func testNormalizedPreservesCatchAllService() {
        let rules = [
            rule("app.example.com", service: "http://localhost:3000"),
            rule(nil, service: "http_status:503"),
        ]

        let normalized = IngressRuleValidator.normalized(rules)
        XCTAssertEqual(normalized.last?.service, "http_status:503")
    }

    func testNormalizedRemovesExtraCatchAlls() {
        let rules = [
            rule(nil, service: "http_status:404"),
            rule("app.example.com", service: "http://localhost:3000"),
            rule(nil, service: "http_status:503"),
        ]

        let normalized = IngressRuleValidator.normalized(rules)
        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized.filter { $0.isCatchAll }.count, 1)
        // First catch-all found wins
        XCTAssertEqual(normalized.last?.service, "http_status:404")
    }

    // MARK: - Codable Round-trip

    func testIngressRuleRoundTrip() throws {
        let original = IngressRule(
            hostname: "app.example.com",
            path: "/api",
            service: "http://localhost:8080",
            originRequest: nil
        )

        let data = try JSONEncoder.cloudflareAPI.encode(original)
        let decoded = try JSONDecoder.cloudflareAPI.decode(IngressRule.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testCatchAllRuleRoundTrip() throws {
        let original = IngressRule(
            hostname: nil,
            path: nil,
            service: "http_status:404",
            originRequest: nil
        )

        let data = try JSONEncoder.cloudflareAPI.encode(original)
        let decoded = try JSONDecoder.cloudflareAPI.decode(IngressRule.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isCatchAll)
    }

    func testIngressConfigRoundTrip() throws {
        let original = IngressConfig(
            ingress: [
                IngressRule(hostname: "app.example.com", path: nil, service: "http://localhost:3000", originRequest: nil),
                IngressRule(hostname: nil, path: nil, service: "http_status:404", originRequest: nil),
            ],
            warpRouting: WarpRouting(enabled: false),
            originRequest: nil
        )

        let data = try JSONEncoder.cloudflareAPI.encode(original)
        let decoded = try JSONDecoder.cloudflareAPI.decode(IngressConfig.self, from: data)

        XCTAssertEqual(decoded.ingress, original.ingress)
        XCTAssertEqual(decoded.warpRouting?.enabled, false)
    }

    func testTunnelConfigurationDecodesFromAPIJSON() throws {
        let json = """
        {
            "config": {
                "ingress": [
                    {
                        "hostname": "app.example.com",
                        "service": "http://localhost:3000"
                    },
                    {
                        "service": "http_status:404"
                    }
                ]
            },
            "source": "cloudflare",
            "version": 3
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.cloudflareAPI.decode(TunnelConfiguration.self, from: json)

        XCTAssertEqual(decoded.config.ingress.count, 2)
        XCTAssertEqual(decoded.config.ingress.first?.hostname, "app.example.com")
        XCTAssertTrue(decoded.config.ingress.last?.isCatchAll == true)
        XCTAssertEqual(decoded.source, "cloudflare")
        XCTAssertEqual(decoded.version, 3)
    }
}
