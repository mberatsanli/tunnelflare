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
    ///
    /// `nil` for tunnels that have never had a remote configuration
    /// (the API returns `"config": null` for them).
    let config: IngressConfig?

    /// The source of the configuration.
    let source: String?

    /// Version of the configuration.
    let version: Int?
}

// MARK: - JSONValue

/// A generic JSON value used to round-trip API payloads without data loss.
///
/// The Cloudflare tunnel configuration contains many fields this app does
/// not model (e.g. `ipRules`, `proxyPort`, `bastionMode`). Decoding captures
/// the original JSON alongside the typed models so a later PUT can merge the
/// edited fields into the original object instead of re-serializing from
/// scratch, which would silently drop everything unmodeled.
indirect enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }

    /// Converts an `Encodable` value into a `JSONValue` using plain coders,
    /// so key names are preserved exactly as spelled in `CodingKeys`.
    init?<T: Encodable>(encoding value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        self = decoded
    }

    /// The wrapped dictionary when this value is an object, else `nil`.
    var objectValue: [String: JSONValue]? {
        if case .object(let object) = self { return object }
        return nil
    }
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

    /// The original config JSON as returned by the API.
    ///
    /// Preserved so fields the editor does not model or touch (global
    /// originRequest options, warp-routing extras, unknown keys) survive
    /// the GET -> PUT round-trip. See ``JSONValue``.
    let raw: JSONValue?

    enum CodingKeys: String, CodingKey {
        case ingress
        case warpRouting = "warp-routing"
        case originRequest = "originRequest"
    }

    init(
        ingress: [IngressRule],
        warpRouting: WarpRouting?,
        originRequest: OriginRequestConfig?,
        raw: JSONValue? = nil
    ) {
        self.ingress = ingress
        self.warpRouting = warpRouting
        self.originRequest = originRequest
        self.raw = raw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ingress = try container.decodeIfPresent([IngressRule].self, forKey: .ingress) ?? []
        warpRouting = try container.decodeIfPresent(WarpRouting.self, forKey: .warpRouting)
        originRequest = try container.decodeIfPresent(OriginRequestConfig.self, forKey: .originRequest)
        raw = try? JSONValue(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try mergedJSON().encode(to: encoder)
    }

    /// The config as JSON: the original raw object (when available) with the
    /// edited ingress rules merged in, so unmodeled fields are not clobbered.
    func mergedJSON() -> JSONValue {
        var object = raw?.objectValue ?? [:]

        object["ingress"] = .array(ingress.map { $0.mergedJSON() })

        // Only fall back to the typed models when the raw JSON has nothing
        // for these keys (e.g. configs built locally rather than decoded).
        if object["warp-routing"] == nil,
           let warpRouting = warpRouting,
           let json = JSONValue(encoding: warpRouting) {
            object["warp-routing"] = json
        }
        if object["originRequest"] == nil,
           let originRequest = originRequest,
           let json = JSONValue(encoding: originRequest) {
            object["originRequest"] = json
        }

        return .object(object)
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

    /// The rule's original JSON as returned by the API.
    ///
    /// Preserved so per-rule fields the editor does not model or touch
    /// survive the GET -> PUT round-trip. `nil` for rules created locally.
    let raw: JSONValue?

    init(
        hostname: String?,
        path: String?,
        service: String,
        originRequest: OriginRequestConfig?,
        raw: JSONValue? = nil
    ) {
        self.hostname = hostname
        self.path = path
        self.service = service
        self.originRequest = originRequest
        self.raw = raw
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case hostname
        case path
        case service
        case originRequest = "originRequest"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        service = try container.decode(String.self, forKey: .service)
        originRequest = try container.decodeIfPresent(OriginRequestConfig.self, forKey: .originRequest)
        raw = try? JSONValue(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try mergedJSON().encode(to: encoder)
    }

    /// The rule as JSON: the original raw object (when available) with the
    /// editable fields overlaid, so unmodeled per-rule keys are preserved.
    func mergedJSON() -> JSONValue {
        var object = raw?.objectValue ?? [:]

        if let hostname = hostname {
            object["hostname"] = .string(hostname)
        } else {
            object.removeValue(forKey: "hostname")
        }
        if let path = path {
            object["path"] = .string(path)
        } else {
            object.removeValue(forKey: "path")
        }
        object["service"] = .string(service)

        // The editor never modifies per-rule originRequest, so the raw copy
        // (when present) is authoritative; only encode the typed model for
        // locally created rules.
        if object["originRequest"] == nil,
           let originRequest = originRequest,
           let json = JSONValue(encoding: originRequest) {
            object["originRequest"] = json
        }

        return .object(object)
    }

    // MARK: - Hashable Conformance

    /// Equality ignores `raw`: two rules are the same when their editable
    /// fields match, regardless of round-trip bookkeeping.
    static func == (lhs: IngressRule, rhs: IngressRule) -> Bool {
        lhs.hostname == rhs.hostname
            && lhs.path == rhs.path
            && lhs.service == rhs.service
            && lhs.originRequest == rhs.originRequest
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(hostname)
        hasher.combine(path)
        hasher.combine(service)
        hasher.combine(originRequest)
    }

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
