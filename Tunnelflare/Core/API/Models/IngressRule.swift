//
//  IngressRule.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - TunnelConfiguration

/// The configuration for a Cloudflare Tunnel.
///
/// Contains the ingress rules that define how traffic is routed
/// from Cloudflare to origin services.
///
/// ## Example JSON
/// ```json
/// {
///   "config": {
///     "ingress": [
///       {
///         "hostname": "app.example.com",
///         "service": "http://localhost:3000"
///       },
///       {
///         "service": "http_status:404"
///       }
///     ]
///   }
/// }
/// ```
struct TunnelConfiguration: Codable, Sendable {
    /// The configuration content.
    let config: IngressConfig

    /// The source of the configuration.
    let source: String?

    /// Version of the configuration.
    let version: Int?
}

// MARK: - IngressConfig

/// The ingress configuration containing routing rules.
struct IngressConfig: Codable, Sendable {
    /// The list of ingress rules.
    let ingress: [IngressRule]

    /// Warp routing configuration.
    let warpRouting: WarpRouting?

    /// Origin request settings.
    let originRequest: OriginRequestConfig?

    enum CodingKeys: String, CodingKey {
        case ingress
        case warpRouting = "warp-routing"
        case originRequest = "originRequest"
    }
}

// MARK: - IngressRule

/// An ingress rule that maps a hostname to a service.
///
/// Ingress rules are evaluated in order. The last rule must be a catch-all
/// rule with no hostname specified.
///
/// ## Examples
/// ```swift
/// // Route specific hostname to local service
/// IngressRule(hostname: "app.example.com", service: "http://localhost:3000")
///
/// // Catch-all rule (must be last)
/// IngressRule(hostname: nil, service: "http_status:404")
/// ```
struct IngressRule: Codable, Identifiable, Hashable, Sendable {
    /// The hostname to match (nil for catch-all).
    let hostname: String?

    /// The path to match (optional).
    let path: String?

    /// The origin service to route to.
    let service: String

    /// Origin request settings specific to this rule.
    let originRequest: OriginRequestConfig?

    // MARK: - Identifiable Conformance

    /// A unique identifier for this rule.
    var id: String {
        "\(hostname ?? "*")\(path ?? ""):\(service)"
    }

    // MARK: - Computed Properties

    /// Whether this is a catch-all rule.
    var isCatchAll: Bool {
        hostname == nil
    }

    /// The display hostname.
    var displayHostname: String {
        hostname ?? "*"
    }

    /// A human-readable description of the rule.
    var description: String {
        if isCatchAll {
            return "Catch-all -> \(service)"
        } else if let path = path {
            return "\(displayHostname)\(path) -> \(service)"
        }
        return "\(displayHostname) -> \(service)"
    }

    /// The type of service (HTTP, HTTPS, TCP, etc.).
    var serviceType: ServiceType {
        ServiceType.from(service: service)
    }

    /// The port number if the service URL contains one.
    var servicePort: Int? {
        guard let url = URL(string: service) else { return nil }
        return url.port
    }

    /// The host portion of the service URL.
    var serviceHost: String? {
        guard let url = URL(string: service) else { return nil }
        return url.host
    }
}

// MARK: - ServiceType

/// The type of service a tunnel can route to.
enum ServiceType: String, CaseIterable, Sendable {
    case http = "HTTP"
    case https = "HTTPS"
    case tcp = "TCP"
    case ssh = "SSH"
    case rdp = "RDP"
    case httpStatus = "HTTP Status"
    case unix = "Unix Socket"
    case unknown = "Unknown"

    /// Determines the service type from a service URL string.
    static func from(service: String) -> ServiceType {
        let lowercased = service.lowercased()

        if lowercased.hasPrefix("http://") {
            return .http
        } else if lowercased.hasPrefix("https://") {
            return .https
        } else if lowercased.hasPrefix("tcp://") {
            return .tcp
        } else if lowercased.hasPrefix("ssh://") {
            return .ssh
        } else if lowercased.hasPrefix("rdp://") {
            return .rdp
        } else if lowercased.hasPrefix("http_status:") {
            return .httpStatus
        } else if lowercased.hasPrefix("unix:") || lowercased.hasPrefix("unix://") {
            return .unix
        }

        return .unknown
    }

