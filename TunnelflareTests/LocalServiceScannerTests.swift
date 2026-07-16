//
//  LocalServiceScannerTests.swift
//  TunnelflareTests
//
//  Created on 2026-07-16.
//  Tests for LocalServiceScanner parsing, filtering, and classification.
//

import XCTest
@testable import Tunnelflare

final class LocalServiceScannerTests: XCTestCase {

    // MARK: - Port Parsing Tests

    func testPortFromWildcardAddress() {
        XCTAssertEqual(LocalServiceScanner.port(fromAddress: "*:5173"), 5173)
    }

    func testPortFromIPv4Address() {
        XCTAssertEqual(LocalServiceScanner.port(fromAddress: "127.0.0.1:3000"), 3000)
    }

    func testPortFromIPv6LoopbackAddress() {
        XCTAssertEqual(LocalServiceScanner.port(fromAddress: "[::1]:8080"), 8080)
    }

    func testPortFromIPv6WildcardAddress() {
        XCTAssertEqual(LocalServiceScanner.port(fromAddress: "[::]:5173"), 5173)
    }

    func testPortFromInvalidAddresses() {
        XCTAssertNil(LocalServiceScanner.port(fromAddress: ""))
        XCTAssertNil(LocalServiceScanner.port(fromAddress: "no-port"))
        XCTAssertNil(LocalServiceScanner.port(fromAddress: "*:"))
        XCTAssertNil(LocalServiceScanner.port(fromAddress: "*:abc"))
        XCTAssertNil(LocalServiceScanner.port(fromAddress: "*:0"))
        XCTAssertNil(LocalServiceScanner.port(fromAddress: "*:99999"))
    }

    // MARK: - lsof Output Parsing Tests

    func testParseListenersFromFieldOutput() {
        let output = """
        p123
        cnode
        f23
        n*:5173
        p456
        cpostgres
        f7
        n[::1]:5432
        f8
        n127.0.0.1:5432
        """

        let listeners = LocalServiceScanner.parseListeners(from: output)

        // The postgres IPv6 + IPv4 listeners on the same port collapse to one
        XCTAssertEqual(listeners.count, 2)
        XCTAssertEqual(listeners[0].pid, 123)
        XCTAssertEqual(listeners[0].processName, "node")
        XCTAssertEqual(listeners[0].port, 5173)
        XCTAssertEqual(listeners[1].pid, 456)
        XCTAssertEqual(listeners[1].processName, "postgres")
        XCTAssertEqual(listeners[1].port, 5432)
    }

    func testParseListenersDeduplicatesIdenticalEntries() {
        // Same process listening twice on the same port (e.g. two fds)
        let output = """
        p123
        cnode
        f23
        n*:5173
        f24
        n*:5173
        """

        let listeners = LocalServiceScanner.parseListeners(from: output)
        XCTAssertEqual(listeners.count, 1)
    }

    func testParseListenersHandlesEmptyOutput() {
        XCTAssertTrue(LocalServiceScanner.parseListeners(from: "").isEmpty)
    }

    func testParseListenersIgnoresMalformedLines() {
        let output = """
        pnotanumber
        cnode
        n*:5173
        garbage
        p123
        n*:3000
        """

        // First block: pid unparsable → dropped.
        // Second block: no command name → dropped.
        XCTAssertTrue(LocalServiceScanner.parseListeners(from: output).isEmpty)
    }

    // MARK: - Filtering Tests

