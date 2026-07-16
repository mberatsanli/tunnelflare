//
//  QuickTunnel.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - QuickTunnel

/// A local, ephemeral quick tunnel served via trycloudflare.com.
///
/// Quick tunnels are created with `cloudflared tunnel --url http://localhost:<port>`
/// and require no Cloudflare account, tunnel creation, or DNS setup. They are
/// NOT part of the Cloudflare API tunnel list — they exist only while the
/// local cloudflared process is running.
struct QuickTunnel: Identifiable, Sendable, Equatable {

    /// Locally generated identifier (prefixed with `QuickTunnelConstants.idPrefix`).
    let id: String

    /// The local port being shared.
    let port: Int

    /// The public trycloudflare.com URL, once discovered from cloudflared output.
    var publicURL: URL?

    /// The current local run state of the quick tunnel process.
    var state: TunnelRunState

    /// When the quick tunnel was started.
    let startedAt: Date

    /// The local URL that cloudflared proxies to.
    var localURL: String {
        "http://localhost:\(port)"
    }

    /// Display name used in menus, logs, and notifications.
    var displayName: String {
        "Quick Tunnel :\(port)"
    }

    /// Creates a new quick tunnel in the `.starting` state.
    ///
    /// - Parameter port: The local port to share.
    init(port: Int) {
        self.id = QuickTunnelConstants.idPrefix + UUID().uuidString.lowercased()
        self.port = port
        self.publicURL = nil
        self.state = .starting
        self.startedAt = Date()
    }

    /// Whether a tunnel ID belongs to a quick tunnel.
    ///
    /// - Parameter tunnelId: The tunnel ID to check.
    /// - Returns: True if the ID uses the quick tunnel prefix.
    static func isQuickTunnelId(_ tunnelId: String) -> Bool {
        tunnelId.hasPrefix(QuickTunnelConstants.idPrefix)
    }

    /// Validates and parses a user-entered port string.
    ///
    /// - Parameter input: The raw port text (e.g. "3000").
    /// - Returns: The port number if it is a valid TCP port (1-65535), nil otherwise.
    static func validatePort(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = Int(trimmed), (1...65535).contains(port) else {
            return nil
        }
        return port
    }
}

// MARK: - QuickTunnelURLParser

/// Parses the public trycloudflare.com URL from cloudflared output.
///
/// When started in quick tunnel mode, cloudflared prints the assigned URL
/// inside a boxed banner on stderr within a few seconds:
/// ```
/// +--------------------------------------------------------------------------------------------+
/// |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |
/// |  https://random-words-here.trycloudflare.com                                               |
/// +--------------------------------------------------------------------------------------------+
/// ```
enum QuickTunnelURLParser {

    /// Regex matching a trycloudflare.com URL anywhere in a log line.
    private static let urlPattern = #/https://[a-zA-Z0-9-]+\.trycloudflare\.com/#

    /// Extracts the public quick tunnel URL from a single log line.
    ///
    /// - Parameter line: A line of cloudflared output.
    /// - Returns: The trycloudflare.com URL if present, nil otherwise.
    static func parse(_ line: String) -> URL? {
        guard let match = line.firstMatch(of: urlPattern) else {
            return nil
        }
        return URL(string: String(match.output))
    }
}
