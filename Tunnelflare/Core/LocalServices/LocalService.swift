//
//  LocalService.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - LocalServiceKind

/// The recognized kind of a local development server.
///
/// Kinds are derived from process-name and command-line heuristics and are
/// used for nicer labels and icons in the UI (e.g. `vite — :5173 (node)`).
enum LocalServiceKind: String, Sendable, CaseIterable {
    case node
    case python
    case ruby
    case php
    case go
    case java
    case rust
    case dotnet
    case docker
    case database
    case webServer
    case other

    /// A short human-readable runtime label (shown in parentheses in the UI).
    var label: String {
        switch self {
        case .node: return "node"
        case .python: return "python"
        case .ruby: return "ruby"
        case .php: return "php"
        case .go: return "go"
        case .java: return "java"
        case .rust: return "rust"
        case .dotnet: return ".net"
        case .docker: return "docker"
        case .database: return "database"
        case .webServer: return "web server"
        case .other: return ""
        }
    }

    /// SF Symbol name used to represent this kind in the UI.
    var systemImage: String {
        switch self {
        case .node, .python, .ruby, .php, .go, .java, .rust, .dotnet:
            return "chevron.left.forwardslash.chevron.right"
        case .docker:
            return "shippingbox"
        case .database:
            return "cylinder.split.1x2"
        case .webServer:
            return "server.rack"
        case .other:
            return "app.connected.to.app.below.fill"
        }
    }
}

// MARK: - LocalService

/// A service discovered listening on a local TCP port.
///
/// LocalService represents one row in the "Local Services" list: a process
/// owned by the current user that is accepting TCP connections on localhost
/// (or all interfaces) and looks like a development server.
struct LocalService: Identifiable, Hashable, Sendable {
    /// The TCP port the service is listening on.
    let port: Int

    /// The process ID of the listening process.
    let pid: Int32

    /// The raw process (command) name as reported by lsof.
    let processName: String

    /// The display name for the service (e.g. "vite", "rails", "node").
    ///
    /// Derived from the process command line when a known dev tool is
    /// recognized, otherwise falls back to the process name.
    let displayName: String

    /// The recognized kind of the service.
    let kind: LocalServiceKind

    /// A stable identity: one row per port.
    var id: Int { port }

    /// The local URL for the service (e.g. `http://localhost:5173`).
    var localURL: URL {
        URL(string: "http://localhost:\(port)")!
    }

    /// The service address without scheme, suitable for the tunnel wizard
    /// (e.g. `localhost:5173`).
    var serviceAddress: String {
        "localhost:\(port)"
    }

    /// The subtitle shown under the name (e.g. ":5173 (node)").
    var portLabel: String {
        let kindLabel = kind.label
        if kindLabel.isEmpty || kindLabel == displayName.lowercased() {
            return ":\(port)"
        }
        return ":\(port) (\(kindLabel))"
    }
}
