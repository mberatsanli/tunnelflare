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
            "http://http_status:404",   // Special-service keyword as host
            "https://http_status:200",  // Special-service keyword as host
            "http://hello_world:80",    // Underscore host (special service)
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
            "under_score.example.com",  // Cloudflare accepts underscores
            "_dmarc.example.com",
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

        XCTAssertEqual(decoded.config?.ingress.count, 2)
        XCTAssertEqual(decoded.config?.ingress.first?.hostname, "app.example.com")
        XCTAssertTrue(decoded.config?.ingress.last?.isCatchAll == true)
        XCTAssertEqual(decoded.source, "cloudflare")
        XCTAssertEqual(decoded.version, 3)
    }

    func testTunnelConfigurationDecodesNullConfig() throws {
        // A tunnel that was never configured returns "config": null; the
        // editor must treat it as an empty config instead of failing to load
        let json = """
        {
            "config": null,
            "source": "cloudflare",
            "version": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.cloudflareAPI.decode(TunnelConfiguration.self, from: json)

        XCTAssertNil(decoded.config)
        XCTAssertEqual(decoded.source, "cloudflare")
    }

    // MARK: - Round-trip Preservation of Unmodeled Fields

    /// A config JSON containing originRequest fields and per-rule keys the
    /// app does not model, as a dashboard-configured tunnel would return.
    private var configJSONWithUnmodeledFields: Data {
        """
        {
            "ingress": [
                {
                    "hostname": "app.example.com",
                    "service": "http://localhost:3000",
                    "originRequest": {
                        "connectTimeout": 30,
                        "ipRules": [
                            {"prefix": "10.0.0.0/8", "ports": [80, 443], "allow": true}
                        ],
                        "proxyAddress": "127.0.0.1",
                        "proxyPort": 9000,
                        "proxyType": "socks",
                        "bastionMode": true,
                        "caPool": "/etc/ssl/ca.pem",
                        "noHappyEyeballs": true,
                        "matchSNItoHost": true
                    }
                },
                {
                    "service": "http_status:404"
                }
            ],
            "warp-routing": {
                "enabled": true,
                "connectTimeout": 5
            },
            "originRequest": {
                "connectTimeout": 10,
                "noHappyEyeballs": true,
                "proxyType": "socks"
            },
            "someFutureField": {"nested": [1, 2.5, "x", null, false]}
        }
        """.data(using: .utf8)!
    }

    /// Encodes a config the way the update endpoint does (plain encoder, so
    /// preserved keys reach the API verbatim) and returns the JSON object.
    private func putJSONObject(for config: IngressConfig) throws -> [String: Any] {
        let data = try JSONEncoder().encode(config)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try XCTUnwrap(object)
    }

    func testConfigRoundTripPreservesUnmodeledFields() throws {
        let decoded = try JSONDecoder.cloudflareAPI.decode(IngressConfig.self, from: configJSONWithUnmodeledFields)

        // Rebuild the config exactly as the editor does on save
        let saved = IngressConfig(
            ingress: decoded.ingress,
            warpRouting: decoded.warpRouting,
            originRequest: decoded.originRequest,
            raw: decoded.raw
        )

        let object = try putJSONObject(for: saved)

        // Unmodeled top-level key survives
        XCTAssertNotNil(object["someFutureField"])

        // Global originRequest keeps unmodeled fields with exact key names
        let originRequest = try XCTUnwrap(object["originRequest"] as? [String: Any])
        XCTAssertEqual(originRequest["connectTimeout"] as? Int, 10)
        XCTAssertEqual(originRequest["noHappyEyeballs"] as? Bool, true)
        XCTAssertEqual(originRequest["proxyType"] as? String, "socks")

        // warp-routing keeps unmodeled fields
        let warpRouting = try XCTUnwrap(object["warp-routing"] as? [String: Any])
        XCTAssertEqual(warpRouting["enabled"] as? Bool, true)
        XCTAssertEqual(warpRouting["connectTimeout"] as? Int, 5)

        // Per-rule originRequest keeps every unmodeled field
        let rules = try XCTUnwrap(object["ingress"] as? [[String: Any]])
        XCTAssertEqual(rules.count, 2)
        let ruleOrigin = try XCTUnwrap(rules[0]["originRequest"] as? [String: Any])
        XCTAssertEqual(ruleOrigin["proxyPort"] as? Int, 9000)
        XCTAssertEqual(ruleOrigin["proxyAddress"] as? String, "127.0.0.1")
        XCTAssertEqual(ruleOrigin["bastionMode"] as? Bool, true)
        XCTAssertEqual(ruleOrigin["caPool"] as? String, "/etc/ssl/ca.pem")
        XCTAssertEqual(ruleOrigin["noHappyEyeballs"] as? Bool, true)
        XCTAssertEqual(ruleOrigin["matchSNItoHost"] as? Bool, true)
        XCTAssertNotNil(ruleOrigin["ipRules"])
    }

    func testEditedRulePreservesUnmodeledFields() throws {
        let decoded = try JSONDecoder.cloudflareAPI.decode(IngressConfig.self, from: configJSONWithUnmodeledFields)
        let original = decoded.ingress[0]

        // Edit hostname and service the way commitRuleForm does, carrying
        // originRequest and raw over from the edited rule
        let edited = IngressRule(
            hostname: "new.example.com",
            path: "/api",
            service: "https://localhost:8443",
            originRequest: original.originRequest,
            raw: original.raw
        )

        let saved = IngressConfig(
            ingress: [edited, decoded.ingress[1]],
            warpRouting: decoded.warpRouting,
            originRequest: decoded.originRequest,
            raw: decoded.raw
        )

        let object = try putJSONObject(for: saved)
        let rules = try XCTUnwrap(object["ingress"] as? [[String: Any]])

        // Edited fields are applied...
        XCTAssertEqual(rules[0]["hostname"] as? String, "new.example.com")
        XCTAssertEqual(rules[0]["path"] as? String, "/api")
        XCTAssertEqual(rules[0]["service"] as? String, "https://localhost:8443")

        // ...while unmodeled per-rule settings survive untouched
        let ruleOrigin = try XCTUnwrap(rules[0]["originRequest"] as? [String: Any])
        XCTAssertEqual(ruleOrigin["proxyType"] as? String, "socks")
        XCTAssertEqual(ruleOrigin["bastionMode"] as? Bool, true)
        XCTAssertNotNil(ruleOrigin["ipRules"])

        // Catch-all is untouched and keeps no hostname key
        XCTAssertNil(rules[1]["hostname"])
        XCTAssertEqual(rules[1]["service"] as? String, "http_status:404")
    }

    func testLocallyCreatedRuleEncodesTypedFields() throws {
        // A rule added in the editor (no raw JSON) must still encode cleanly
        let config = IngressConfig(
            ingress: [
                IngressRule(hostname: "app.example.com", path: nil, service: "http://localhost:3000", originRequest: nil),
                IngressRuleValidator.defaultCatchAll,
            ],
            warpRouting: nil,
            originRequest: nil
        )

        let object = try putJSONObject(for: config)
        let rules = try XCTUnwrap(object["ingress"] as? [[String: Any]])

        XCTAssertEqual(rules[0]["hostname"] as? String, "app.example.com")
        XCTAssertEqual(rules[0]["service"] as? String, "http://localhost:3000")
        XCTAssertNil(rules[0]["path"])
        XCTAssertNil(object["warp-routing"])
        XCTAssertNil(object["originRequest"])
    }
}
