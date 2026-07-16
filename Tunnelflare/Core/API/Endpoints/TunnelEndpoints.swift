//
//  TunnelEndpoints.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Tunnel Endpoints

/// Endpoints for tunnel-related operations.
enum TunnelEndpoints {

    // MARK: - List Tunnels

    /// Endpoint to list all tunnels for an account.
    ///
    /// Returns a list of Cloudflare Tunnels for the specified account.
    ///
    /// ## API Reference
    /// `GET /accounts/{account_id}/cfd_tunnel`
    struct ListTunnels: Endpoint, PaginatedEndpoint {
        typealias Response = [Tunnel]

        let accountId: String
        let page: Int
        let perPage: Int
        let name: String?
        let isDeleted: Bool

        var path: String {
            "accounts/\(accountId)/cfd_tunnel"
        }

        let method = HTTPMethod.get

        var queryItems: [URLQueryItem]? {
            var items = paginationQueryItems
            if let name = name {
                items.append(URLQueryItem(name: "name", value: name))
            }
            items.append(URLQueryItem(name: "is_deleted", value: String(isDeleted)))
            return items
        }

        init(
            accountId: String,
            page: Int = 1,
            perPage: Int = APIConstants.defaultPageSize,
            name: String? = nil,
            isDeleted: Bool = false
        ) {
            self.accountId = accountId
            self.page = page
            self.perPage = perPage
            self.name = name
            self.isDeleted = isDeleted
        }
    }

    // MARK: - Get Tunnel

    /// Endpoint to get details for a specific tunnel.
    ///
    /// ## API Reference
    /// `GET /accounts/{account_id}/cfd_tunnel/{tunnel_id}`
    struct GetTunnel: Endpoint {
        typealias Response = Tunnel

        let accountId: String
        let tunnelId: String

        var path: String {
            "accounts/\(accountId)/cfd_tunnel/\(tunnelId)"
        }

        let method = HTTPMethod.get

        init(accountId: String, tunnelId: String) {
            self.accountId = accountId
            self.tunnelId = tunnelId
        }
    }

    // MARK: - Create Tunnel

    /// Endpoint to create a new tunnel.
    ///
    /// ## API Reference
    /// `POST /accounts/{account_id}/cfd_tunnel`
    struct CreateTunnel: Endpoint {
        typealias Response = Tunnel

        let accountId: String
        let request: CreateTunnelRequest

        var path: String {
            "accounts/\(accountId)/cfd_tunnel"
        }

        let method = HTTPMethod.post

        var body: Encodable? {
            request
        }

        init(accountId: String, name: String, configSrc: String = "cloudflare") {
            self.accountId = accountId
            self.request = CreateTunnelRequest(name: name, configSrc: configSrc)
        }
    }

    // MARK: - Delete Tunnel

    /// Endpoint to delete a tunnel.
    ///
    /// The tunnel must have no active connections before it can be deleted.
    ///
    /// ## API Reference
    /// `DELETE /accounts/{account_id}/cfd_tunnel/{tunnel_id}`
    struct DeleteTunnel: Endpoint {
        typealias Response = DeleteResponse

        let accountId: String
        let tunnelId: String

        var path: String {
            "accounts/\(accountId)/cfd_tunnel/\(tunnelId)"
        }

        let method = HTTPMethod.delete

        init(accountId: String, tunnelId: String) {
            self.accountId = accountId
            self.tunnelId = tunnelId
        }
    }

    // MARK: - Get Tunnel Token

    /// Endpoint to get a tunnel's connection token.
    ///
    /// The token is used by cloudflared to authenticate and run the tunnel.
    ///
    /// ## API Reference
    /// `GET /accounts/{account_id}/cfd_tunnel/{tunnel_id}/token`
    struct GetTunnelToken: Endpoint {
        typealias Response = String

        let accountId: String
        let tunnelId: String

        var path: String {
            "accounts/\(accountId)/cfd_tunnel/\(tunnelId)/token"
        }

        let method = HTTPMethod.get

        init(accountId: String, tunnelId: String) {
            self.accountId = accountId
            self.tunnelId = tunnelId
        }
    }

    // MARK: - Get Tunnel Configuration

    /// Endpoint to get a tunnel's configuration.
    ///
    /// Returns the ingress rules and other configuration for the tunnel.
    ///
    /// ## API Reference
    /// `GET /accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations`
    struct GetTunnelConfiguration: Endpoint {
        typealias Response = TunnelConfiguration

        let accountId: String
        let tunnelId: String

        var path: String {
            "accounts/\(accountId)/cfd_tunnel/\(tunnelId)/configurations"
        }

        let method = HTTPMethod.get

        init(accountId: String, tunnelId: String) {
            self.accountId = accountId
            self.tunnelId = tunnelId
        }
    }

    // MARK: - Update Tunnel Configuration

    /// Endpoint to update a tunnel's configuration.
    ///
    /// Replaces the tunnel's ingress rules and configuration.
    ///
    /// ## API Reference
    /// `PUT /accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations`
    struct UpdateTunnelConfiguration: Endpoint {
        typealias Response = TunnelConfiguration

        let accountId: String
        let tunnelId: String
        let configuration: IngressConfig

        var path: String {
            "accounts/\(accountId)/cfd_tunnel/\(tunnelId)/configurations"
        }

        let method = HTTPMethod.put

        /// Encoded with a plain encoder (no snake_case strategy): the config
        /// merges in raw JSON preserved from the GET, whose keys (camelCase
        /// originRequest fields, "warp-routing", unknown keys) must be sent
        /// back to the API exactly as they were received.
        var rawBody: Data? {
            try? JSONEncoder().encode(UpdateTunnelConfigurationRequest(config: configuration))
        }

        init(accountId: String, tunnelId: String, configuration: IngressConfig) {
            self.accountId = accountId
            self.tunnelId = tunnelId
            self.configuration = configuration
        }
    }

    // MARK: - List Tunnel Connectors

    /// Endpoint to list connectors for a tunnel.
    ///
    /// Returns the list of cloudflared instances connected to the tunnel.
    ///
    /// ## API Reference
    /// `GET /accounts/{account_id}/cfd_tunnel/{tunnel_id}/connectors`
    struct ListTunnelConnectors: Endpoint {
        typealias Response = [Connector]

        let accountId: String
        let tunnelId: String

        var path: String {
            "accounts/\(accountId)/cfd_tunnel/\(tunnelId)/connectors"
        }

        let method = HTTPMethod.get

        init(accountId: String, tunnelId: String) {
            self.accountId = accountId
            self.tunnelId = tunnelId
        }
    }

    // MARK: - Clean Up Tunnel Connections

    /// Endpoint to clean up stale connections for a tunnel.
    ///
    /// Removes connections that are no longer active.
    ///
    /// ## API Reference
    /// `DELETE /accounts/{account_id}/cfd_tunnel/{tunnel_id}/connections`
    struct CleanUpConnections: Endpoint {
        typealias Response = EmptyResult

        let accountId: String
        let tunnelId: String

        var path: String {
            "accounts/\(accountId)/cfd_tunnel/\(tunnelId)/connections"
        }

        let method = HTTPMethod.delete

        init(accountId: String, tunnelId: String) {
            self.accountId = accountId
            self.tunnelId = tunnelId
        }
    }

}
