//
//  JSONFixtures.swift
//  TunnelflareTests
//
//  Created on 2026-01-11.
//  Sample JSON fixtures for API model tests.
//

import Foundation

// MARK: - JSON Fixtures

/// Sample JSON responses for testing API model decoding.
enum JSONFixtures {

    // MARK: - User Fixtures

    /// Complete user response with all fields.
    static let userComplete = """
    {
        "id": "user-123",
        "email": "user@example.com",
        "first_name": "John",
        "last_name": "Doe",
        "username": "johndoe",
        "two_factor_authentication_enabled": true,
        "suspended": false,
        "created_on": "2024-01-10T12:00:00Z",
        "modified_on": "2024-06-15T08:30:00Z"
    }
    """

    /// User with minimal required fields only.
    static let userMinimal = """
    {
        "id": "user-456",
        "email": "minimal@example.com"
    }
    """

    /// User with null optional fields.
    static let userNullFields = """
    {
        "id": "user-789",
        "email": "nulls@example.com",
        "first_name": null,
        "last_name": null,
        "username": null,
        "two_factor_authentication_enabled": null,
        "suspended": null,
        "created_on": null,
        "modified_on": null
    }
    """

    /// User with empty string names.
    static let userEmptyNames = """
    {
        "id": "user-empty",
        "email": "empty@example.com",
        "first_name": "",
        "last_name": "",
        "username": ""
    }
    """

    // MARK: - Account Fixtures

    /// Complete account response with all fields.
    static let accountComplete = """
    {
        "id": "account-123",
        "name": "Personal Account",
        "type": "standard",
        "settings": {
            "enforce_twofactor": true,
            "use_legacy_ns": false,
            "access_approval_expiry": "2024-12-31"
        },
        "created_on": "2023-01-01T00:00:00Z"
    }
    """

    /// Enterprise account.
    static let accountEnterprise = """
    {
        "id": "account-enterprise",
        "name": "Acme Corporation",
        "type": "enterprise",
        "settings": {
            "enforce_twofactor": true
        },
        "created_on": "2022-06-15T10:00:00Z"
    }
    """

    /// Account with minimal fields.
    static let accountMinimal = """
    {
        "id": "account-minimal",
        "name": "Minimal Account"
    }
    """

    /// Account with null type.
    static let accountNullType = """
    {
        "id": "account-null-type",
        "name": "Null Type Account",
        "type": null
    }
    """

    // MARK: - Tunnel Fixtures

    /// Complete tunnel with active connections.
    static let tunnelHealthy = """
    {
        "id": "tunnel-healthy-123",
        "name": "my-dev-tunnel",
        "created_at": "2024-01-10T12:00:00Z",
        "deleted_at": null,
        "connections": [
            {
                "uuid": "conn-uuid-1",
                "colo_name": "SJC",
                "is_pending_reconnect": false,
                "client_id": "client-123",
                "client_version": "2024.1.1",
                "opened_at": "2024-06-20T15:30:00Z",
                "origin_ip": "192.168.1.100",
                "arch": "darwin_arm64"
            }
        ],
        "status": "healthy",
        "account_tag": "account-123",
        "conns_active_at": "2024-06-20T15:30:00Z",
        "metadata": {
            "is_legacy": false,
            "config_src": "cloudflare"
        }
    }
    """

    /// Tunnel with no connections (inactive).
    static let tunnelInactive = """
    {
        "id": "tunnel-inactive-456",
        "name": "api-tunnel",
        "created_at": "2024-01-05T08:00:00Z",
        "deleted_at": null,
        "connections": [],
        "status": "inactive",
        "account_tag": "account-123"
    }
    """

    /// Deleted tunnel.
    static let tunnelDeleted = """
    {
        "id": "tunnel-deleted-789",
        "name": "old-tunnel",
        "created_at": "2023-06-01T00:00:00Z",
        "deleted_at": "2024-03-15T12:00:00Z",
        "connections": [],
        "status": null
    }
    """

    /// Tunnel with minimal fields.
    static let tunnelMinimal = """
    {
        "id": "tunnel-minimal",
        "name": "minimal-tunnel",
        "created_at": "2024-06-01T00:00:00Z",
        "connections": []
    }
    """

    /// Tunnel with multiple connections.
    static let tunnelMultipleConnections = """
    {
        "id": "tunnel-multi",
        "name": "ha-tunnel",
        "created_at": "2024-01-01T00:00:00Z",
        "connections": [
            {
                "uuid": "conn-1",
                "colo_name": "SJC",
                "is_pending_reconnect": false,
                "client_id": "client-a",
                "client_version": "2024.1.1",
                "opened_at": "2024-06-20T10:00:00Z"
            },
            {
                "uuid": "conn-2",
                "colo_name": "LAX",
                "is_pending_reconnect": false,
                "client_id": "client-b",
                "client_version": "2024.1.0",
                "opened_at": "2024-06-20T11:00:00Z"
            },
            {
                "uuid": "conn-3",
                "colo_name": "ORD",
                "is_pending_reconnect": true,
                "client_id": "client-c",
                "client_version": "2024.1.1",
                "opened_at": "2024-06-20T09:00:00Z"
            }
        ],
        "status": "degraded"
    }
    """

