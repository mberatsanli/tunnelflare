//
//  AccountEndpoints.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Account Endpoints

/// Endpoints for account-related operations.
enum AccountEndpoints {

    // MARK: - List Accounts

    /// Endpoint to list all accounts the user has access to.
    ///
    /// Returns a list of accounts/organizations that the authenticated
    /// user is a member of.
    ///
    /// ## API Reference
    /// `GET /accounts`
    struct ListAccounts: Endpoint, PaginatedEndpoint {
        typealias Response = [Account]

        let path = "accounts"
        let method = HTTPMethod.get
        let page: Int
        let perPage: Int

        var queryItems: [URLQueryItem]? {
            paginationQueryItems
        }

        init(page: Int = 1, perPage: Int = APIConstants.defaultPageSize) {
            self.page = page
            self.perPage = perPage
        }
    }

    // MARK: - Get Account

    /// Endpoint to get details for a specific account.
    ///
    /// ## API Reference
    /// `GET /accounts/{account_id}`
    struct GetAccount: Endpoint {
        typealias Response = Account

        let accountId: String

        var path: String {
            "accounts/\(accountId)"
        }

        let method = HTTPMethod.get

        init(accountId: String) {
            self.accountId = accountId
        }
    }
}
