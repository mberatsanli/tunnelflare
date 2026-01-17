//
//  APIResponse.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - APIResponse

/// Generic wrapper for Cloudflare API responses.
///
/// All Cloudflare API endpoints return responses in this format, containing
/// a success flag, the result data, and any errors or messages.
///
/// ## Example JSON
/// ```json
/// {
///   "success": true,
///   "result": { ... },
///   "errors": [],
///   "messages": []
/// }
/// ```
struct APIResponse<T: Decodable>: Decodable {
    /// Whether the request was successful.
    let success: Bool

    /// The result data from the API.
    let result: T

    /// Any errors returned by the API.
    let errors: [CloudflareAPIError]?

    /// Any informational messages from the API.
    let messages: [APIMessage]?

    /// Pagination information for list responses.
    let resultInfo: ResultInfo?

    enum CodingKeys: String, CodingKey {
        case success
        case result
        case errors
        case messages
        case resultInfo = "result_info"
    }
}

// MARK: - Error Response

/// Response wrapper for API error cases where result may be absent.
struct APIErrorResponse: Decodable {
    /// Whether the request was successful (will be false for errors).
    let success: Bool

    /// The errors returned by the API.
    let errors: [CloudflareAPIError]

    /// Any informational messages from the API.
    let messages: [APIMessage]?

    /// Combines all error messages into a single string.
    var combinedErrorMessage: String {
        errors.map { "\($0.code): \($0.message)" }.joined(separator: "; ")
    }
}

// MARK: - CloudflareAPIError

/// Error information from the Cloudflare API.
///
/// Each error contains a numeric code and a human-readable message.
struct CloudflareAPIError: Decodable, Equatable {
    /// The error code.
    let code: Int

    /// The error message.
    let message: String

    /// Additional error chain for nested errors.
    let errorChain: [CloudflareAPIError]?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case errorChain = "error_chain"
    }
}

extension CloudflareAPIError: LocalizedError {
    var errorDescription: String? {
        message
    }
}

// MARK: - APIMessage

/// Informational message from the Cloudflare API.
struct APIMessage: Decodable {
    /// The message code.
    let code: Int?

    /// The message content.
    let message: String
}

// MARK: - ResultInfo (Pagination)

/// Pagination information for list responses.
struct ResultInfo: Decodable {
    /// Current page number.
    let page: Int

    /// Number of results per page.
    let perPage: Int

    /// Total number of results.
    let totalCount: Int

    /// Total number of pages.
    let totalPages: Int

    /// Number of results in the current response.
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case totalCount = "total_count"
        case totalPages = "total_pages"
        case count
    }

    /// Whether there are more pages available.
    var hasMorePages: Bool {
        page < totalPages
    }

    /// The next page number, if available.
    var nextPage: Int? {
        hasMorePages ? page + 1 : nil
    }
}

// MARK: - Token Response

/// Response for tunnel token requests.
///
/// The token endpoint returns just the token string as the result.
struct TokenResponse: Decodable {
    /// Whether the request was successful.
    let success: Bool

    /// The tunnel token.
    let result: String

    /// Any errors returned by the API.
    let errors: [CloudflareAPIError]?
}

// MARK: - Empty Result

/// Used for API responses that return an empty result.
struct EmptyResult: Decodable {}

// MARK: - Delete Response

/// Response for delete operations.
struct DeleteResponse: Decodable {
    /// The ID of the deleted resource.
    let id: String
}

// MARK: - JSONDecoder Extension

extension JSONDecoder {
    /// Creates a JSONDecoder configured for Cloudflare API responses.
    ///
    /// This decoder is configured with:
    /// - `keyDecodingStrategy = .convertFromSnakeCase`
    /// - `dateDecodingStrategy = .iso8601` with fractional seconds support
    static var cloudflareAPI: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Custom date decoding to handle ISO8601 with fractional seconds
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: dateString) {
                return date
            }

            // Fall back to standard ISO8601
            if let date = ISO8601DateFormatter().date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }

        return decoder
    }
}

// MARK: - ISO8601DateFormatter Extension

extension ISO8601DateFormatter {
    /// ISO8601 formatter with fractional seconds support.
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        return formatter
    }()
}

// MARK: - JSONEncoder Extension

extension JSONEncoder {
    /// Creates a JSONEncoder configured for Cloudflare API requests.
    ///
    /// This encoder is configured with:
    /// - `keyEncodingStrategy = .convertToSnakeCase`
    /// - `dateEncodingStrategy = .iso8601`
    static var cloudflareAPI: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
