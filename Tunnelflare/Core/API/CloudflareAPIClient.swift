//
//  CloudflareAPIClient.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation
import os.log

// MARK: - CloudflareAPIClient

/// Actor-based API client for Cloudflare API v4.
///
/// This client handles all communication with the Cloudflare API, including:
/// - Authentication header injection
/// - Request/response encoding/decoding
/// - Error handling (401, 429, 5xx)
/// - Rate limit detection
/// - Retry with exponential backoff
///
/// ## Usage
/// ```swift
/// let client = CloudflareAPIClient(authManager: authManager)
///
/// // Fetch current user
/// let user = try await client.fetchCurrentUser()
///
/// // Fetch tunnels
/// let tunnels = try await client.fetchTunnels(accountId: "account-id")
/// ```
actor CloudflareAPIClient {

    // MARK: - Properties

    /// The base URL for the Cloudflare API.
    private let baseURL: URL

    /// The URL session for network requests.
    private let session: URLSession

    /// The authentication manager for token access.
    private let authManager: AuthenticationManager

    /// Logger for API operations.
    private let logger = Logger.api

    /// JSON decoder configured for Cloudflare API responses.

    /// JSON encoder configured for Cloudflare API requests.
    private let encoder = JSONEncoder.cloudflareAPI

    // MARK: - Rate Limiting

    /// Tracks rate limit state per endpoint path.
    private var rateLimitState: [String: RateLimitInfo] = [:]

    /// Information about rate limit status.
    private struct RateLimitInfo {
        let resetAt: Date
        let remaining: Int
    }

    // MARK: - Initialization

    /// Creates a new CloudflareAPIClient.
    ///
    /// - Parameters:
    ///   - authManager: The authentication manager for token access.
    ///   - baseURL: The base URL for the API (defaults to Cloudflare API v4).
    ///   - session: The URL session to use (defaults to shared session).
    init(
        authManager: AuthenticationManager,
        baseURL: URL = APIConstants.baseURL,
        session: URLSession = .shared
    ) {
        self.authManager = authManager
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Generic Request Method

    /// Performs a request to the specified endpoint.
    ///
    /// This method handles:
    /// - Building the request with authentication
    /// - Executing the request
    /// - Decoding the response
    /// - Error handling and retry logic
    ///
    /// - Parameter endpoint: The endpoint to request.
    /// - Returns: The decoded response.
    /// - Throws: `APIError` if the request fails.
    func request<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        try await performRequest(endpoint, retryCount: 0)
    }

    /// Internal request method with retry support.
    private func performRequest<E: Endpoint>(_ endpoint: E, retryCount: Int) async throws -> E.Response {
        let startTime = Date()
        let requestId = UUID().uuidString.prefix(8)

        // Check rate limit before making request
        if let rateLimitInfo = rateLimitState[endpoint.path],
           rateLimitInfo.resetAt > Date(),
           rateLimitInfo.remaining == 0 {
            let waitTime = rateLimitInfo.resetAt.timeIntervalSinceNow
            logger.warning("[\(requestId)] Rate limited, waiting \(waitTime)s")
            throw APIError.rateLimited(retryAfter: waitTime)
        }

        // Get access token if required
        var accessToken: String? = nil
        if endpoint.requiresAuthentication {
            do {
                accessToken = try await authManager.getAccessToken()
            } catch {
                logger.error("[\(requestId)] Failed to get access token: \(error.localizedDescription)")
                throw APIError.authenticationRequired
            }

            guard accessToken != nil else {
                throw APIError.authenticationRequired
            }
        }

        // Build request
        guard let request = endpoint.buildRequest(baseURL: baseURL, accessToken: accessToken) else {
            throw APIError.invalidURL
        }

        logger.logRequest(method: endpoint.method.rawValue, path: endpoint.path, requestId: String(requestId))

        do {
            // Perform request
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            let duration = Date().timeIntervalSince(startTime)
            logger.logResponse(
                statusCode: httpResponse.statusCode,
                path: endpoint.path,
                duration: duration,
                requestId: String(requestId)
            )

            // Update rate limit info from headers
            updateRateLimitInfo(from: httpResponse, for: endpoint.path)

            // Handle response based on status code
            return try await handleResponse(
                data: data,
                response: httpResponse,
                endpoint: endpoint,
                retryCount: retryCount,
                requestId: String(requestId)
            )

        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            let apiError = APIError.from(urlError: error)
            if apiError.isRetryable && retryCount < APIConstants.maxRetries {
                return try await retryRequest(endpoint, retryCount: retryCount, error: apiError)
            }
            throw apiError
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// Handles the HTTP response and decodes the result.
    private func handleResponse<E: Endpoint>(
        data: Data,
        response: HTTPURLResponse,
        endpoint: E,
        retryCount: Int,
        requestId: String
    ) async throws -> E.Response {
        let statusCode = response.statusCode

        switch statusCode {
        case 200...299:
            // Success - decode response
            return try decodeResponse(data: data, endpoint: endpoint)

        case 401:
            // Unauthorized - API token is invalid
            // With API token auth, there's no refresh mechanism - user needs to re-authenticate
            logger.warning("[\(requestId)] Unauthorized - API token may be invalid or expired")
            throw APIError.unauthorized

        case 429:
            // Rate limited
            let retryAfter = parseRetryAfter(from: response)
            let error = APIError.rateLimited(retryAfter: retryAfter)

            if retryCount < APIConstants.maxRetries {
                let waitTime = retryAfter ?? 5.0
                logger.warning("[\(requestId)] Rate limited, waiting \(waitTime)s before retry")
                try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                return try await performRequest(endpoint, retryCount: retryCount + 1)
            }

            throw error

        case 500...599:
            // Server error - may be retryable
            let error = APIError.from(statusCode: statusCode, data: data)

            if error.isRetryable && retryCount < APIConstants.maxRetries {
                return try await retryRequest(endpoint, retryCount: retryCount, error: error)
            }

            throw error

        default:
            // Client error or other
            throw APIError.from(statusCode: statusCode, data: data)
        }
    }

    /// Decodes the response data.
    private func decodeResponse<E: Endpoint>(data: Data, endpoint: E) throws -> E.Response {
        // Handle empty responses
        if data.isEmpty {
            if E.Response.self == EmptyResult.self {
                return EmptyResult() as! E.Response
            }
            throw APIError.emptyResponse
        }

        do {
            // Special handling for String responses (like tunnel token)
            if E.Response.self == String.self {
                let tokenResponse = try endpoint.responseDecoder.decode(TokenResponse.self, from: data)
                if tokenResponse.success {
                    return tokenResponse.result as! E.Response
                } else if let errors = tokenResponse.errors, !errors.isEmpty {
                    throw APIError.apiError(errors: errors)
                }
                throw APIError.invalidResponse
            }

            // Standard API response
            let apiResponse = try endpoint.responseDecoder.decode(APIResponse<E.Response>.self, from: data)

            guard apiResponse.success else {
                throw APIError.apiError(errors: apiResponse.errors ?? [])
            }

            return apiResponse.result

        } catch let error as APIError {
            throw error
        } catch {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw APIError.decodingError(error)
        }
    }

    /// Decodes the response data with pagination info.
    private func decodeResponseWithPagination<E: Endpoint>(data: Data, endpoint: E) throws -> (E.Response, ResultInfo?) {
        // Handle empty responses
        if data.isEmpty {
            if E.Response.self == EmptyResult.self {
                return (EmptyResult() as! E.Response, nil)
            }
            throw APIError.emptyResponse
        }

        do {
            // Standard API response with pagination
            let apiResponse = try endpoint.responseDecoder.decode(APIResponse<E.Response>.self, from: data)

            guard apiResponse.success else {
                throw APIError.apiError(errors: apiResponse.errors ?? [])
            }

            return (apiResponse.result, apiResponse.resultInfo)

        } catch let error as APIError {
            throw error
        } catch {
            logger.error("Decoding error: \(error.localizedDescription)")
            throw APIError.decodingError(error)
        }
    }

    /// Retries a request with exponential backoff.
    private func retryRequest<E: Endpoint>(
        _ endpoint: E,
        retryCount: Int,
        error: APIError
    ) async throws -> E.Response {
        let delay = calculateBackoffDelay(retryCount: retryCount)
        logger.info("Retrying request in \(delay)s (attempt \(retryCount + 1)/\(APIConstants.maxRetries))")

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return try await performRequest(endpoint, retryCount: retryCount + 1)
    }

    /// Calculates exponential backoff delay.
    private func calculateBackoffDelay(retryCount: Int) -> TimeInterval {
        let baseDelay = APIConstants.retryDelay
        let exponentialDelay = baseDelay * pow(2.0, Double(retryCount))
        // Add jitter (random 0-1 second)
        let jitter = Double.random(in: 0...1)
        return min(exponentialDelay + jitter, 30.0) // Cap at 30 seconds
    }

    /// Updates rate limit tracking from response headers.
    private func updateRateLimitInfo(from response: HTTPURLResponse, for path: String) {
        // Cloudflare uses these headers for rate limiting
        if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init),
           let resetTimestamp = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init) {
            let resetDate = Date(timeIntervalSince1970: resetTimestamp)
            rateLimitState[path] = RateLimitInfo(resetAt: resetDate, remaining: remaining)
        }
    }

    /// Parses the Retry-After header from a response.
    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfter = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        // Try parsing as seconds
        if let seconds = Double(retryAfter) {
            return seconds
        }

        // Try parsing as HTTP date
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: retryAfter) {
            return date.timeIntervalSinceNow
        }

        return nil
    }
}

