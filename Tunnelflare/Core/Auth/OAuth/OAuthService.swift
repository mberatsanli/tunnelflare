//
//  OAuthService.swift
//  Tunnelflare
//
//  Created on 2026-07-15.
//  Copyright 2026. All rights reserved.
//

import AppKit
import Foundation
import Network
import os.log

/// Drives the OAuth 2.0 Authorization Code + PKCE flow against Cloudflare.
///
/// This is a public client: it uses PKCE (S256) and never embeds a client
/// secret. The flow is:
/// 1. ``discover()`` — fetch RFC 8414 metadata (authorize/token endpoints).
/// 2. ``authorize(metadata:)`` — start an RFC 8252 loopback listener, open the
///    system browser, and receive the authorization code on the callback.
/// 3. ``exchange(code:verifier:metadata:)`` — swap the code for tokens.
///
/// ``login()`` orchestrates all three. ``refresh(refreshToken:metadata:)``
/// renews an expired access token.
///
/// ## Redirect transport
/// Cloudflare's OAuth client registration rejects custom URL schemes, so the
/// app uses a loopback redirect (`http://127.0.0.1:<port>/callback`, RFC 8252)
/// instead of `ASWebAuthenticationSession`'s `callbackURLScheme`. A local
/// `NWListener` is started before the browser opens and torn down once the
/// callback arrives.
@MainActor
final class OAuthService: NSObject {

    // MARK: - Properties

    /// Logger for OAuth events.
    private let logger = Logger.auth

    /// The URL session used for discovery and token requests.
    private let urlSession: URLSession

    // MARK: - Initialization

