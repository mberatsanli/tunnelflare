//
//  AppError.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - AppError

/// Comprehensive error type hierarchy for the application.
///
/// AppError provides a unified error type that categorizes all errors the application
/// can encounter, with user-friendly descriptions and recovery suggestions.
///
/// ## Categories
/// - **Authentication**: Login, token, and session errors
/// - **API**: Network, response, and rate limiting errors
/// - **Tunnel**: Process management and cloudflared errors
/// - **Validation**: Input validation errors
/// - **General**: Miscellaneous application errors
///
/// ## Usage
/// ```swift
/// do {
///     try await someOperation()
/// } catch let error as AppError {
///     print(error.localizedDescription)
///     if let suggestion = error.recoverySuggestion {
///         print("Try: \(suggestion)")
///     }
/// }
/// ```
enum AppError: Error, LocalizedError, Sendable {

    // MARK: - Authentication Errors

    /// Authentication is required to perform the operation.
    case authenticationRequired

    /// Authentication failed with the given reason.
    case authenticationFailed(reason: String)

    /// The authentication token has expired.
    case tokenExpired

    /// Failed to refresh the authentication token.
    case tokenRefreshFailed(reason: String)

    /// No valid session exists.
    case noValidSession

    // MARK: - API Errors

    /// A network error occurred.
    case networkError(underlying: Error)

    /// The API returned an error response.
    case apiError(code: Int, message: String)

    /// Rate limit was exceeded.
    case rateLimited(retryAfter: TimeInterval?)

    /// The server returned an error.
    case serverError(statusCode: Int)

    /// The request was invalid.
    case badRequest(message: String)

    /// The requested resource was not found.
    case notFound(resource: String)

    /// The response could not be decoded.
    case decodingError(underlying: Error)

    /// The response was empty when data was expected.
    case emptyResponse

    /// The response was invalid.
    case invalidResponse

    // MARK: - Tunnel Errors

    /// The specified tunnel was not found.
    case tunnelNotFound(tunnelId: String)

    /// Failed to start the tunnel.
    case tunnelStartFailed(tunnelId: String, reason: String)

    /// Failed to stop the tunnel.
    case tunnelStopFailed(tunnelId: String, reason: String)

    /// The cloudflared binary was not found.
    case cloudflaredNotFound

    /// The cloudflared binary is not executable.
    case cloudflaredNotExecutable

    /// The cloudflared process crashed.
    case cloudflaredCrashed(tunnelId: String, exitCode: Int32)

    /// The tunnel token could not be retrieved.
    case tunnelTokenUnavailable(tunnelId: String)

    /// The tunnel is already running.
    case tunnelAlreadyRunning(tunnelId: String)

    /// The tunnel is not running.
    case tunnelNotRunning(tunnelId: String)

    // MARK: - Validation Errors

    /// Invalid tunnel name.
    case invalidTunnelName(reason: String)

    /// Invalid configuration.
    case invalidConfiguration(reason: String)

    /// Invalid URL format.
    case invalidURL(url: String)

    /// Invalid hostname format.
    case invalidHostname(hostname: String)

    // MARK: - General Errors

    /// No organization is selected.
    case noOrganizationSelected

    /// Services are not initialized.
    case servicesNotInitialized

    /// The operation was cancelled.
    case operationCancelled

    /// An unknown error occurred.
    case unknown(underlying: Error?)

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        // Authentication
        case .authenticationRequired:
            return "Authentication is required. Please log in to continue."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExpired:
            return "Your session has expired. Please log in again."
        case .tokenRefreshFailed(let reason):
            return "Failed to refresh your session: \(reason)"
        case .noValidSession:
            return "No valid session found. Please log in."

