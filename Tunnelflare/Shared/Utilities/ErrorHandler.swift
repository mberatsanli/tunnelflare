//
//  ErrorHandler.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI
import os.log

// MARK: - ErrorHandler

/// Centralized error handling service for the application.
///
/// ErrorHandler provides strategies for handling different types of errors,
/// including automatic retries and user notification.
///
/// ## Usage
/// ```swift
/// let handler = ErrorHandler.shared
///
/// // Handle an error with appropriate strategy
/// let result = await handler.handle(error, context: .api)
///
/// // Retry an operation with automatic error handling
/// let data = try await handler.withRetry(maxAttempts: 3) {
///     try await apiClient.fetchTunnels()
/// }
/// ```
actor ErrorHandler {

    // MARK: - Singleton

    /// Shared instance of the ErrorHandler.
    static let shared = ErrorHandler()

    // MARK: - Types

    /// Context in which an error occurred.
    enum ErrorContext: String, Sendable {
        /// Error occurred during API operations.
        case api
        /// Error occurred during process management.
        case process
        /// Error occurred during authentication.
        case authentication
        /// Error occurred during validation.
        case validation
        /// Error occurred in general operations.
        case general
    }

    /// Result of handling an error.
    enum HandlingResult: Sendable {
        /// The error was handled, retry the operation.
        case retry(after: TimeInterval)
        /// The error requires re-authentication.
        case reauthenticate
        /// Show an alert to the user.
        case showAlert(title: String, message: String, actions: [AlertAction])
        /// Show a banner notification.
        case showBanner(message: String, isError: Bool)
        /// Log the error and continue.
        case logAndContinue
        /// The error is fatal, stop the operation.
        case fatal(error: AppError)
    }

    /// Action for an error alert.
    struct AlertAction: Sendable {
        let title: String
        let role: ActionRole
        let handler: @Sendable () async -> Void

        enum ActionRole: Sendable {
            case cancel
            case destructive
            case primary
        }

        static func cancel(title: String = "Cancel") -> AlertAction {
            AlertAction(title: title, role: .cancel, handler: {})
        }

        static func primary(title: String, handler: @escaping @Sendable () async -> Void) -> AlertAction {
            AlertAction(title: title, role: .primary, handler: handler)
        }

        static func destructive(title: String, handler: @escaping @Sendable () async -> Void) -> AlertAction {
            AlertAction(title: title, role: .destructive, handler: handler)
        }
    }

    // MARK: - Properties

    /// Logger for error handling.
    private let logger = Logger.app

    /// Authentication manager for re-authentication handling.
    private weak var authManager: AuthenticationManager?

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    /// Configures the error handler with dependencies.
    ///
    /// - Parameter authManager: The authentication manager.
    func configure(authManager: AuthenticationManager) {
        self.authManager = authManager
    }

    // MARK: - Error Handling

    /// Handles an error and returns the appropriate action.
    ///
    /// - Parameters:
    ///   - error: The error to handle.
    ///   - context: The context in which the error occurred.
    /// - Returns: The handling result indicating what action to take.
    func handle(_ error: Error, context: ErrorContext) async -> HandlingResult {
        let appError = AppError.from(error)

        // Log the error
        logError(appError, context: context)

        // Determine handling strategy based on error type
        switch appError {
        // Authentication errors
        case .authenticationRequired, .tokenExpired, .noValidSession:
            return .reauthenticate

        case .tokenRefreshFailed:
            // Token refresh is not supported with API tokens, require re-authentication
            return .reauthenticate

        // Retryable API errors
        case .rateLimited(let retryAfter):
            return .retry(after: retryAfter ?? 5.0)

        case .networkError:
            if appError.isRetryable {
                return .retry(after: appError.retryDelay ?? 2.0)
            }
            return .showAlert(
                title: "Network Error",
                message: appError.localizedDescription,
                actions: [
                    .primary(title: "Retry", handler: {}),
                    .cancel()
                ]
            )

        case .serverError:
            if appError.isRetryable {
                return .retry(after: appError.retryDelay ?? 5.0)
            }
            return .showBanner(message: appError.localizedDescription, isError: true)

        // Tunnel errors
        case .cloudflaredCrashed:
            return .showAlert(
                title: "Tunnel Crashed",
                message: appError.localizedDescription,
                actions: [
                    .primary(title: "View Logs", handler: {}),
                    .primary(title: "Restart", handler: {}),
                    .cancel()
                ]
            )

        case .cloudflaredNotFound:
            return .showAlert(
                title: "cloudflared Not Found",
                message: appError.localizedDescription,
                actions: [
                    .primary(title: "Open Settings", handler: {}),
                    .cancel()
                ]
            )

        case .tunnelStartFailed, .tunnelStopFailed:
            return .showAlert(
                title: "Tunnel Error",
                message: appError.localizedDescription,
                actions: [
                    .primary(title: "View Logs", handler: {}),
                    .cancel()
                ]
            )

        // Validation errors - show inline
        case .invalidTunnelName, .invalidConfiguration, .invalidURL, .invalidHostname:
            return .logAndContinue

        // API errors
        case .badRequest, .apiError:
            return .showBanner(message: appError.localizedDescription, isError: true)

        case .notFound:
            return .showBanner(message: appError.localizedDescription, isError: true)

        // General errors
        case .noOrganizationSelected:
            return .showAlert(
                title: "No Organization Selected",
                message: appError.localizedDescription,
                actions: [.cancel(title: "OK")]
            )

        case .servicesNotInitialized:
            return .retry(after: 1.0)

        case .operationCancelled:
            return .logAndContinue

        default:
            return .showBanner(message: appError.localizedDescription, isError: true)
        }
    }

    // MARK: - Retry Logic

    /// Executes an operation with automatic retry on transient errors.
    ///
    /// - Parameters:
    ///   - maxAttempts: Maximum number of attempts (default: 3).
    ///   - initialDelay: Initial delay between retries (default: 1 second).
    ///   - maxDelay: Maximum delay between retries (default: 30 seconds).
    ///   - operation: The operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: The last error if all retries fail.
    func withRetry<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 30.0,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var currentDelay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let appError = AppError.from(error)

                // Don't retry non-retryable errors
                guard appError.isRetryable else {
                    throw error
                }

                // Check if we should retry
                if attempt < maxAttempts {
                    let delay = appError.retryDelay ?? currentDelay

                    logger.info("Retry attempt \(attempt)/\(maxAttempts) after \(delay)s: \(appError.localizedDescription)")

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                    // Exponential backoff with jitter
                    currentDelay = min(currentDelay * 2 + Double.random(in: 0...1), maxDelay)
                }
            }
        }

        throw lastError ?? AppError.unknown(underlying: nil)
    }

    // MARK: - Error Logging

    /// Logs an error with appropriate level and context.
    ///
    /// - Parameters:
    ///   - error: The error to log.
    ///   - context: The context in which the error occurred.
    private func logError(_ error: AppError, context: ErrorContext) {
        let category = error.category
        let message = "[\(context.rawValue)/\(category.rawValue)] \(error.localizedDescription)"

        switch error {
        case .operationCancelled:
            logger.debug("\(message)")
        case .invalidTunnelName, .invalidConfiguration, .invalidURL, .invalidHostname:
            logger.info("\(message)")
        case .networkError, .rateLimited, .serverError:
            logger.warning("\(message)")
        default:
            logger.error("\(message)")
        }
    }
}