// MARK: - User and Account Operations (Task 3.4)

extension CloudflareAPIClient {

    /// Fetches the current authenticated user.
    ///
    /// - Returns: The current user's profile.
    /// - Throws: `APIError` if the request fails.
    func fetchCurrentUser() async throws -> User {
        try await request(UserEndpoints.GetCurrentUser())
    }

    /// Fetches all accounts the user has access to.
    ///
    /// - Returns: An array of accounts.
    /// - Throws: `APIError` if the request fails.
    func fetchAccounts() async throws -> [Account] {
        try await request(AccountEndpoints.ListAccounts())
    }

    /// Fetches a specific account.
    ///
    /// - Parameter accountId: The account ID.
    /// - Returns: The account details.
    /// - Throws: `APIError` if the request fails.
    func fetchAccount(accountId: String) async throws -> Account {
        try await request(AccountEndpoints.GetAccount(accountId: accountId))
    }
}

// MARK: - Tunnel Operations (Task 3.5)

extension CloudflareAPIClient {

    /// Fetches all tunnels for an account with automatic pagination.
    ///
    /// This method automatically fetches all pages of results, not just the first page.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - includeDeleted: Whether to include deleted tunnels.
    /// - Returns: An array of all tunnels.
    /// - Throws: `APIError` if the request fails.
    func fetchTunnels(accountId: String, includeDeleted: Bool = false) async throws -> [Tunnel] {
        var allTunnels: [Tunnel] = []
        var currentPage = 1
        let perPage = APIConstants.defaultPageSize

        while true {
            let endpoint = TunnelEndpoints.ListTunnels(
                accountId: accountId,
                page: currentPage,
                perPage: perPage,
                isDeleted: includeDeleted
            )

            let (tunnels, resultInfo) = try await requestWithPagination(endpoint)
            allTunnels.append(contentsOf: tunnels)

            // Check if there are more pages
            guard let info = resultInfo, info.hasMorePages else {
                break
            }

            currentPage += 1

            // Safety limit to prevent infinite loops
            if currentPage > 100 {
                logger.warning("Pagination safety limit reached at page 100")
                break
            }
        }

        logger.info("Fetched \(allTunnels.count) tunnels across \(currentPage) page(s)")
        return allTunnels
    }

