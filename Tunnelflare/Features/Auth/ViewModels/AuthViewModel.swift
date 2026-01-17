//
//  AuthViewModel.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI
import os.log

/// ViewModel for authentication views.
///
/// `AuthViewModel` manages the authentication UI state and coordinates with
/// `AuthenticationManager` to perform login/logout operations.
///
/// ## Features
/// - API Token login flow management
/// - Loading state tracking
/// - Error handling and display
/// - Organization selection
///
/// ## Usage
/// ```swift
/// @State private var viewModel = AuthViewModel()
///
/// LoginView()
///     .environment(viewModel)
/// ```
@Observable
@MainActor
final class AuthViewModel {

    // MARK: - Properties

    /// Whether a login operation is in progress.
    var isLoading: Bool = false

    /// The current error message to display.
    var errorMessage: String?

    /// Whether an error alert should be shown.
    var showError: Bool = false

    /// The list of available organizations.
    var organizations: [Organization] = []

    /// Whether the organization selector should be shown.
    var showOrganizationSelector: Bool = false

    /// The authentication manager.
    private let authManager: AuthenticationManager

    /// The app state for updating authentication status.
    private weak var appState: AppState?

    /// Logger for auth view model events.
    private let logger = Logger.auth

    // MARK: - Initialization

    /// Creates a new AuthViewModel.
    ///
    /// - Parameter authManager: The authentication manager to use.
    init(authManager: AuthenticationManager = .shared) {
        self.authManager = authManager
    }

    /// Sets the app state reference for updating authentication status.
    ///
    /// - Parameter appState: The app state to update on login/logout.
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    // MARK: - Public Methods