// MARK: - Error Presentation Helpers

/// Presentation style for errors.
enum ErrorPresentationStyle: Sendable {
    /// Show error inline (e.g., below a form field).
    case inline
    /// Show error as a dismissible alert.
    case alert
    /// Show error as a non-blocking banner.
    case banner
    /// Show error as a system notification.
    case notification
}

/// Helper for determining how to present errors.
struct ErrorPresenter {

    /// Determines the best presentation style for an error.
    ///
    /// - Parameter error: The error to present.
    /// - Returns: The recommended presentation style.
    static func style(for error: AppError) -> ErrorPresentationStyle {
        switch error.category {
        case .validation:
            return .inline
        case .authentication:
            return .alert
        case .tunnel:
            // Crashes should be notifications
            if case .cloudflaredCrashed = error {
                return .notification
            }
            return .alert
        case .api:
            // Network errors can be banners
            if case .networkError = error {
                return .banner
            }
            if case .rateLimited = error {
                return .banner
            }
            return .alert
        case .general:
            return .banner
        }
    }

    /// Gets the icon name for an error.
    ///
    /// - Parameter error: The error.
    /// - Returns: SF Symbol name for the error.
    static func iconName(for error: AppError) -> String {
        switch error.category {
        case .authentication:
            return "person.crop.circle.badge.exclamationmark"
        case .api:
            return "network.slash"
        case .tunnel:
            return "tunnel.fill"
        case .validation:
            return "exclamationmark.circle"
        case .general:
            return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - View Modifier for Error Handling

/// View modifier that provides error handling capabilities.
struct ErrorHandlingModifier: ViewModifier {

    /// Binding to the current error.
    @Binding var error: AppError?

    /// Whether to show the error alert.
    @State private var showAlert = false

    /// The current error for display.
    @State private var displayError: AppError?

    func body(content: Content) -> some View {
        content
            .onChange(of: error) { _, newError in
                if let newError = newError {
                    displayError = newError
                    let style = ErrorPresenter.style(for: newError)
                    if style == .alert {
                        showAlert = true
                    }
                }
            }
            .alert(
                "Error",
                isPresented: $showAlert,
                presenting: displayError
            ) { _ in
                Button("OK") {
                    error = nil
                    displayError = nil
                }
            } message: { error in
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.localizedDescription)
                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .foregroundColor(.secondary)
                    }
                }
            }
    }
}

extension View {
    /// Adds error handling to a view.
    ///
    /// - Parameter error: Binding to the error to handle.
    /// - Returns: A view with error handling.
    func handleError(_ error: Binding<AppError?>) -> some View {
        modifier(ErrorHandlingModifier(error: error))
    }
}

// MARK: - Error Banner View

/// A banner view for displaying non-blocking errors.
struct ErrorBannerView: View {
    let error: AppError
    let onDismiss: () -> Void
    var onRetry: (() async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: ErrorPresenter.iconName(for: error))
                .font(.headline)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onRetry = onRetry, error.isRetryable {
                Button(action: {
                    performRetry(onRetry)
                }) {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Retry")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRetrying)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func performRetry(_ action: @escaping () async -> Void) {
        isRetrying = true
        Task {
            await action()
            await MainActor.run {
                isRetrying = false
            }
        }
    }
}
