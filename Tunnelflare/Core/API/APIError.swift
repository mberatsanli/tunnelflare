//
//  APIError.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - APIError

/// Errors that can occur during API operations.
///
/// This enum categorizes all errors that the API client can encounter,
/// providing specific error types for common scenarios.
enum APIError: Error, LocalizedError, Sendable {

    // MARK: - Network Errors

    /// No internet connection available.
    case noConnection

    /// Request timed out.
    case timeout

    /// Network error occurred.
    case networkError(Error)

    // MARK: - Authentication Errors

    /// The request requires authentication but no token was available.
    case authenticationRequired

    /// The provided credentials are invalid or expired.
    case unauthorized

    /// Token refresh is required.
    case tokenRefreshRequired

    // MARK: - Client Errors

    /// The request was malformed.
    case badRequest(message: String)

    /// The requested resource was not found.
    case notFound

    /// The request was understood but cannot be processed.
    case unprocessableEntity(message: String)

    /// Resource already exists (conflict).
    case conflict(message: String)

    /// Rate limit exceeded.
    case rateLimited(retryAfter: TimeInterval?)

    // MARK: - Server Errors

    /// Server encountered an error.
    case serverError(statusCode: Int)

    /// Service is temporarily unavailable.
    case serviceUnavailable

    // MARK: - API Response Errors

    /// The API returned an error response.
    case apiError(errors: [CloudflareAPIError])

    /// Failed to parse the response.
    case decodingError(Error)

    /// Invalid response received.
    case invalidResponse

    /// Empty response when data was expected.
    case emptyResponse

    // MARK: - Request Building Errors

    /// Failed to build the request URL.
    case invalidURL

    /// Failed to encode the request body.
    case encodingError(Error)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network settings."
        case .timeout:
            return "The request timed out. Please try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationRequired:
            return "Authentication is required. Please log in."
        case .unauthorized:
            return "Your session has expired. Please log in again."
        case .tokenRefreshRequired:
            return "Your session needs to be refreshed."
        case .badRequest(let message):
            return "Invalid request: \(message)"
        case .notFound:
            return "The requested resource was not found."
        case .unprocessableEntity(let message):
            return "Unable to process request: \(message)"
        case .conflict(let message):
            return message
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limit exceeded. Please wait \(Int(seconds)) seconds before retrying."
            }
            return "Rate limit exceeded. Please wait before retrying."
        case .serverError(let statusCode):
            return "Server error (\(statusCode)). Please try again later."
        case .serviceUnavailable:
            return "Service is temporarily unavailable. Please try again later."
        case .apiError(let errors):
            return errors.map { $0.message }.joined(separator: "; ")
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .emptyResponse:
            return "No data received from the server."
        case .invalidURL:
            return "Failed to build request URL."
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return "Check your Wi-Fi or cellular connection and try again."
        case .timeout:
            return "The server may be busy. Try again in a few moments."
        case .networkError:
            return "Check your network connection and try again."
        case .authenticationRequired, .unauthorized:
            return "Click 'Login with Cloudflare' to authenticate."
        case .tokenRefreshRequired:
            return "The app will attempt to refresh your session automatically."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Wait \(Int(seconds)) seconds before making another request."
            }
            return "Wait a few seconds before making another request."
        case .serverError, .serviceUnavailable:
            return "This is usually temporary. Try again in a few minutes."
        case .apiError, .badRequest, .unprocessableEntity:
            return "Check your input and try again."
        case .conflict:
            return "Try using a different name."
        default:
            return nil
        }
    }

    // MARK: - Retry Logic

    /// Whether this error is transient and the request should be retried.
    var isRetryable: Bool {
        switch self {
        case .timeout, .networkError, .serviceUnavailable, .rateLimited:
            return true
        case .serverError(let statusCode):
            // 5xx errors except 501 (Not Implemented) are retryable
            return statusCode >= 500 && statusCode != 501
        default:
            return false
        }
    }

    /// Whether this error requires re-authentication.
    var requiresReauthentication: Bool {
        switch self {
        case .unauthorized, .authenticationRequired:
            return true
        default:
            return false
        }
    }

    /// The recommended delay before retrying, if applicable.
    var retryDelay: TimeInterval? {
        switch self {
        case .rateLimited(let retryAfter):
            return retryAfter ?? 5.0
        case .timeout, .networkError:
            return 2.0
        case .serverError, .serviceUnavailable:
            return 5.0
        default:
            return nil
        }
    }

    // MARK: - Factory Methods

    /// Creates an appropriate APIError from an HTTP status code.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code.
    ///   - data: Optional response data for parsing error details.
    /// - Returns: An appropriate APIError.
    static func from(statusCode: Int, data: Data? = nil) -> APIError {
        switch statusCode {
        case 400:
            return .badRequest(message: parseErrorMessage(from: data) ?? "Invalid request")
        case 401:
            return .unauthorized
        case 403:
            return .unauthorized
        case 404:
            return .notFound
        case 409:
            return .conflict(message: parseErrorMessage(from: data) ?? "A resource with this name already exists")
        case 422:
            return .unprocessableEntity(message: parseErrorMessage(from: data) ?? "Validation failed")
        case 429:
            // Try to parse Retry-After header from the response
            return .rateLimited(retryAfter: nil)
        case 500...599:
            if statusCode == 503 {
                return .serviceUnavailable
            }
            return .serverError(statusCode: statusCode)
        default:
            return .invalidResponse
        }
    }

    /// Creates an APIError from a URLError.
    ///
    /// - Parameter urlError: The URLError that occurred.
    /// - Returns: An appropriate APIError.
    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timeout
        default:
            return .networkError(urlError)
        }
    }

    // MARK: - Private Helpers

    private static func parseErrorMessage(from data: Data?) -> String? {
        guard let data = data else { return nil }
        do {
            let errorResponse = try JSONDecoder.cloudflareAPI.decode(APIErrorResponse.self, from: data)
            return errorResponse.errors.first?.message
        } catch {
            return nil
        }
    }
}

// MARK: - APIError Equatable

extension APIError: Equatable {
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.noConnection, .noConnection),
             (.timeout, .timeout),
             (.authenticationRequired, .authenticationRequired),
             (.unauthorized, .unauthorized),
             (.tokenRefreshRequired, .tokenRefreshRequired),
             (.notFound, .notFound),
             (.serviceUnavailable, .serviceUnavailable),
             (.invalidResponse, .invalidResponse),
             (.emptyResponse, .emptyResponse),
             (.invalidURL, .invalidURL):
            return true

        case (.badRequest(let lhsMsg), .badRequest(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.unprocessableEntity(let lhsMsg), .unprocessableEntity(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.conflict(let lhsMsg), .conflict(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.rateLimited(let lhsRetry), .rateLimited(let rhsRetry)):
            return lhsRetry == rhsRetry
        case (.apiError(let lhsErrors), .apiError(let rhsErrors)):
            return lhsErrors == rhsErrors

        default:
            return false
        }
    }
}