    func testBuildServicesFiltersSystemDaemons() {
        let listeners = [
            LocalServiceScanner.Listener(pid: 1, processName: "ControlCenter", port: 5000),
            LocalServiceScanner.Listener(pid: 2, processName: "rapportd", port: 49200),
            LocalServiceScanner.Listener(pid: 3, processName: "node", port: 3000)
        ]

        let services = LocalServiceScanner.buildServices(listeners: listeners, commandLines: [:])

        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services[0].port, 3000)
    }

    func testBuildServicesFiltersWellKnownNonDevPorts() {
        let listeners = [
            LocalServiceScanner.Listener(pid: 1, processName: "someproc", port: 22),
            LocalServiceScanner.Listener(pid: 2, processName: "someproc", port: 445),
            LocalServiceScanner.Listener(pid: 3, processName: "node", port: 5173)
        ]

        let services = LocalServiceScanner.buildServices(listeners: listeners, commandLines: [:])

        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services[0].port, 5173)
    }

    func testBuildServicesFiltersEphemeralPortsForUnrecognizedProcesses() {
        let listeners = [
            // Unrecognized app on an ephemeral port → filtered
            LocalServiceScanner.Listener(pid: 1, processName: "SomeRandomApp", port: 59869),
            // Recognized dev runtime on an ephemeral port → kept
            LocalServiceScanner.Listener(pid: 2, processName: "node", port: 55000)
        ]

        let services = LocalServiceScanner.buildServices(listeners: listeners, commandLines: [:])

        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services[0].port, 55000)
        XCTAssertEqual(services[0].kind, .node)
    }

    func testBuildServicesDeduplicatesByPort() {
        // IPv4 + IPv6 listeners for the same server
        let listeners = [
            LocalServiceScanner.Listener(pid: 100, processName: "python3", port: 8000),
            LocalServiceScanner.Listener(pid: 100, processName: "python3", port: 8000)
        ]

        let services = LocalServiceScanner.buildServices(listeners: listeners, commandLines: [:])
        XCTAssertEqual(services.count, 1)
    }

    func testBuildServicesPrefersRecognizedKindWhenDeduplicating() {
        let listeners = [
            LocalServiceScanner.Listener(pid: 1, processName: "mystery-binary", port: 4000),
            LocalServiceScanner.Listener(pid: 2, processName: "node", port: 4000)
        ]

        let services = LocalServiceScanner.buildServices(listeners: listeners, commandLines: [:])

        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services[0].kind, .node)
    }

    func testBuildServicesSortsByPort() {
        let listeners = [
            LocalServiceScanner.Listener(pid: 1, processName: "node", port: 8080),
            LocalServiceScanner.Listener(pid: 2, processName: "ruby", port: 3000),
            LocalServiceScanner.Listener(pid: 3, processName: "python3", port: 5001)
        ]

        let services = LocalServiceScanner.buildServices(listeners: listeners, commandLines: [:])
        XCTAssertEqual(services.map(\.port), [3000, 5001, 8080])
    }

    // MARK: - Classification Tests

    func testKindForKnownProcessNames() {
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "node"), .node)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "bun"), .node)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "python3.12"), .python)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "ruby"), .ruby)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "puma"), .ruby)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "php-fpm"), .php)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "java"), .java)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "go"), .go)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "dotnet"), .dotnet)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "com.docker.backend"), .docker)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "postgres"), .database)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "nginx"), .webServer)
        XCTAssertEqual(LocalServiceScanner.kind(forProcessName: "mystery"), .other)
    }

    func testClassifyRecognizesViteFromCommandLine() {
        let (name, kind) = LocalServiceScanner.classify(
            processName: "node",
            commandLine: "node /Users/dev/project/node_modules/.bin/vite --port 5173"
        )

        XCTAssertEqual(name, "vite")
        XCTAssertEqual(kind, .node)
    }

    func testClassifyRecognizesRailsFromCommandLine() {
        let (name, kind) = LocalServiceScanner.classify(
            processName: "ruby",
            commandLine: "ruby bin/rails server -p 3000"
        )

        XCTAssertEqual(name, "rails")
        XCTAssertEqual(kind, .ruby)
    }

    func testClassifyRecognizesDjangoFromManagePy() {
        let (name, kind) = LocalServiceScanner.classify(
            processName: "python3",
            commandLine: "python3 manage.py runserver 8000"
        )

        XCTAssertEqual(name, "django")
        XCTAssertEqual(kind, .python)
    }

    func testClassifyFallsBackToProcessName() {
        let (name, kind) = LocalServiceScanner.classify(
            processName: "node",
            commandLine: "node server.js"
        )

        XCTAssertEqual(name, "node")
        XCTAssertEqual(kind, .node)
    }

    func testClassifyDoesNotMatchToolTokensInsideLongerWords() {
        // "next" inside "nextcloud" must not match
        let (nextName, _) = LocalServiceScanner.classify(
            processName: "node",
            commandLine: "node /Users/dev/nextcloud/server.js"
        )
        XCTAssertEqual(nextName, "node")

        // "expo" inside "export" must not match
        let (expoName, _) = LocalServiceScanner.classify(
            processName: "node",
            commandLine: "sh -c 'export PORT=3000' && node app.js"
        )
        XCTAssertEqual(expoName, "node")

        // "vite" inside "invite" must not match
        let (viteName, _) = LocalServiceScanner.classify(
            processName: "node",
            commandLine: "node /Users/dev/invite-app/server.js"
        )
        XCTAssertEqual(viteName, "node")
    }

    func testClassifyMatchesToolTokensAtPathBoundaries() {
        // Token preceded by "/" and followed by whitespace still matches
        let (name, _) = LocalServiceScanner.classify(
            processName: "node",
            commandLine: "node /project/node_modules/.bin/next dev"
        )
        XCTAssertEqual(name, "next")
    }

    func testClassifyWithoutCommandLine() {
        let (name, kind) = LocalServiceScanner.classify(processName: "Postgres", commandLine: nil)

        XCTAssertEqual(name, "postgres")
        XCTAssertEqual(kind, .database)
    }

    // MARK: - ps Output Parsing Tests

    func testParseCommandLines() {
        let output = """
          123 node /project/node_modules/.bin/vite
          456 python3 manage.py runserver
        """

        let commandLines = LocalServiceScanner.parseCommandLines(from: output)

        XCTAssertEqual(commandLines.count, 2)
        XCTAssertEqual(commandLines[123], "node /project/node_modules/.bin/vite")
        XCTAssertEqual(commandLines[456], "python3 manage.py runserver")
    }

    func testParseCommandLinesHandlesEmptyOutput() {
        XCTAssertTrue(LocalServiceScanner.parseCommandLines(from: "").isEmpty)
    }

    // MARK: - LocalService Model Tests

    func testLocalServiceURLs() {
        let service = LocalService(
            port: 5173,
            pid: 123,
            processName: "node",
            displayName: "vite",
            kind: .node
        )

        XCTAssertEqual(service.localURL.absoluteString, "http://localhost:5173")
        XCTAssertEqual(service.serviceAddress, "localhost:5173")
        XCTAssertEqual(service.portLabel, ":5173 (node)")
    }

    func testLocalServicePortLabelOmitsRedundantKind() {
        // displayName equals the kind label → no duplicate "(node)" suffix
        let service = LocalService(
            port: 3000,
            pid: 1,
            processName: "node",
            displayName: "node",
            kind: .node
        )

        XCTAssertEqual(service.portLabel, ":3000")
    }
}