    /// Creates a new OAuth service.
    ///
    /// - Parameter urlSession: The URL session for network calls. Defaults to
    ///   `.shared`.
    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        super.init()
    }

    // MARK: - Orchestration

    /// Runs the full OAuth login flow and returns persisted-ready tokens.
    ///
    /// - Returns: The access/refresh tokens with an absolute expiry `Date`.
    /// - Throws: ``OAuthError`` if any step fails.
    func login() async throws -> OAuthTokens {
        try assertConfigured()

        let metadata = try await discover()
        let (code, verifier) = try await authorize(metadata: metadata)
        let response = try await exchange(code: code, verifier: verifier, metadata: metadata)

        let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        return OAuthTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: expiresAt
        )
    }

    /// Discovers metadata and refreshes an access token in one main-actor hop.
    ///
    /// A convenience for callers on other actors (e.g. `AuthenticationManager`)
    /// so no non-`Sendable` `OAuthService` instance crosses an actor boundary.
    ///
    /// - Parameter refreshToken: The stored refresh token.
    /// - Returns: The fresh token response.
    /// - Throws: ``OAuthError`` if discovery or refresh fails.
    static func performRefresh(refreshToken: String) async throws -> OAuthTokenResponse {
        let service = OAuthService()
        let metadata = try await service.discover()
        return try await service.refresh(refreshToken: refreshToken, metadata: metadata)
    }

    /// Runs the full login flow in one main-actor hop.
    ///
    /// - Returns: The persisted-ready ``OAuthTokens``.
    /// - Throws: ``OAuthError`` if any step fails.
    static func performLogin() async throws -> OAuthTokens {
        try await OAuthService().login()
    }

    // MARK: - Discovery

    /// Fetches the authorization-server metadata from the discovery endpoint.
    ///
    /// - Returns: The decoded ``OAuthServerMetadata``.
    /// - Throws: ``OAuthError/discoveryFailed`` on network or decode failure.
    func discover() async throws -> OAuthServerMetadata {
        // Cloudflare does not serve a fetchable RFC 8414 metadata document for
        // third-party clients, so the endpoints are pinned in OAuthConstants.
        OAuthServerMetadata(
            authorizationEndpoint: OAuthConstants.authorizationEndpoint,
            tokenEndpoint: OAuthConstants.tokenEndpoint
        )
    }

    // MARK: - Authorization

    /// Opens the system browser and returns the authorization code.
    ///
    /// Builds the authorize URL with PKCE + a random `state`, starts the
    /// loopback listener, opens the URL in the default browser, and verifies the
    /// returned state.
    ///
    /// - Parameter metadata: The discovered server metadata.
    /// - Returns: The authorization `code` and the PKCE `verifier` used.
    /// - Throws: ``OAuthError`` on cancel, listener failure, or invalid callback.
    func authorize(metadata: OAuthServerMetadata) async throws -> (code: String, verifier: String) {
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        let state = PKCE.generateVerifier()

        guard var components = URLComponents(url: metadata.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw OAuthError.invalidCallback
        }
        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: OAuthConstants.clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConstants.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        // Only send `scope` when explicitly configured; empty means "use the
        // client's registered scopes" (sending guessed tokens => invalid_scope).
        if !OAuthConstants.scopeString.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: OAuthConstants.scopeString))
        }
        components.queryItems = queryItems

        guard let authorizeURL = components.url else {
            throw OAuthError.invalidCallback
        }

        let code = try await runLoopbackFlow(authorizeURL: authorizeURL, expectedState: state)
        return (code, verifier)
    }

    /// Starts the loopback listener, opens the browser, and awaits the callback.
    ///
    /// - Parameters:
    ///   - authorizeURL: The authorization URL to open in the browser.
    ///   - expectedState: The `state` value that the callback must echo back.
    /// - Returns: The authorization code extracted from the callback request.
    /// - Throws: ``OAuthError`` on listener failure, timeout (mapped to
    ///   ``OAuthError/userCancelled``), or invalid/mismatched callback.
    private func runLoopbackFlow(authorizeURL: URL, expectedState: String) async throws -> String {
        let listener: NWListener
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let port = NWEndpoint.Port(rawValue: OAuthConstants.loopbackPort) else {
                throw OAuthError.callbackServerFailed("Invalid loopback port")
            }
            listener = try NWListener(using: parameters, on: port)
        } catch let error as OAuthError {
            throw error
        } catch {
            logger.error("Failed to create loopback listener: \(error.localizedDescription)")
            throw OAuthError.callbackServerFailed("Port \(OAuthConstants.loopbackPort) may be in use")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                let box = ResumeBox(continuation: continuation) { listener.cancel() }

                // Timeout: browser closed without finishing → treat as cancel.
                let timeoutTask = Task {
                    try? await Task.sleep(for: .seconds(OAuthConstants.callbackTimeout))
                    box.finish(.failure(OAuthError.userCancelled))
                }

                listener.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        // Listener is up; open the authorization URL in the
                        // system default browser.
                        DispatchQueue.main.async {
                            NSWorkspace.shared.open(authorizeURL)
                        }
                    case .failed(let error):
                        timeoutTask.cancel()
                        box.finish(.failure(OAuthError.callbackServerFailed(error.localizedDescription)))
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }

                listener.newConnectionHandler = { connection in
                    OAuthService.handleConnection(connection, expectedState: expectedState) { result in
                        timeoutTask.cancel()
                        box.finish(result)
                    }
                }

                listener.start(queue: .global())
            }
        } onCancel: {
            listener.cancel()
        }
    }

    /// Handles a single loopback HTTP connection: parse the request line, send a
    /// friendly 200 page, then report the parsed code (or error).
    private nonisolated static func handleConnection(
        _ connection: NWConnection,
        expectedState: String,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
            let result: Result<String, Error>
            if let data = data, let request = String(data: data, encoding: .utf8) {
                result = parseCallbackRequest(request, expectedState: expectedState)
            } else {
                result = .failure(OAuthError.invalidCallback)
            }

            let body = successHTML
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """

            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            completion(result)
        }
    }

    /// Parses the authorization code from a raw HTTP request, verifying `state`.
    private nonisolated static func parseCallbackRequest(_ request: String, expectedState: String) -> Result<String, Error> {
        // First line: "GET /callback?code=...&state=... HTTP/1.1"
        guard let requestLine = request.split(separator: "\r\n", maxSplits: 1).first else {
            return .failure(OAuthError.invalidCallback)
        }
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else {
            return .failure(OAuthError.invalidCallback)
        }
        let path = String(tokens[1])

        guard let components = URLComponents(string: "http://127.0.0.1\(path)"),
              let items = components.queryItems else {
            return .failure(OAuthError.invalidCallback)
        }

        let returnedState = items.first { $0.name == "state" }?.value
        guard returnedState == expectedState else {
            return .failure(OAuthError.invalidCallback)
        }

        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .failure(OAuthError.invalidCallback)
        }
        return .success(code)
    }

    /// The HTML shown in the browser after a successful callback.
    private nonisolated static let successHTML = """
    <!doctype html>
    <html>
    <head><meta charset="utf-8"><title>Tunnelflare</title></head>
    <body style="font-family: -apple-system, sans-serif; text-align: center; padding: 48px;">
    <h2>Tunnelflare</h2>
    <p>You can close this tab and return to the app.</p>
    </body>
    </html>
    """

    // MARK: - Token Exchange

    /// Exchanges an authorization code for tokens.
    ///
    /// - Parameters:
    ///   - code: The authorization code from ``authorize(metadata:)``.
    ///   - verifier: The PKCE verifier used in the authorize request.
    ///   - metadata: The discovered server metadata.
    /// - Returns: The token response.
    /// - Throws: ``OAuthError/tokenExchangeFailed(_:)`` on failure.
    func exchange(code: String, verifier: String, metadata: OAuthServerMetadata) async throws -> OAuthTokenResponse {
        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConstants.redirectURI,
            "client_id": OAuthConstants.clientID,
            "code_verifier": verifier
        ]
        return try await postTokenRequest(to: metadata.tokenEndpoint, parameters: parameters)
    }

    /// Uses a refresh token to obtain a new access token.
    ///
    /// - Parameters:
    ///   - refreshToken: The stored refresh token.
    ///   - metadata: The discovered server metadata.
    /// - Returns: The token response.
    /// - Throws: ``OAuthError/refreshFailed`` on failure.
    func refresh(refreshToken: String, metadata: OAuthServerMetadata) async throws -> OAuthTokenResponse {
        let parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthConstants.clientID
        ]
        do {
            return try await postTokenRequest(to: metadata.tokenEndpoint, parameters: parameters)
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            throw OAuthError.refreshFailed
        }
    }

    /// Performs a form-urlencoded POST to a token endpoint and decodes the body.
    private func postTokenRequest(to endpoint: URL, parameters: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formURLEncoded(parameters).data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "status \(httpResponse.statusCode)"
            throw OAuthError.tokenExchangeFailed(body)
        }

        do {
            return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw OAuthError.tokenExchangeFailed("Could not decode token response")
        }
    }

    /// Encodes parameters as `application/x-www-form-urlencoded`.
    private static func formURLEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        .joined(separator: "&")
    }

    // MARK: - Configuration Guard

    /// Throws if the client ID placeholder has not been replaced.
    private func assertConfigured() throws {
        guard OAuthConstants.isClientIDConfigured else {
            logger.error("OAuth client ID is still the placeholder value")
            throw OAuthError.missingClientID
        }
    }
}

// MARK: - ResumeBox

/// Guards a `CheckedContinuation` so it resumes exactly once across the racing
/// listener, connection, and timeout callbacks, running cleanup on first finish.
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private let continuation: CheckedContinuation<String, Error>
    private let cleanup: @Sendable () -> Void

    init(continuation: CheckedContinuation<String, Error>, cleanup: @escaping @Sendable () -> Void) {
        self.continuation = continuation
        self.cleanup = cleanup
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        lock.unlock()

        cleanup()
        continuation.resume(with: result)
    }
}
