//
//  AuthenticationManager.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

/// The main coordinator for authentication in the application.
///
/// `AuthenticationManager` handles all authentication-related operations including:
/// - API Token authentication
/// - Session management and persistence
/// - Token access for API requests
/// - Secure logout with credential cleanup
/// - Session restoration on app launch
///
/// ## Architecture
/// This is an actor-based class that ensures thread-safe access to authentication state.
/// It coordinates with `KeychainManager` for secure credential storage.
///
/// ## Usage
/// ```swift
/// let authManager = AuthenticationManager.shared
///
/// // Check authentication status
/// if await authManager.isAuthenticated {
///     // User is logged in
/// }
///
/// // Login with API Token
/// try await authManager.loginWithAPIToken("your-api-token")
///
/// // Get access token for API
/// if let token = try await authManager.getAccessToken() {
///     // Use token
/// }
///
/// // Logout
/// await authManager.logout()
/// ```
actor AuthenticationManager {

    // MARK: - Singleton

    /// Shared instance of the AuthenticationManager.
    static let shared = AuthenticationManager()

    // MARK: - Types

    /// Authentication method used.
    ///
    /// The raw value is persisted to the Keychain so `restoreSession` knows
    /// which credential path to restore.
    enum AuthMethod: String, Equatable {
        /// API Token authentication.
        case apiToken = "api-token"

        /// Cloudflare OAuth (Authorization Code + PKCE) authentication.
        case oauth = "oauth"
    }

    /// Authentication state.
    enum AuthState: Equatable {
        /// User is not authenticated.
        case unauthenticated

        /// Authentication is in progress.
        case authenticating

        /// User is authenticated.
        case authenticated(userId: String)
    }

    /// Events emitted by the authentication manager.
    enum Event {
        /// Authentication state changed.
        case stateChanged(AuthState)

        /// Authentication succeeded.
        case authenticationSucceeded(userId: String)

        /// Authentication failed.
        case authenticationFailed(Error)

        /// User logged out.
        case loggedOut

        /// Session was restored from Keychain.
        case sessionRestored
    }

    /// Delegate for receiving authentication events.
    protocol Delegate: AnyObject, Sendable {
        func authenticationManager(_ manager: AuthenticationManager, didEmit event: Event) async
    }

    // MARK: - Properties

    /// The current authentication state.
    private(set) var state: AuthState = .unauthenticated

    /// The Keychain manager for credential storage.
    private let keychainManager: KeychainManager

    /// Logger for authentication events.
    private let logger = Logger.auth

    /// Delegate for receiving events.
    private weak var delegate: (any Delegate)?

    /// The current user ID if authenticated.
    private var currentUserId: String?

    /// The current authentication method.
    private var authMethod: AuthMethod?

    // MARK: - Initialization

    /// Creates a new AuthenticationManager with dependencies.
    ///
    /// - Parameter keychainManager: The Keychain manager for credential storage.
    init(keychainManager: KeychainManager = .shared) {
        self.keychainManager = keychainManager
    }

    // MARK: - Public Methods

    /// Sets the delegate for receiving authentication events.
    ///
    /// - Parameter delegate: The delegate to set.
    func setDelegate(_ delegate: any Delegate) {
        self.delegate = delegate
    }

    /// Whether the user is currently authenticated.
    var isAuthenticated: Bool {
        if case .authenticated = state {
            return true
        }
        return false
    }

    /// Attempts to restore a previous session from Keychain.
    ///
    /// This should be called on app launch to check for existing credentials.
    /// Checks for API token in Keychain and restores session if found.
    ///
    /// - Returns: `true` if a session was restored, `false` otherwise.
    @discardableResult
    func restoreSession() async -> Bool {
        logger.info("Attempting to restore session")

        do {
            // Determine which method to restore. Fall back to API token for
            // sessions created before the auth method was persisted.
            let storedMethod = try await keychainManager.retrieveAuthMethod()

            if storedMethod == .oauth {
                if let tokens = try await keychainManager.retrieveOAuthTokens() {
                    // Restore if the token is still valid, or refreshable.
                    guard !tokens.isExpired() || tokens.refreshToken != nil else {
                        logger.info("Stored OAuth tokens are expired with no refresh token")
                        return false
                    }

                    logger.info("Found stored OAuth tokens, restoring session")

                    authMethod = .oauth
                    state = .authenticated(userId: "oauth-user")
                    currentUserId = "oauth-user"

                    logger.info("OAuth session restored successfully")
                    await delegate?.authenticationManager(self, didEmit: .sessionRestored)
                    await delegate?.authenticationManager(self, didEmit: .stateChanged(state))

                    return true
                }

                logger.info("No stored OAuth tokens found")
                return false
            }

            // Check for API token
            if let apiToken = try await keychainManager.retrieveAPIToken(), !apiToken.isEmpty {
                logger.info("Found stored API token, restoring session")

                authMethod = .apiToken
                state = .authenticated(userId: "api-token-user")
                currentUserId = "api-token-user"

                logger.info("API token session restored successfully")
                await delegate?.authenticationManager(self, didEmit: .sessionRestored)
                await delegate?.authenticationManager(self, didEmit: .stateChanged(state))

                return true
            }

            logger.info("No stored API token found")
            return false

        } catch {
            logger.error("Failed to restore session: \(error.localizedDescription)")
            return false
        }
    }

    /// Initiates login with Cloudflare OAuth (Authorization Code + PKCE).
    ///
    /// Runs the interactive OAuth flow, persists the resulting tokens and the
    /// auth method, and marks the user as authenticated.
    ///
    /// - Throws: ``OAuthError`` if the flow fails or is cancelled.
    func loginWithOAuth() async throws {
        guard state != .authenticating else {
            logger.warning("Login already in progress")
            return
        }

        logger.info("Starting OAuth login")
        state = .authenticating
        await delegate?.authenticationManager(self, didEmit: .stateChanged(state))

        do {
            // OAuthService is @MainActor; hop via the static orchestrator so no
            // non-Sendable value crosses the actor boundary.
            let tokens = try await OAuthService.performLogin()

            try await keychainManager.saveOAuthTokens(tokens)
            try await keychainManager.saveAuthMethod(.oauth)

            authMethod = .oauth
            state = .authenticated(userId: "oauth-user")
            currentUserId = "oauth-user"

            logger.info("OAuth login successful")
            await delegate?.authenticationManager(self, didEmit: .authenticationSucceeded(userId: "oauth-user"))
            await delegate?.authenticationManager(self, didEmit: .stateChanged(state))

        } catch {
            logger.error("OAuth login failed: \(error.localizedDescription)")
            state = .unauthenticated
            await delegate?.authenticationManager(self, didEmit: .authenticationFailed(error))
            await delegate?.authenticationManager(self, didEmit: .stateChanged(state))
            throw error
        }
    }

    /// Initiates login with an API token.
    ///
    /// This stores the API token and marks the user as authenticated.
    /// The token should be validated before calling this method.
    ///
    /// - Parameter token: The Cloudflare API token.
    /// - Throws: Error if login fails.
    func loginWithAPIToken(_ token: String) async throws {
        guard state != .authenticating else {
            logger.warning("Login already in progress")
            return
        }

        logger.info("Starting API token login")
        state = .authenticating
        await delegate?.authenticationManager(self, didEmit: .stateChanged(state))

        do {
            // Store the API token in Keychain
            try await keychainManager.saveAPIToken(token)
            try await keychainManager.saveAuthMethod(.apiToken)

            // Mark as authenticated with API token method
            authMethod = .apiToken
            state = .authenticated(userId: "api-token-user")
            currentUserId = "api-token-user"

            logger.info("API token login successful")
            await delegate?.authenticationManager(self, didEmit: .authenticationSucceeded(userId: "api-token-user"))
            await delegate?.authenticationManager(self, didEmit: .stateChanged(state))

        } catch {
            logger.error("API token login failed: \(error.localizedDescription)")
            state = .unauthenticated
            await delegate?.authenticationManager(self, didEmit: .authenticationFailed(error))
            await delegate?.authenticationManager(self, didEmit: .stateChanged(state))
            throw error
        }
    }

    /// Logs out the current user.
    ///
    /// This method:
    /// 1. Clears Keychain credentials
    /// 2. Resets authentication state
    func logout() async {
        logger.info("Logging out")

        // Clear credentials
        do {
            try await keychainManager.deleteAll()
        } catch {
            logger.error("Failed to clear Keychain: \(error.localizedDescription)")
        }

        // Reset state
        state = .unauthenticated
        currentUserId = nil
        authMethod = nil

        logger.info("Logout complete")
        await delegate?.authenticationManager(self, didEmit: .loggedOut)
        await delegate?.authenticationManager(self, didEmit: .stateChanged(state))
    }

    /// Gets the current access token for API requests.
    ///
    /// This method returns the stored API token for authenticated users.
    ///
    /// - Returns: The access token, or `nil` if not authenticated.
    /// - Throws: Error if token cannot be retrieved.
    func getAccessToken() async throws -> String? {
        guard isAuthenticated else {
            return nil
        }

        // Resolve the effective method (fall back to stored value if unset).
        var method = authMethod
        if method == nil {
            method = try? await keychainManager.retrieveAuthMethod()
        }

        switch method ?? .apiToken {
        case .apiToken:
            return try await keychainManager.retrieveAPIToken()

        case .oauth:
            return try await validOAuthAccessToken()
        }
    }

    /// Returns a valid OAuth access token, refreshing it if it has expired.
    ///
    /// If the token is expired and cannot be refreshed, OAuth credentials are
    /// cleared and the session is set unauthenticated so the caller sees login.
    ///
    /// - Returns: A currently valid access token.
    /// - Throws: ``OAuthError`` if no tokens are stored or refresh fails.
    private func validOAuthAccessToken() async throws -> String? {
        guard let tokens = try await keychainManager.retrieveOAuthTokens() else {
            await clearOAuthAndSignOut()
            throw OAuthError.noRefreshToken
        }

        // Still valid (with leeway) — use as-is.
        guard tokens.isExpired() else {
            return tokens.accessToken
        }

        guard let refreshToken = tokens.refreshToken else {
            logger.error("OAuth token expired and no refresh token is available")
            await clearOAuthAndSignOut()
            throw OAuthError.noRefreshToken
        }

        do {
            let response = try await OAuthService.performRefresh(refreshToken: refreshToken)
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
            let refreshed = OAuthTokens(
                accessToken: response.accessToken,
                // Some servers omit a new refresh token; keep the existing one.
                refreshToken: response.refreshToken ?? refreshToken,
                expiresAt: expiresAt
            )
            try await keychainManager.saveOAuthTokens(refreshed)
            logger.info("Refreshed OAuth access token")
            return refreshed.accessToken
        } catch {
            logger.error("OAuth refresh failed: \(error.localizedDescription)")
            await clearOAuthAndSignOut()
            throw OAuthError.refreshFailed
        }
    }

    /// Clears stored OAuth credentials and moves to the unauthenticated state.
    private func clearOAuthAndSignOut() async {
        try? await keychainManager.deleteOAuthTokens()
        state = .unauthenticated
        currentUserId = nil
        authMethod = nil
        await delegate?.authenticationManager(self, didEmit: .stateChanged(state))
    }

    /// Updates the authenticated user information.
    ///
    /// Called after fetching user info from the API.
    ///
    /// - Parameter userId: The user's ID.
    func updateAuthenticatedUser(userId: String) {
        guard isAuthenticated else { return }

        currentUserId = userId
        state = .authenticated(userId: userId)
        logger.info("Updated authenticated user: \(userId)")
    }
}

// MARK: - AuthenticationError

/// Errors that can occur during authentication operations.
enum AuthenticationError: LocalizedError {
    /// User is not authenticated.
    case notAuthenticated

    /// Authentication is required.
    case authenticationRequired

    /// A human-readable description of the error.
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please log in."
        case .authenticationRequired:
            return "Authentication is required to perform this action."
        }
    }

    /// Recovery suggestion for the error.
    var recoverySuggestion: String? {
        return "Enter your Cloudflare API Token to authenticate."
    }
}