    /// Initiates login with a Cloudflare API token.
    ///
    /// This validates the token with the Cloudflare API and stores it securely.
    ///
    /// - Parameter token: The Cloudflare API token.
    func loginWithAPIToken(_ token: String) async {
        guard !isLoading else { return }
        guard !token.isEmpty else {
            errorMessage = "Please enter an API token."
            showError = true
            return
        }

        logger.info("Starting API token login from UI")
        isLoading = true
        errorMessage = nil

        do {
            // Validate the token by calling accounts endpoint and get organizations
            let accounts = try await validateAndFetchAccounts(token: token)

            // Token is valid, proceed with login
            try await authManager.loginWithAPIToken(token)
            logger.info("API token login successful from UI")

            // Fetch real user info from /user endpoint
            let user = await fetchUserInfo(token: token)

            // Update app state with authentication
            if let appState = appState {
                appState.setAuthenticated(user: user, organizations: accounts)
                logger.info("AppState updated - isAuthenticated: \(appState.isAuthenticated)")

                // Log user and organization info as JSON for debugging
                logAuthenticationInfo(user: user, organizations: accounts)
            } else {
                logger.warning("AppState not set - UI may not update")
            }

        } catch let error as APIError {
            logger.error("API error during token validation: \(error.localizedDescription)")
            handleAPIError(error)

        } catch {
            logger.error("Unexpected error during API token login: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    /// Validates an API token by fetching accounts from the Cloudflare API.
    ///
    /// - Parameter token: The token to validate.
    /// - Returns: The list of accounts the token has access to.
    /// - Throws: Error if the token is invalid.
    private func validateAndFetchAccounts(token: String) async throws -> [Organization] {
        // Try to fetch accounts to validate the token works
        // This is more reliable than the /verify endpoint which may require additional permissions
        let url = URL(string: "https://api.cloudflare.com/client/v4/accounts")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        logger.info("Validating API token by fetching accounts (token length: \(token.count))")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Log response for debugging
        let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode"
        logger.info("Token validation response: status=\(httpResponse.statusCode), body=\(responseString.prefix(500))")

        switch httpResponse.statusCode {
        case 200:
            // Token is valid - parse the accounts
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            do {
                let accountsResponse = try decoder.decode(AccountsResponse.self, from: data)
                if accountsResponse.success {
                    logger.info("API token validated successfully - found \(accountsResponse.result.count) accounts")
                    // Convert Account to Organization (they're the same type via typealias)
                    return accountsResponse.result
                }
                logger.error("Token validation returned 200 but success was not true")
                throw APIError.invalidResponse
            } catch {
                logger.error("Failed to decode accounts response: \(error.localizedDescription)")
                // Fallback: try to parse manually
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = json["success"] as? Bool, success,
                   let resultArray = json["result"] as? [[String: Any]] {
                    let accounts = resultArray.compactMap { dict -> Organization? in
                        guard let id = dict["id"] as? String,
                              let name = dict["name"] as? String else { return nil }
                        let type = dict["type"] as? String
                        return Organization(id: id, name: name, type: type, settings: nil, createdOn: nil)
                    }
                    logger.info("Parsed \(accounts.count) accounts manually")
                    return accounts
                }
                throw APIError.decodingError(error)
            }

        case 401:
            logger.error("Token validation failed with 401 - unauthorized")
            throw APIError.unauthorized

        case 403:
            logger.error("Token validation failed with 403 - forbidden (missing permissions)")
            throw APIError.unauthorized

        default:
            logger.error("Token validation failed with unexpected status \(httpResponse.statusCode)")
            throw APIError.from(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Response structure for accounts endpoint.
    private struct AccountsResponse: Decodable {
        let success: Bool
        let result: [Organization]
    }

    /// Response structure for user endpoint.
    private struct UserResponse: Decodable {
        let success: Bool
        let result: User
    }

    /// Fetches user information from the Cloudflare /user endpoint.
    ///
    /// - Parameter token: The API token.
    /// - Returns: The user info, or a placeholder if the request fails.
    private func fetchUserInfo(token: String) async -> User {
        let url = URL(string: "https://api.cloudflare.com/client/v4/user")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        logger.info("Fetching user info from /user endpoint")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.warning("Failed to fetch user info, using placeholder")
                return createPlaceholderUser()
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            let userResponse = try decoder.decode(UserResponse.self, from: data)
            if userResponse.success {
                logger.info("Successfully fetched user info: \(userResponse.result.email)")
                return userResponse.result
            }
        } catch {
            logger.error("Error fetching user info: \(error.localizedDescription)")
        }

        return createPlaceholderUser()
    }

    /// Creates a placeholder user when real user info is unavailable.
    private func createPlaceholderUser() -> User {
        User(
            id: "api-token-user",
            email: "API Token User",
            firstName: nil,
            lastName: nil,
            username: nil,
            twoFactorAuthenticationEnabled: nil,
            suspended: nil,
            createdOn: nil,
            modifiedOn: nil
        )
    }

    /// Logs out the current user.
    func logout() async {
        logger.info("Logging out from UI")

        await authManager.logout()

        // Clear local state
        organizations = []
        showOrganizationSelector = false
        errorMessage = nil

        // Update app state
        appState?.clearAuthentication()
    }

    /// Dismisses the current error.
    func dismissError() {
        errorMessage = nil
        showError = false
    }

    /// Selects an organization.
    ///
    /// - Parameter organization: The organization to select.
    func selectOrganization(_ organization: Organization) {
        logger.info("Selected organization: \(organization.name)")
        showOrganizationSelector = false

        // Persist selection
        UserDefaults.standard.set(organization.id, forKey: UserDefaultsKeys.selectedOrganizationId)
    }

    /// Checks if we have multiple organizations and should show selector.
    func checkOrganizations() {
        showOrganizationSelector = organizations.count > 1
    }

    // MARK: - Private Methods

    /// Logs user and organization information as JSON for debugging.
    private func logAuthenticationInfo(user: User, organizations: [Organization]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Log user info
        do {
            let userData = try encoder.encode(user)
            if let jsonString = String(data: userData, encoding: .utf8) {
                logger.info("📋 Authenticated User:\n\(jsonString)")
                print("📋 Authenticated User JSON:\n\(jsonString)")
            }
        } catch {
            logger.error("Failed to encode user: \(error.localizedDescription)")
        }

        // Log all organizations
        do {
            let orgsData = try encoder.encode(organizations)
            if let jsonString = String(data: orgsData, encoding: .utf8) {
                logger.info("🏢 Available Organizations (\(organizations.count)):\n\(jsonString)")
                print("🏢 Available Organizations (\(organizations.count)) JSON:\n\(jsonString)")
            }
        } catch {
            logger.error("Failed to encode organizations: \(error.localizedDescription)")
        }

        // Log selected organization if available
        if let selectedOrg = appState?.selectedOrganization {
            do {
                let orgData = try encoder.encode(selectedOrg)
                if let jsonString = String(data: orgData, encoding: .utf8) {
                    logger.info("✅ Selected Organization:\n\(jsonString)")
                    print("✅ Selected Organization JSON:\n\(jsonString)")
                }
            } catch {
                logger.error("Failed to encode selected organization: \(error.localizedDescription)")
            }
        }
    }

    /// Handles API-specific errors.
    private func handleAPIError(_ error: APIError) {
        switch error {
        case .unauthorized:
            errorMessage = "Invalid API token. Please check your token and try again.\n\nMake sure your token has Account:Read and Cloudflare Tunnel:Edit permissions."
            showError = true

        case .rateLimited:
            errorMessage = "Too many requests. Please wait a moment and try again."
            showError = true

        case .networkError, .noConnection:
            errorMessage = "Network error. Please check your internet connection and try again."
            showError = true

        case .timeout:
            errorMessage = "Request timed out. Please try again."
            showError = true

        case .serverError, .serviceUnavailable:
            errorMessage = "Cloudflare service is temporarily unavailable. Please try again later."
            showError = true

        default:
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