    // MARK: - Connection Fixtures

    /// Complete connection with all fields.
    static let connectionComplete = """
    {
        "uuid": "connection-uuid-123",
        "colo_name": "SJC",
        "is_pending_reconnect": false,
        "client_id": "client-id-456",
        "client_version": "2024.1.1",
        "opened_at": "2024-06-20T15:30:00.123Z",
        "origin_ip": "192.168.1.100",
        "arch": "darwin_arm64"
    }
    """

    /// Connection with pending reconnect.
    static let connectionPending = """
    {
        "uuid": "connection-pending",
        "colo_name": "LAX",
        "is_pending_reconnect": true,
        "client_id": "client-pending",
        "client_version": "2024.1.0",
        "opened_at": "2024-06-20T14:00:00Z"
    }
    """

    /// Connection with minimal fields.
    static let connectionMinimal = """
    {
        "uuid": "connection-minimal",
        "colo_name": "ORD",
        "is_pending_reconnect": false,
        "opened_at": "2024-06-20T12:00:00Z"
    }
    """

    // MARK: - Ingress Rule Fixtures

    /// Complete tunnel configuration with multiple rules.
    static let tunnelConfiguration = """
    {
        "config": {
            "ingress": [
                {
                    "hostname": "app.example.com",
                    "path": "/api",
                    "service": "http://localhost:3000",
                    "originRequest": {
                        "connectTimeout": 30,
                        "noTLSVerify": false
                    }
                },
                {
                    "hostname": "api.example.com",
                    "service": "https://localhost:8443"
                },
                {
                    "service": "http_status:404"
                }
            ],
            "warp-routing": {
                "enabled": true
            }
        },
        "source": "cloudflare",
        "version": 1
    }
    """

    /// Ingress rule for HTTP service.
    static let ingressHTTP = """
    {
        "hostname": "app.example.com",
        "service": "http://localhost:3000"
    }
    """

    /// Ingress rule for HTTPS service.
    static let ingressHTTPS = """
    {
        "hostname": "secure.example.com",
        "service": "https://localhost:8443"
    }
    """

    /// Ingress rule for TCP service.
    static let ingressTCP = """
    {
        "hostname": "tcp.example.com",
        "service": "tcp://localhost:5432"
    }
    """

    /// Ingress rule for SSH service.
    static let ingressSSH = """
    {
        "hostname": "ssh.example.com",
        "service": "ssh://localhost:22"
    }
    """

    /// Catch-all ingress rule.
    static let ingressCatchAll = """
    {
        "service": "http_status:404"
    }
    """

    /// Ingress rule with path.
    static let ingressWithPath = """
    {
        "hostname": "app.example.com",
        "path": "/api/v1/*",
        "service": "http://localhost:3000"
    }
    """

    // MARK: - API Response Fixtures

    /// Successful API response wrapper for user.
    static let apiResponseUser = """
    {
        "success": true,
        "result": \(userComplete),
        "errors": [],
        "messages": []
    }
    """

    /// Successful API response wrapper for accounts list.
    static let apiResponseAccounts = """
    {
        "success": true,
        "result": [
            \(accountComplete),
            \(accountEnterprise)
        ],
        "errors": [],
        "messages": [],
        "result_info": {
            "page": 1,
            "per_page": 25,
            "total_count": 2,
            "total_pages": 1,
            "count": 2
        }
    }
    """

    /// API error response.
    static let apiErrorResponse = """
    {
        "success": false,
        "errors": [
            {
                "code": 10000,
                "message": "Authentication error"
            }
        ],
        "messages": []
    }
    """

    /// API error with error chain.
    static let apiErrorWithChain = """
    {
        "success": false,
        "errors": [
            {
                "code": 1001,
                "message": "Invalid request",
                "error_chain": [
                    {
                        "code": 1002,
                        "message": "Missing required field: name"
                    }
                ]
            }
        ],
        "messages": []
    }
    """

    // MARK: - Date Edge Cases

    /// Date with fractional seconds.
    static let dateWithFractionalSeconds = "2024-06-20T15:30:00.123Z"

    /// Date without fractional seconds.
    static let dateWithoutFractionalSeconds = "2024-06-20T15:30:00Z"

    /// Date with timezone offset.
    static let dateWithTimezone = "2024-06-20T15:30:00+00:00"
}
