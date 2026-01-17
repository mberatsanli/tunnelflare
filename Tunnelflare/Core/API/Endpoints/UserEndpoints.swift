//
//  UserEndpoints.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - User Endpoints

/// Endpoints for user-related operations.
enum UserEndpoints {

    // MARK: - Get Current User

    /// Endpoint to get the current authenticated user.
    ///
    /// Returns the profile information for the currently authenticated user.
    ///
    /// ## API Reference
    /// `GET /user`
    struct GetCurrentUser: Endpoint {
        typealias Response = User

        let path = "user"
        let method = HTTPMethod.get
    }
}