        // API
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Too many requests. Please wait \(Int(seconds)) seconds before trying again."
            }
            return "Too many requests. Please wait before trying again."
        case .serverError(let statusCode):
            return "Server error (\(statusCode)). Please try again later."
        case .badRequest(let message):
            return "Invalid request: \(message)"
        case .notFound(let resource):
            return "Resource not found: \(resource)"
        case .decodingError:
            return "Failed to process the server response."
        case .emptyResponse:
            return "The server returned an empty response."
        case .invalidResponse:
            return "Received an invalid response from the server."

        // Tunnel
        case .tunnelNotFound(let tunnelId):
            return "Tunnel not found: \(tunnelId)"
        case .tunnelStartFailed(let tunnelId, let reason):
            return "Failed to start tunnel '\(tunnelId)': \(reason)"
        case .tunnelStopFailed(let tunnelId, let reason):
            return "Failed to stop tunnel '\(tunnelId)': \(reason)"
        case .cloudflaredNotFound:
            return "cloudflared binary not found. Please install cloudflared or specify a custom path in Settings."
        case .cloudflaredNotExecutable:
            return "cloudflared binary is not executable."
        case .cloudflaredCrashed(let tunnelId, let exitCode):
            return "Tunnel '\(tunnelId)' crashed unexpectedly (exit code: \(exitCode))."
        case .tunnelTokenUnavailable(let tunnelId):
            return "Could not retrieve token for tunnel '\(tunnelId)'."
        case .tunnelAlreadyRunning(let tunnelId):
            return "Tunnel '\(tunnelId)' is already running."
        case .tunnelNotRunning(let tunnelId):
            return "Tunnel '\(tunnelId)' is not running."

        // Validation
        case .invalidTunnelName(let reason):
            return "Invalid tunnel name: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidHostname(let hostname):
            return "Invalid hostname: \(hostname)"

        // General
        case .noOrganizationSelected:
            return "No organization selected. Please select an organization."
        case .servicesNotInitialized:
            return "Application services are not ready. Please try again."
        case .operationCancelled:
            return "The operation was cancelled."
        case .unknown(let underlying):
            if let error = underlying {
                return "An unexpected error occurred: \(error.localizedDescription)"
            }
            return "An unexpected error occurred."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        // Authentication
        case .authenticationRequired, .tokenExpired, .noValidSession:
            return "Enter your Cloudflare API Token to authenticate."
        case .authenticationFailed, .tokenRefreshFailed:
            return "Check your credentials and try again. If the problem persists, contact support."

        // API
        case .networkError:
            return "Check your internet connection and try again."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Wait \(Int(seconds)) seconds before making another request."
            }
            return "Wait a few seconds before making another request."
        case .serverError, .emptyResponse, .invalidResponse:
            return "This is usually temporary. Try again in a few moments."
        case .badRequest, .decodingError:
            return "Check your input and try again."
        case .notFound:
            return "The requested item may have been deleted. Try refreshing the list."
        case .apiError:
            return "Check your input and try again. If the problem persists, contact support."

        // Tunnel
        case .tunnelNotFound:
            return "The tunnel may have been deleted. Try refreshing the tunnel list."
        case .tunnelStartFailed, .tunnelStopFailed:
            return "Check the tunnel logs for more details."
        case .cloudflaredNotFound:
            return "Install cloudflared via Homebrew (brew install cloudflared) or specify a custom path in Settings."
        case .cloudflaredNotExecutable:
            return "Check the file permissions or specify a different cloudflared path in Settings."
        case .cloudflaredCrashed:
            return "Check the tunnel logs for details. You can restart the tunnel to try again."
        case .tunnelTokenUnavailable:
            return "Try refreshing the tunnel list. You may need to delete and recreate the tunnel."
        case .tunnelAlreadyRunning:
            return "The tunnel is already running. Stop it first if you want to restart."
        case .tunnelNotRunning:
            return "Start the tunnel first before performing this operation."

        // Validation
        case .invalidTunnelName:
            return "Tunnel names must be 3-63 characters, start with a letter, end with a letter or number, and contain only lowercase letters, numbers, and hyphens."
        case .invalidConfiguration:
            return "Review your configuration and correct any errors."
        case .invalidURL:
            return "Enter a valid URL (e.g., http://localhost:3000)."
        case .invalidHostname:
            return "Enter a valid hostname (e.g., app.example.com)."

        // General
        case .noOrganizationSelected:
            return "Select an organization from the organization picker."
        case .servicesNotInitialized:
            return "Wait a moment and try again, or restart the application."
        case .operationCancelled:
            return nil
        case .unknown:
            return "Try again. If the problem persists, restart the application."
        }
    }

    // MARK: - Error Classification

    /// Whether this error is transient and the operation should be retried.
    var isRetryable: Bool {
        switch self {
        case .networkError, .serverError, .rateLimited, .emptyResponse:
            return true
        case .cloudflaredCrashed:
            return true
        default:
            return false
        }
    }

    /// Whether this error requires re-authentication.
    var requiresReauthentication: Bool {
        switch self {
        case .authenticationRequired, .tokenExpired, .noValidSession, .tokenRefreshFailed:
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
        case .networkError:
            return 2.0
        case .serverError:
            return 5.0
        case .cloudflaredCrashed:
            return 3.0
        default:
            return nil
        }
    }

    /// The error category for logging and analytics.
    var category: ErrorCategory {
        switch self {
        case .authenticationRequired, .authenticationFailed, .tokenExpired,
             .tokenRefreshFailed, .noValidSession:
            return .authentication
        case .networkError, .apiError, .rateLimited, .serverError, .badRequest,
             .notFound, .decodingError, .emptyResponse, .invalidResponse:
            return .api
        case .tunnelNotFound, .tunnelStartFailed, .tunnelStopFailed,
             .cloudflaredNotFound, .cloudflaredNotExecutable, .cloudflaredCrashed,
             .tunnelTokenUnavailable, .tunnelAlreadyRunning, .tunnelNotRunning:
            return .tunnel
        case .invalidTunnelName, .invalidConfiguration, .invalidURL, .invalidHostname:
            return .validation
        case .noOrganizationSelected, .servicesNotInitialized, .operationCancelled, .unknown:
            return .general
        }
    }

    /// Error categories for classification.
    enum ErrorCategory: String, Sendable {
        case authentication
        case api
        case tunnel
        case validation
        case general
    }
}

