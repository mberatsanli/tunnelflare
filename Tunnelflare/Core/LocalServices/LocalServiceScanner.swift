//
//  LocalServiceScanner.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - LocalServiceScanner

/// Discovers services listening on local TCP ports.
///
/// LocalServiceScanner enumerates listening sockets via
/// `lsof -nP -iTCP -sTCP:LISTEN` (the app already shells out to external
/// binaries for cloudflared, so this is sandbox-friendly and needs no
/// elevated privileges — lsof only reports processes owned by the current
/// user when run unprivileged).
///
/// The raw listener list is then:
/// - mapped from PIDs to process names and command lines (via `ps`)
/// - filtered to drop system daemons and well-known non-dev ports
/// - deduplicated by port (one row per port)
/// - classified with process/port heuristics for nicer labels
///   (node/vite/next, python/flask/django, ruby/rails, go, php, java, ...)
///
/// If lsof is unavailable or fails, the scanner degrades gracefully and
/// returns an empty list.
///
/// ## Usage
/// ```swift
/// let scanner = LocalServiceScanner()
/// let services = await scanner.scan()
/// for service in services {
///     print("\(service.displayName) — :\(service.port)")
/// }
/// ```
actor LocalServiceScanner {

    // MARK: - Types

    /// A raw TCP listener parsed from lsof output.
    struct Listener: Hashable, Sendable {
        let pid: Int32
        let processName: String
        let port: Int
    }

    // MARK: - Constants

    /// Candidate paths for the lsof binary.
    private static let lsofPaths = ["/usr/sbin/lsof", "/usr/bin/lsof"]

    /// Path to the ps binary used to resolve command lines.
    private static let psPath = "/bin/ps"

    /// Process names of system daemons and non-dev apps to ignore.
    ///
    /// lsof reports these as listening, but they are never dev servers the
    /// user would want to tunnel.
    static let ignoredProcessNames: Set<String> = [
        "launchd", "rapportd", "sharingd", "controlcenter",
        "identityservicesd", "remoted", "remotepairingd", "bluetoothd",
        "airplayxpchelper", "mdnsresponder", "assistantd",
        "ampdevicediscoveryagent", "universalcontrol", "screensharingd",
        "cupsd", "kdc", "smbd", "netbiosd", "spotify", "dropbox",
        "onedrive", "logipluginservice", "logioptionsplus_agent",
        "cloudflared", "tunnelflare"
    ]

    /// Well-known non-dev ports to ignore (system services).
    static let ignoredPorts: Set<Int> = [
        22,    // SSH (remote login)
        25,    // SMTP
        53,    // DNS
        88,    // Kerberos
        445,   // SMB
        548,   // AFP
        631,   // CUPS printing
        5900   // Screen Sharing (VNC)
    ]

    /// Start of the ephemeral port range. Listeners on ephemeral ports are
    /// ignored unless the process is a recognized dev runtime, since system
    /// daemons and desktop apps typically bind random high ports.
    static let ephemeralPortStart = 49152

    // MARK: - Properties

    /// Logger for scan operations.
    private let logger = Logger.process

    // MARK: - Public Methods

    /// Scans for local services listening on TCP ports.
    ///
    /// - Returns: The discovered services, sorted by port. Empty if lsof
    ///   output is unavailable.
    func scan() async -> [LocalService] {
        guard let output = await runLsof() else {
            logger.warning("lsof unavailable or failed; local service scan returned nothing")
            return []
        }

        let listeners = Self.parseListeners(from: output)
        let commandLines = await resolveCommandLines(pids: Set(listeners.map(\.pid)))

        return Self.buildServices(listeners: listeners, commandLines: commandLines)
    }

    // MARK: - Parsing (pure, testable)

    /// Parses lsof field output (`-Fpcn`) into raw listeners.
    ///
    /// The field format emits one value per line, prefixed by a field
    /// character: `p<pid>`, `c<command>`, `f<fd>`, `n<address>`.
    ///
    /// - Parameter output: The raw lsof `-Fpcn` output.
    /// - Returns: The parsed listeners (unfiltered, may contain duplicates).
    static func parseListeners(from output: String) -> [Listener] {
        var listeners: [Listener] = []
        var seen = Set<Listener>()

        var currentPid: Int32?
        var currentName: String?

        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                currentPid = Int32(value)
                currentName = nil
            case "c":
                currentName = value
            case "n":
                guard let pid = currentPid,
                      let name = currentName,
                      let port = port(fromAddress: value) else {
                    continue
                }
                let listener = Listener(pid: pid, processName: name, port: port)
                if seen.insert(listener).inserted {
                    listeners.append(listener)
                }
            default:
                // f (fd) and any other fields are irrelevant
                continue
            }
        }

        return listeners
    }

    /// Extracts the port from an lsof network address.
    ///
    /// Handles the forms lsof emits with `-nP`:
    /// `*:5173`, `127.0.0.1:3000`, `[::1]:8080`, `[::]:5173`.
    ///
    /// - Parameter address: The lsof `n` field value.
    /// - Returns: The port, or nil if it could not be parsed.
    static func port(fromAddress address: String) -> Int? {
        guard let colonIndex = address.lastIndex(of: ":") else { return nil }
        let portString = address[address.index(after: colonIndex)...]
        guard let port = Int(portString), (1...65535).contains(port) else { return nil }
        return port
    }

    /// Builds the final service list from raw listeners.
    ///
    /// Applies filtering (system daemons, ignored ports, ephemeral ports),
    /// deduplicates by port, classifies each service, and sorts by port.
    ///
    /// - Parameters:
    ///   - listeners: The raw listeners from lsof.
    ///   - commandLines: Full command lines keyed by PID (from ps), used for
    ///     dev-tool recognition.
    /// - Returns: The filtered, deduplicated, classified services.
    static func buildServices(
        listeners: [Listener],
        commandLines: [Int32: String]
    ) -> [LocalService] {
        var byPort: [Int: LocalService] = [:]

        for listener in listeners {
            let normalizedName = listener.processName.lowercased()

            // Filter: system daemons and non-dev apps
            guard !ignoredProcessNames.contains(normalizedName) else { continue }

            // Filter: well-known non-dev ports
            guard !ignoredPorts.contains(listener.port) else { continue }

            let (displayName, kind) = classify(
                processName: listener.processName,
                commandLine: commandLines[listener.pid]
            )

            // Filter: ephemeral ports, unless the process is a recognized
            // dev runtime (daemons and desktop apps bind random high ports)
            if listener.port >= ephemeralPortStart && kind == .other { continue }

            let service = LocalService(
                port: listener.port,
                pid: listener.pid,
                processName: listener.processName,
                displayName: displayName,
                kind: kind
            )

            // Dedupe by port: prefer a recognized kind over .other
            // (e.g. IPv4 + IPv6 listeners, or parent/child workers)
            if let existing = byPort[listener.port] {
                if existing.kind == .other && kind != .other {
                    byPort[listener.port] = service
                }
            } else {
                byPort[listener.port] = service
            }
        }

        return byPort.values.sorted { $0.port < $1.port }
    }

    /// Classifies a process into a display name and service kind.
    ///
    /// Recognizes common dev servers by process name (node, python, ruby,
    /// php, java, ...) and refines the display name from the command line
    /// when a known tool is present (vite, next, rails, django, ...).
    ///
    /// - Parameters:
    ///   - processName: The process (command) name from lsof.
    ///   - commandLine: The full command line from ps, if available.
    /// - Returns: The display name and kind for the service.
    static func classify(
        processName: String,
        commandLine: String?
    ) -> (displayName: String, kind: LocalServiceKind) {
        let name = processName.lowercased()
        let kind = kind(forProcessName: name)

        // Try to recognize a specific dev tool from the command line for a
        // nicer label (e.g. "vite" instead of "node")
        if let commandLine, let tool = devTool(inCommandLine: commandLine.lowercased()) {
            return (tool, kind)
        }

        return (name, kind)
    }

    /// Maps a lowercase process name to a service kind.
    static func kind(forProcessName name: String) -> LocalServiceKind {
        switch name {
        case "node", "bun", "deno", "npm", "npx", "pnpm", "yarn":
            return .node
        case let n where n.hasPrefix("python") || n == "uvicorn" || n == "gunicorn" || n == "flask":
            return .python
        case "ruby", "rails", "puma", "unicorn":
            return .ruby
        case let n where n.hasPrefix("php"):
            return .php
        case "java":
            return .java
        case "go":
            return .go
        case "cargo", "rustc":
            return .rust
        case "dotnet":
            return .dotnet
        case let n where n.hasPrefix("docker") || n.hasPrefix("com.docker"):
            return .docker
        case "postgres", "mysqld", "mariadbd", "redis-server", "mongod", "memcached", "clickhouse":
            return .database
        case "nginx", "httpd", "caddy", "traefik":
            return .webServer
        default:
            return .other
        }
    }

    /// Known dev tools recognizable from a command line, mapped to display
    /// names, in matching priority order.
    private static let devTools: [(token: String, displayName: String)] = [
        ("vite", "vite"), ("next", "next"), ("nuxt", "nuxt"),
        ("astro", "astro"), ("remix", "remix"), ("webpack", "webpack"),
        ("parcel", "parcel"), ("storybook", "storybook"),
        ("react-scripts", "react"), ("ng serve", "angular"), ("expo", "expo"),
        ("rails", "rails"), ("puma", "puma"), ("jekyll", "jekyll"),
        ("flask", "flask"), ("django", "django"), ("manage.py", "django"),
        ("uvicorn", "uvicorn"), ("gunicorn", "gunicorn"),
        ("fastapi", "fastapi"), ("streamlit", "streamlit"),
        ("artisan", "laravel"), ("hugo", "hugo"), ("wrangler", "wrangler")
    ]

    /// Precompiled boundary-aware matchers for the known dev tools.
    ///
    /// Each token must stand alone (not be a substring of a longer word or
    /// path component), so "expo" does not match "export" and "next" does
    /// not match "nextcloud". NSRegularExpression (ICU) is used because
    /// Swift's native Regex does not support lookbehind assertions.
    private static let devToolMatchers: [(displayName: String, regex: NSRegularExpression)] = {
        devTools.compactMap { tool in
            let escaped = NSRegularExpression.escapedPattern(for: tool.token)
            guard let regex = try? NSRegularExpression(
                pattern: "(?<![0-9a-z_-])\(escaped)(?![0-9a-z_-])"
            ) else {
                return nil
            }
            return (tool.displayName, regex)
        }
    }()

    /// Recognizes a known dev tool inside a command line.
    ///
    /// - Parameter commandLine: The lowercase command line.
    /// - Returns: The tool's display name, or nil if none is recognized.
    static func devTool(inCommandLine commandLine: String) -> String? {
        let range = NSRange(commandLine.startIndex..., in: commandLine)

        for matcher in devToolMatchers
        where matcher.regex.firstMatch(in: commandLine, options: [], range: range) != nil {
            return matcher.displayName
        }

        return nil
    }

    // MARK: - Private Methods

    /// Runs an external process and returns its stdout, or nil on failure.
    ///
    /// The blocking Process APIs (`waitUntilExit`, pipe reads) run on a
    /// global dispatch queue so they never park a Swift-concurrency
    /// cooperative thread while lsof/ps execute.
    private static func runProcess(path: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }

    /// Runs lsof and returns its raw field output, or nil on failure.
    private func runLsof() async -> String? {
        guard let lsofPath = Self.lsofPaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else {
            return nil
        }

        // +c 0: full command names; -nP: numeric hosts/ports;
        // -Fpcn: machine-parsable field output (pid, command, name)
        let output = await Self.runProcess(
            path: lsofPath,
            arguments: ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        )

        // lsof exits non-zero when some sockets can't be inspected; partial
        // output is still usable, so only bail when there is no output.
        guard let output, !output.isEmpty else {
            logger.error("lsof produced no output")
            return nil
        }

        return output
    }

    /// Resolves full command lines for the given PIDs via ps.
    ///
    /// - Parameter pids: The PIDs to resolve.
    /// - Returns: Command lines keyed by PID. Empty on failure (labels then
    ///   fall back to process names).
    private func resolveCommandLines(pids: Set<Int32>) async -> [Int32: String] {
        guard !pids.isEmpty,
              FileManager.default.isExecutableFile(atPath: Self.psPath) else {
            return [:]
        }

        let output = await Self.runProcess(
            path: Self.psPath,
            arguments: ["-o", "pid=,command=", "-p", pids.map(String.init).joined(separator: ",")]
        )

        guard let output else {
            logger.error("ps produced no output; falling back to process names")
            return [:]
        }

        return Self.parseCommandLines(from: output)
    }

    /// Parses `ps -o pid=,command=` output into a PID → command line map.
    ///
    /// - Parameter output: The raw ps output.
    /// - Returns: Command lines keyed by PID.
    static func parseCommandLines(from output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let spaceIndex = trimmed.firstIndex(of: " "),
                  let pid = Int32(trimmed[..<spaceIndex]) else {
                continue
            }
            result[pid] = String(trimmed[trimmed.index(after: spaceIndex)...])
                .trimmingCharacters(in: .whitespaces)
        }

        return result
    }
}
