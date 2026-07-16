//
//  Endpoint.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - HTTPMethod

/// HTTP methods used for API requests.
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

// MARK: - Endpoint Protocol

/// Protocol defining an API endpoint.
///
/// Each endpoint specifies its path, HTTP method, query parameters,
/// request body, and expected response type.
///
/// ## Example
/// ```swift
/// struct GetUserEndpoint: Endpoint {
///     typealias Response = User
///
///     let path = "user"
///     let method = HTTPMethod.get
/// }
/// ```
protocol Endpoint {
    /// The type of response expected from this endpoint.
    associatedtype Response: Decodable

    /// The path component of the endpoint (relative to base URL).
    var path: String { get }

    /// The HTTP method for this endpoint.
    var method: HTTPMethod { get }

    /// Query parameters to include in the request.
    var queryItems: [URLQueryItem]? { get }

    /// The request body, if any.
    var body: Encodable? { get }

    /// Builds a pre-encoded request body, taking precedence over `body`.
    ///
    /// Use when the payload must bypass the shared snake_case key strategy,
    /// e.g. to round-trip API JSON whose keys must be sent back verbatim.
    /// A thrown error fails the request build instead of silently sending
    /// a body-less request.
    func makeRawBody() throws -> Data?

    /// The decoder for this endpoint's response.
    ///
    /// Defaults to the shared Cloudflare decoder (snake_case conversion).
    /// Override with a plain decoder when the response embeds JSON that must
    /// be captured verbatim (key conversion would mangle unknown keys).
    var responseDecoder: JSONDecoder { get }

    /// Additional headers for this request.
    var headers: [String: String]? { get }

    /// Whether this endpoint requires authentication.
    var requiresAuthentication: Bool { get }
}

// MARK: - Endpoint Default Implementations

extension Endpoint {
    /// Default to no query items.
    var queryItems: [URLQueryItem]? { nil }

    /// Default to no body.
    var body: Encodable? { nil }

    /// Default to no pre-encoded body.
    func makeRawBody() throws -> Data? { nil }

    /// Default to the shared Cloudflare decoder.
    var responseDecoder: JSONDecoder { .cloudflareAPI }

    /// Default to no additional headers.
    var headers: [String: String]? { nil }

    /// Default to requiring authentication.
    var requiresAuthentication: Bool { true }

    /// Builds the full URL for this endpoint.
    ///
    /// - Parameter baseURL: The base URL to build from.
    /// - Returns: The complete URL for the endpoint.
    func buildURL(baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        components?.queryItems = queryItems?.isEmpty == true ? nil : queryItems
        return components?.url
    }

    /// Builds a URLRequest for this endpoint.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL to build from.
    ///   - accessToken: Optional access token for authentication.
    /// - Returns: A configured URLRequest, or nil if URL building fails.
    func buildRequest(baseURL: URL, accessToken: String? = nil) -> URLRequest? {
        guard let url = buildURL(baseURL: baseURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = APIConstants.requestTimeout

        // Set default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add authorization if available
        if let token = accessToken, requiresAuthentication {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add custom headers
        headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Encode body if present (a pre-encoded body takes precedence);
        // any encoding failure fails the request build
        do {
            if let rawBody = try makeRawBody() {
                request.httpBody = rawBody
            } else if let body = body {
                request.httpBody = try JSONEncoder.cloudflareAPI.encode(AnyEncodable(body))
            }
        } catch {
            return nil
        }

        return request
    }
}

// MARK: - AnyEncodable

/// Type-erased wrapper for Encodable values.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        _encode = wrapped.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Paginated Endpoint

/// Protocol for endpoints that support pagination.
protocol PaginatedEndpoint: Endpoint {
    /// The current page number.
    var page: Int { get }

    /// The number of results per page.
    var perPage: Int { get }
}

extension PaginatedEndpoint {
    /// Default page number.
    var page: Int { 1 }

    /// Default results per page.
    var perPage: Int { APIConstants.defaultPageSize }

    /// Query items including pagination.
    var paginationQueryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
    }
}