// MARK: - Conversion from Other Error Types

extension AppError {

    /// Creates an AppError from an APIError.
    ///
    /// - Parameter apiError: The APIError to convert.
    /// - Returns: The corresponding AppError.
    static func from(_ apiError: APIError) -> AppError {
        switch apiError {
        case .noConnection:
            return .networkError(underlying: apiError)
        case .timeout:
            return .networkError(underlying: apiError)
        case .networkError(let error):
            return .networkError(underlying: error)
        case .authenticationRequired:
            return .authenticationRequired
        case .unauthorized:
            return .tokenExpired
        case .tokenRefreshRequired:
            return .tokenExpired
        case .badRequest(let message):
            return .badRequest(message: message)
        case .notFound:
            return .notFound(resource: "resource")
        case .unprocessableEntity(let message):
            return .badRequest(message: message)
        case .conflict(let message):
            return .badRequest(message: message)
        case .rateLimited(let retryAfter):
            return .rateLimited(retryAfter: retryAfter)
        case .serverError(let statusCode):
            return .serverError(statusCode: statusCode)
        case .serviceUnavailable:
            return .serverError(statusCode: 503)
        case .apiError(let errors):
            if let first = errors.first {
                return .apiError(code: first.code, message: first.message)
            }
            return .apiError(code: 0, message: "Unknown API error")
        case .decodingError(let error):
            return .decodingError(underlying: error)
        case .invalidResponse:
            return .invalidResponse
        case .emptyResponse:
            return .emptyResponse
        case .invalidURL:
            return .invalidURL(url: "unknown")
        case .encodingError(let error):
            return .badRequest(message: error.localizedDescription)
        }
    }

    /// Creates an AppError from an AuthenticationError.
    ///
    /// - Parameter authError: The AuthenticationError to convert.
    /// - Returns: The corresponding AppError.
    static func from(_ authError: AuthenticationError) -> AppError {
        switch authError {
        case .notAuthenticated:
            return .authenticationRequired
        case .authenticationRequired:
            return .authenticationRequired
        }
    }

    /// Creates an AppError from a CloudflaredError.
    ///
    /// - Parameters:
    ///   - cloudflaredError: The CloudflaredError to convert.
    ///   - tunnelId: The tunnel ID if available.
    /// - Returns: The corresponding AppError.
    static func from(_ cloudflaredError: CloudflaredError, tunnelId: String? = nil) -> AppError {
        switch cloudflaredError {
        case .binaryNotFound:
            return .cloudflaredNotFound
        case .versionCheckFailed:
            return .cloudflaredNotExecutable
        case .startFailed(let reason):
            return .tunnelStartFailed(tunnelId: tunnelId ?? "unknown", reason: reason)
        case .processTerminated(let exitCode):
            return .cloudflaredCrashed(tunnelId: tunnelId ?? "unknown", exitCode: exitCode)
        case .quickTunnelURLTimeout:
            return .tunnelStartFailed(
                tunnelId: tunnelId ?? "unknown",
                reason: cloudflaredError.localizedDescription
            )
        }
    }