    /// The URL scheme for this service type.
    var scheme: String {
        switch self {
        case .http: return "http"
        case .https: return "https"
        case .tcp: return "tcp"
        case .ssh: return "ssh"
        case .rdp: return "rdp"
        case .unix: return "unix"
        case .httpStatus, .unknown: return ""
        }
    }

    /// Default port for this service type.
    var defaultPort: Int {
        switch self {
        case .http: return 80
        case .https: return 443
        case .tcp: return 0 // No default
        case .ssh: return 22
        case .rdp: return 3389
        case .unix, .httpStatus, .unknown: return 0
        }
    }

    /// System image for this service type.
    var systemImage: String {
        switch self {
        case .http, .https:
            return "globe"
        case .tcp:
            return "network"
        case .ssh:
            return "terminal"
        case .rdp:
            return "desktopcomputer"
        case .unix:
            return "server.rack"
        case .httpStatus:
            return "number.circle"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - WarpRouting

/// WARP routing configuration.
struct WarpRouting: Codable, Sendable {
    /// Whether WARP routing is enabled.
    let enabled: Bool?
}

// MARK: - OriginRequestConfig

/// Configuration for requests to the origin server.
struct OriginRequestConfig: Codable, Hashable, Sendable {
    /// Connection timeout.
    let connectTimeout: Int?

    /// TLS connection timeout.
    let tlsTimeout: Int?

    /// TCP keep-alive timeout.
    let tcpKeepAlive: Int?

    /// Whether to skip TLS verification.
    let noTLSVerify: Bool?

    /// Whether to disable chunked transfer encoding.
    let disableChunkedEncoding: Bool?

    /// HTTP host header override.
    let httpHostHeader: String?

    /// Origin server name for TLS.
    let originServerName: String?

    /// Keep-alive connections.
    let keepAliveConnections: Int?

    /// Keep-alive timeout.
    let keepAliveTimeout: Int?

    /// HTTP/2 origin configuration.
    let http2Origin: Bool?

    /// Access configuration.
    let access: AccessConfig?

    enum CodingKeys: String, CodingKey {
        case connectTimeout = "connectTimeout"
        case tlsTimeout = "tlsTimeout"
        case tcpKeepAlive = "tcpKeepAlive"
        case noTLSVerify = "noTLSVerify"
        case disableChunkedEncoding = "disableChunkedEncoding"
        case httpHostHeader = "httpHostHeader"
        case originServerName = "originServerName"
        case keepAliveConnections = "keepAliveConnections"
        case keepAliveTimeout = "keepAliveTimeout"
        case http2Origin = "http2Origin"
        case access
    }
}

// MARK: - AccessConfig

/// Access configuration for origin requests.
struct AccessConfig: Codable, Hashable, Sendable {
    /// Whether Access is required.
    let required: Bool?

    /// The Access team name.
    let teamName: String?

    /// The audience tag.
    let audTag: [String]?

    enum CodingKeys: String, CodingKey {
        case required
        case teamName = "teamName"
        case audTag = "audTag"
    }
}

// MARK: - IngressRule Extensions

extension IngressRule {
    /// Creates a placeholder ingress rule for preview and testing.
    static var preview: IngressRule {
        IngressRule(
            hostname: "app.example.com",
            path: nil,
            service: "http://localhost:3000",
            originRequest: nil
        )
    }

    /// Creates a catch-all rule for preview and testing.
    static var catchAllPreview: IngressRule {
        IngressRule(
            hostname: nil,
            path: nil,
            service: "http_status:404",
            originRequest: nil
        )
    }
}

// MARK: - Update Configuration Request

/// Request body for updating tunnel configuration.
struct UpdateTunnelConfigurationRequest: Encodable {
    /// The configuration to update.
    let config: IngressConfig
}