    /// Performs a request and returns both the result and pagination info.
    private func requestWithPagination<E: Endpoint>(_ endpoint: E) async throws -> (E.Response, ResultInfo?) where E.Response: Decodable {
        let startTime = Date()
        let requestId = UUID().uuidString.prefix(8)

        // Check rate limit before making request
        if let rateLimitInfo = rateLimitState[endpoint.path],
           rateLimitInfo.resetAt > Date(),
           rateLimitInfo.remaining == 0 {
            let waitTime = rateLimitInfo.resetAt.timeIntervalSinceNow
            logger.warning("[\(requestId)] Rate limited, waiting \(waitTime)s")
            throw APIError.rateLimited(retryAfter: waitTime)
        }

        // Get access token if required
        var accessToken: String? = nil
        if endpoint.requiresAuthentication {
            do {
                accessToken = try await authManager.getAccessToken()
            } catch {
                logger.error("[\(requestId)] Failed to get access token: \(error.localizedDescription)")
                throw APIError.authenticationRequired
            }

            guard accessToken != nil else {
                throw APIError.authenticationRequired
            }
        }

        // Build request
        guard let request = endpoint.buildRequest(baseURL: baseURL, accessToken: accessToken) else {
            throw APIError.invalidURL
        }

        logger.logRequest(method: endpoint.method.rawValue, path: endpoint.path, requestId: String(requestId))

        do {
            // Perform request
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            let duration = Date().timeIntervalSince(startTime)
            logger.logResponse(
                statusCode: httpResponse.statusCode,
                path: endpoint.path,
                duration: duration,
                requestId: String(requestId)
            )

            // Update rate limit info from headers
            updateRateLimitInfo(from: httpResponse, for: endpoint.path)

            // Handle non-success status codes
            let statusCode = httpResponse.statusCode
            guard (200...299).contains(statusCode) else {
                throw APIError.from(statusCode: statusCode, data: data)
            }

            // Decode with pagination info
            return try decodeResponseWithPagination(data: data, endpoint: endpoint)

        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// Fetches a specific tunnel.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    /// - Returns: The tunnel details.
    /// - Throws: `APIError` if the request fails.
    func fetchTunnel(accountId: String, tunnelId: String) async throws -> Tunnel {
        try await request(TunnelEndpoints.GetTunnel(accountId: accountId, tunnelId: tunnelId))
    }

    /// Creates a new tunnel.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - name: The name for the new tunnel.
    /// - Returns: The created tunnel.
    /// - Throws: `APIError` if the request fails.
    func createTunnel(accountId: String, name: String) async throws -> Tunnel {
        try await request(TunnelEndpoints.CreateTunnel(accountId: accountId, name: name))
    }

    /// Deletes a tunnel.
    ///
    /// The tunnel must have no active connections before it can be deleted.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID to delete.
    /// - Throws: `APIError` if the request fails.
    func deleteTunnel(accountId: String, tunnelId: String) async throws {
        _ = try await request(TunnelEndpoints.DeleteTunnel(accountId: accountId, tunnelId: tunnelId))
    }

    /// Cleans up all connections for a tunnel.
    ///
    /// Removes connections that are no longer active.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    /// - Throws: `APIError` if the request fails.
    func cleanUpConnections(accountId: String, tunnelId: String) async throws {
        _ = try await request(TunnelEndpoints.CleanUpConnections(accountId: accountId, tunnelId: tunnelId))
    }

    /// Fetches the connection token for a tunnel.
    ///
    /// The token is used by cloudflared to authenticate and run the tunnel.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    /// - Returns: The tunnel connection token.
    /// - Throws: `APIError` if the request fails.
    func fetchTunnelToken(accountId: String, tunnelId: String) async throws -> String {
        try await request(TunnelEndpoints.GetTunnelToken(accountId: accountId, tunnelId: tunnelId))
    }

    /// Fetches the configuration for a tunnel.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    /// - Returns: The tunnel configuration.
    /// - Throws: `APIError` if the request fails.
    func fetchTunnelConfiguration(accountId: String, tunnelId: String) async throws -> TunnelConfiguration {
        try await request(TunnelEndpoints.GetTunnelConfiguration(accountId: accountId, tunnelId: tunnelId))
    }

    /// Updates the configuration for a tunnel.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    ///   - config: The new configuration.
    /// - Returns: The updated tunnel configuration.
    /// - Throws: `APIError` if the request fails.
    @discardableResult
    func updateTunnelConfiguration(
        accountId: String,
        tunnelId: String,
        config: IngressConfig
    ) async throws -> TunnelConfiguration {
        try await request(TunnelEndpoints.UpdateTunnelConfiguration(
            accountId: accountId,
            tunnelId: tunnelId,
            configuration: config
        ))
    }

    /// Fetches connectors for a tunnel.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    /// - Returns: An array of connectors.
    /// - Throws: `APIError` if the request fails.
    func fetchTunnelConnectors(accountId: String, tunnelId: String) async throws -> [Connector] {
        try await request(TunnelEndpoints.ListTunnelConnectors(accountId: accountId, tunnelId: tunnelId))
    }

    /// Cleans up stale connections for a tunnel.
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    /// - Throws: `APIError` if the request fails.
    func cleanUpTunnelConnections(accountId: String, tunnelId: String) async throws {
        _ = try await request(TunnelEndpoints.CleanUpConnections(accountId: accountId, tunnelId: tunnelId))
    }
}

// MARK: - Zone Operations

extension CloudflareAPIClient {

    /// Fetches all zones (domains) the user has access to.
    ///
    /// - Parameters:
    ///   - accountId: Optional account ID to filter zones.
    ///   - activeOnly: Whether to only return active zones (default: true).
    /// - Returns: An array of zones.
    /// - Throws: `APIError` if the request fails.
    func fetchZones(accountId: String? = nil, activeOnly: Bool = true) async throws -> [Zone] {
        let status: ZoneStatus? = activeOnly ? .active : nil
        return try await request(ZoneEndpoints.ListZones(accountId: accountId, status: status))
    }

    /// Fetches a specific zone.
    ///
    /// - Parameter zoneId: The zone ID.
    /// - Returns: The zone details.
    /// - Throws: `APIError` if the request fails.
    func fetchZone(zoneId: String) async throws -> Zone {
        try await request(ZoneEndpoints.GetZone(zoneId: zoneId))
    }

    /// Fetches DNS records for a zone.
    ///
    /// - Parameters:
    ///   - zoneId: The zone ID.
    ///   - recordType: Optional filter by record type (e.g., "CNAME").
    ///   - name: Optional filter by record name.
    /// - Returns: An array of DNS records.
    /// - Throws: `APIError` if the request fails.
    func fetchDNSRecords(zoneId: String, recordType: String? = nil, name: String? = nil) async throws -> [DNSRecord] {
        try await request(ZoneEndpoints.ListDNSRecords(zoneId: zoneId, recordType: recordType, name: name))
    }

    /// Checks if a subdomain exists in a zone.
    ///
    /// - Parameters:
    ///   - subdomain: The subdomain to check (e.g., "app").
    ///   - zone: The zone to check in.
    /// - Returns: The existing DNS record if found, nil otherwise.
    /// - Throws: `APIError` if the request fails.
    func checkSubdomainExists(subdomain: String, zone: Zone) async throws -> DNSRecord? {
        let fullName = subdomain.isEmpty ? zone.name : "\(subdomain).\(zone.name)"
        let records = try await fetchDNSRecords(zoneId: zone.id, name: fullName)
        return records.first
    }

    /// Creates a DNS record for a tunnel.
    ///
    /// - Parameters:
    ///   - zoneId: The zone ID.
    ///   - name: The record name (e.g., "app" for app.example.com).
    ///   - tunnelId: The tunnel ID to point to.
    /// - Returns: The created DNS record.
    /// - Throws: `APIError` if the request fails.
    @discardableResult
    func createTunnelDNSRecord(zoneId: String, name: String, tunnelId: String) async throws -> DNSRecord {
        let content = "\(tunnelId).cfargotunnel.com"
        return try await request(ZoneEndpoints.CreateDNSRecord(
            zoneId: zoneId,
            recordType: "CNAME",
            name: name,
            content: content,
            proxied: true
        ))
    }

    /// Updates an existing DNS record for a tunnel.
    ///
    /// - Parameters:
    ///   - zoneId: The zone ID.
    ///   - recordId: The existing record ID to update.
    ///   - name: The record name.
    ///   - tunnelId: The tunnel ID to point to.
    /// - Returns: The updated DNS record.
    /// - Throws: `APIError` if the request fails.
    @discardableResult
    func updateTunnelDNSRecord(zoneId: String, recordId: String, name: String, tunnelId: String) async throws -> DNSRecord {
        let content = "\(tunnelId).cfargotunnel.com"
        return try await request(ZoneEndpoints.UpdateDNSRecord(
            zoneId: zoneId,
            recordId: recordId,
            recordType: "CNAME",
            name: name,
            content: content,
            proxied: true
        ))
    }

    /// Deletes a DNS record.
    ///
    /// - Parameters:
    ///   - zoneId: The zone ID.
    ///   - recordId: The record ID to delete.
    /// - Throws: `APIError` if the request fails.
    func deleteDNSRecord(zoneId: String, recordId: String) async throws {
        _ = try await request(ZoneEndpoints.DeleteDNSRecord(zoneId: zoneId, recordId: recordId))
    }

    /// Deletes all DNS CNAME records associated with a tunnel.
    ///
    /// This method:
    /// 1. Fetches the tunnel configuration to get hostnames
    /// 2. For each hostname, finds the zone and CNAME record
    /// 3. Deletes the CNAME record if it points to the tunnel
    ///
    /// - Parameters:
    ///   - accountId: The account ID.
    ///   - tunnelId: The tunnel ID.
    /// - Returns: Result containing deleted hostnames and any errors.
    func deleteDNSRecordsForTunnel(accountId: String, tunnelId: String) async -> DNSDeletionResult {
        var deletedHostnames: [String] = []
        var errors: [String] = []

        // Get tunnel configuration to find hostnames
        let configuration: TunnelConfiguration
        do {
            configuration = try await fetchTunnelConfiguration(accountId: accountId, tunnelId: tunnelId)
        } catch {
            return DNSDeletionResult(deletedHostnames: [], errors: ["Failed to fetch tunnel configuration: \(error.localizedDescription)"])
        }

        // Get all zones for lookups
        let zones: [Zone]
        do {
            zones = try await fetchZones(accountId: accountId, activeOnly: false)
        } catch {
            return DNSDeletionResult(deletedHostnames: [], errors: ["Failed to fetch zones: \(error.localizedDescription)"])
        }

        // Extract hostnames from ingress rules
        let hostnames = (configuration.config?.ingress ?? [])
            .compactMap { $0.hostname }
            .filter { !$0.isEmpty }

        // Delete DNS record for each hostname
        for hostname in hostnames {
            // Find the zone for this hostname
            guard let zone = findZone(for: hostname, in: zones) else {
                errors.append("No zone found for hostname: \(hostname)")
                continue
            }

            // Find the CNAME record for this hostname
            do {
                let records = try await fetchDNSRecords(zoneId: zone.id, recordType: "CNAME", name: hostname)

                // Find record pointing to this tunnel
                let tunnelCNAME = "\(tunnelId).cfargotunnel.com"
                guard let record = records.first(where: { $0.content == tunnelCNAME }) else {
                    // No matching record found - not an error, just skip
                    continue
                }

                // Delete the record
                try await deleteDNSRecord(zoneId: zone.id, recordId: record.id)
                deletedHostnames.append(hostname)

            } catch {
                errors.append("Failed to delete DNS for \(hostname): \(error.localizedDescription)")
            }
        }

        return DNSDeletionResult(deletedHostnames: deletedHostnames, errors: errors)
    }

    /// Finds the zone that matches a hostname.
    private func findZone(for hostname: String, in zones: [Zone]) -> Zone? {
        // Sort zones by name length (longest first) to match most specific zone
        let sortedZones = zones.sorted { $0.name.count > $1.name.count }

        for zone in sortedZones {
            if hostname == zone.name || hostname.hasSuffix(".\(zone.name)") {
                return zone
            }
        }

        return nil
    }
}

// MARK: - DNS Deletion Result

/// Result of deleting DNS records for a tunnel.
struct DNSDeletionResult: Sendable {
    /// Hostnames that were successfully deleted.
    let deletedHostnames: [String]

    /// Any errors that occurred during deletion.
    let errors: [String]

    /// Whether all deletions succeeded.
    var success: Bool {
        errors.isEmpty
    }

    /// Whether any DNS records were deleted.
    var hasDeleted: Bool {
        !deletedHostnames.isEmpty
    }
}

// MARK: - Auth Token Operations

extension CloudflareAPIClient {

    /// Verifies the current API token.
    ///
    /// - Returns: Token verification information.
    /// - Throws: `APIError` if the request fails.
    func verifyToken() async throws -> TokenVerification {
        try await request(AuthEndpoints.VerifyToken())
    }
}