    /// Creates an AppError from any Error.
    ///
    /// - Parameter error: The error to convert.
    /// - Returns: The corresponding AppError.
    static func from(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        if let apiError = error as? APIError {
            return from(apiError)
        }
        if let authError = error as? AuthenticationError {
            return from(authError)
        }
        if let cloudflaredError = error as? CloudflaredError {
            return from(cloudflaredError)
        }
        return .unknown(underlying: error)
    }
}

// MARK: - Equatable

extension AppError: Equatable {
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        // Authentication
        case (.authenticationRequired, .authenticationRequired),
             (.tokenExpired, .tokenExpired),
             (.noValidSession, .noValidSession):
            return true
        case (.authenticationFailed(let lhsReason), .authenticationFailed(let rhsReason)):
            return lhsReason == rhsReason
        case (.tokenRefreshFailed(let lhsReason), .tokenRefreshFailed(let rhsReason)):
            return lhsReason == rhsReason

        // API
        case (.networkError, .networkError):
            return true // Can't compare underlying errors
        case (.apiError(let lhsCode, let lhsMsg), .apiError(let rhsCode, let rhsMsg)):
            return lhsCode == rhsCode && lhsMsg == rhsMsg
        case (.rateLimited(let lhsRetry), .rateLimited(let rhsRetry)):
            return lhsRetry == rhsRetry
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.badRequest(let lhsMsg), .badRequest(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.notFound(let lhsResource), .notFound(let rhsResource)):
            return lhsResource == rhsResource
        case (.decodingError, .decodingError),
             (.emptyResponse, .emptyResponse),
             (.invalidResponse, .invalidResponse):
            return true

        // Tunnel
        case (.tunnelNotFound(let lhsId), .tunnelNotFound(let rhsId)):
            return lhsId == rhsId
        case (.tunnelStartFailed(let lhsId, let lhsReason), .tunnelStartFailed(let rhsId, let rhsReason)):
            return lhsId == rhsId && lhsReason == rhsReason
        case (.tunnelStopFailed(let lhsId, let lhsReason), .tunnelStopFailed(let rhsId, let rhsReason)):
            return lhsId == rhsId && lhsReason == rhsReason
        case (.cloudflaredNotFound, .cloudflaredNotFound),
             (.cloudflaredNotExecutable, .cloudflaredNotExecutable):
            return true
        case (.cloudflaredCrashed(let lhsId, let lhsCode), .cloudflaredCrashed(let rhsId, let rhsCode)):
            return lhsId == rhsId && lhsCode == rhsCode
        case (.tunnelTokenUnavailable(let lhsId), .tunnelTokenUnavailable(let rhsId)):
            return lhsId == rhsId
        case (.tunnelAlreadyRunning(let lhsId), .tunnelAlreadyRunning(let rhsId)):
            return lhsId == rhsId
        case (.tunnelNotRunning(let lhsId), .tunnelNotRunning(let rhsId)):
            return lhsId == rhsId

        // Validation
        case (.invalidTunnelName(let lhsReason), .invalidTunnelName(let rhsReason)):
            return lhsReason == rhsReason
        case (.invalidConfiguration(let lhsReason), .invalidConfiguration(let rhsReason)):
            return lhsReason == rhsReason
        case (.invalidURL(let lhsURL), .invalidURL(let rhsURL)):
            return lhsURL == rhsURL
        case (.invalidHostname(let lhsHost), .invalidHostname(let rhsHost)):
            return lhsHost == rhsHost

        // General
        case (.noOrganizationSelected, .noOrganizationSelected),
             (.servicesNotInitialized, .servicesNotInitialized),
             (.operationCancelled, .operationCancelled):
            return true
        case (.unknown, .unknown):
            return true // Can't compare underlying errors

        default:
            return false
        }
    }
}
