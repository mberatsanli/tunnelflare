//
//  QuickTunnelTests.swift
//  TunnelflareTests
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import XCTest
@testable import Tunnelflare

// MARK: - QuickTunnelURLParser Tests

final class QuickTunnelURLParserTests: XCTestCase {

    // MARK: - Positive Cases

    func testParsesURLFromBannerLine() {
        let line = "2026-07-16T10:00:00Z INF |  https://witty-otter-random.trycloudflare.com                                            |"
        let url = QuickTunnelURLParser.parse(line)

        XCTAssertEqual(url?.absoluteString, "https://witty-otter-random.trycloudflare.com")
    }

    func testParsesURLFromBoxedBannerWithPlusBorder() {
        let line = "|  https://alpha-beta-gamma-delta.trycloudflare.com  |"
        let url = QuickTunnelURLParser.parse(line)

        XCTAssertEqual(url?.absoluteString, "https://alpha-beta-gamma-delta.trycloudflare.com")
    }

    func testParsesURLWithSurroundingText() {
        let line = "Your quick Tunnel has been created! Visit it at https://my-tunnel.trycloudflare.com now"
        let url = QuickTunnelURLParser.parse(line)

        XCTAssertEqual(url?.absoluteString, "https://my-tunnel.trycloudflare.com")
    }

    func testParsesURLWithDigitsAndHyphens() {
        let line = "https://a1-b2-c3-d4.trycloudflare.com"
        let url = QuickTunnelURLParser.parse(line)

        XCTAssertEqual(url?.absoluteString, "https://a1-b2-c3-d4.trycloudflare.com")
    }

    // MARK: - Negative Cases

    func testReturnsNilForLineWithoutURL() {
        let line = "2026-07-16T10:00:00Z INF Requesting new quick Tunnel on trycloudflare.com..."
        XCTAssertNil(QuickTunnelURLParser.parse(line))
    }

    func testReturnsNilForEmptyLine() {
        XCTAssertNil(QuickTunnelURLParser.parse(""))
    }

    func testReturnsNilForHTTPURL() {
        // Quick tunnel URLs are always https
        XCTAssertNil(QuickTunnelURLParser.parse("http://insecure.trycloudflare.com"))
    }

    func testReturnsNilForOtherCloudflareDomains() {
        XCTAssertNil(QuickTunnelURLParser.parse("https://dash.cloudflare.com/some/path"))
    }

    func testReturnsNilForQuickTunnelAPIEndpoint() {
        // cloudflared registers quick tunnels against api.trycloudflare.com;
        // error lines containing that endpoint must not be mistaken for the
        // assigned public URL
        let line = "ERR failed to request quick Tunnel: https://api.trycloudflare.com/tunnel unreachable"
        XCTAssertNil(QuickTunnelURLParser.parse(line))
    }
}

// MARK: - QuickTunnel Model Tests

final class QuickTunnelTests: XCTestCase {

    // MARK: - Initialization

    func testNewQuickTunnelHasPrefixedIdAndStartingState() {
        let tunnel = QuickTunnel(port: 3000)

        XCTAssertTrue(tunnel.id.hasPrefix(QuickTunnelConstants.idPrefix))
        XCTAssertEqual(tunnel.port, 3000)
        XCTAssertEqual(tunnel.state, .starting)
        XCTAssertNil(tunnel.publicURL)
    }

    func testNewQuickTunnelsHaveUniqueIds() {
        let first = QuickTunnel(port: 3000)
        let second = QuickTunnel(port: 3000)

        XCTAssertNotEqual(first.id, second.id)
    }

    func testLocalURLAndDisplayName() {
        let tunnel = QuickTunnel(port: 8080)

        XCTAssertEqual(tunnel.localURL, "http://localhost:8080")
        XCTAssertEqual(tunnel.displayName, "Quick Tunnel :8080")
    }

    // MARK: - ID Prefix

    func testIsQuickTunnelIdRecognizesPrefix() {
        XCTAssertTrue(QuickTunnel.isQuickTunnelId("quick-abc123"))
        XCTAssertFalse(QuickTunnel.isQuickTunnelId("2f77bfb4-0f34-4c5e-a7ec-example"))
        XCTAssertFalse(QuickTunnel.isQuickTunnelId(""))
    }

    // MARK: - Port Validation

    func testValidatePortAcceptsValidPorts() {
        XCTAssertEqual(QuickTunnel.validatePort("1"), 1)
        XCTAssertEqual(QuickTunnel.validatePort("3000"), 3000)
        XCTAssertEqual(QuickTunnel.validatePort("65535"), 65535)
    }

    func testValidatePortTrimsWhitespace() {
        XCTAssertEqual(QuickTunnel.validatePort("  8080  "), 8080)
        XCTAssertEqual(QuickTunnel.validatePort("\n443\n"), 443)
    }

    func testValidatePortRejectsInvalidInput() {
        XCTAssertNil(QuickTunnel.validatePort(""))
        XCTAssertNil(QuickTunnel.validatePort("0"))
        XCTAssertNil(QuickTunnel.validatePort("65536"))
        XCTAssertNil(QuickTunnel.validatePort("-80"))
        XCTAssertNil(QuickTunnel.validatePort("abc"))
        XCTAssertNil(QuickTunnel.validatePort("80.5"))
        XCTAssertNil(QuickTunnel.validatePort("http://localhost:3000"))
    }
}
