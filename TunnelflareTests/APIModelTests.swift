//
//  APIModelTests.swift
//  TunnelflareTests
//
//  Created on 2026-01-11.
//  Tests for API model decoding (User, Account, Tunnel, Connection, IngressRule).
//

import XCTest
@testable import Tunnelflare

// MARK: - User Model Tests

final class UserModelTests: XCTestCase {

    // MARK: - Basic Decoding Tests

    func testUserDecoding_Complete() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userComplete)

        XCTAssertEqual(user.id, "user-123")
        XCTAssertEqual(user.email, "user@example.com")
        XCTAssertEqual(user.firstName, "John")
        XCTAssertEqual(user.lastName, "Doe")
        XCTAssertEqual(user.username, "johndoe")
        XCTAssertEqual(user.twoFactorAuthenticationEnabled, true)
        XCTAssertEqual(user.suspended, false)
        XCTAssertNotNil(user.createdOn)
        XCTAssertNotNil(user.modifiedOn)
    }

    func testUserDecoding_Minimal() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userMinimal)

        XCTAssertEqual(user.id, "user-456")
        XCTAssertEqual(user.email, "minimal@example.com")
        XCTAssertNil(user.firstName)
        XCTAssertNil(user.lastName)
        XCTAssertNil(user.username)
        XCTAssertNil(user.twoFactorAuthenticationEnabled)
        XCTAssertNil(user.suspended)
    }

    func testUserDecoding_NullFields() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userNullFields)

        XCTAssertEqual(user.id, "user-789")
        XCTAssertEqual(user.email, "nulls@example.com")
        XCTAssertNil(user.firstName)
        XCTAssertNil(user.lastName)
        XCTAssertNil(user.username)
    }

    // MARK: - Computed Properties Tests

    func testUserDisplayName_FullName() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userComplete)
        XCTAssertEqual(user.displayName, "John Doe")
    }

    func testUserDisplayName_EmailFallback() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userMinimal)
        XCTAssertEqual(user.displayName, "minimal@example.com")
    }

    func testUserDisplayName_EmptyNames() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userEmptyNames)
        XCTAssertEqual(user.displayName, "empty@example.com")
    }

    func testUserInitials_FullName() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userComplete)
        XCTAssertEqual(user.initials, "JD")
    }

    func testUserInitials_EmailFallback() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userMinimal)
        XCTAssertEqual(user.initials, "M")
    }

    func testUserHas2FA_True() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userComplete)
        XCTAssertTrue(user.has2FA)
    }

    func testUserHas2FA_Nil() throws {
        let user: User = try decode(User.self, from: JSONFixtures.userMinimal)
        XCTAssertFalse(user.has2FA)
    }

    // MARK: - Error Cases

    func testUserDecoding_MissingId() {
        let json = """
        {
            "email": "missing@example.com"
        }
        """
        assertDecodingFails(User.self, from: json)
    }

    func testUserDecoding_MissingEmail() {
        let json = """
        {
            "id": "user-no-email"
        }
        """
        assertDecodingFails(User.self, from: json)
    }
}

// MARK: - Account Model Tests

final class AccountModelTests: XCTestCase {

    // MARK: - Basic Decoding Tests

    func testAccountDecoding_Complete() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountComplete)

        XCTAssertEqual(account.id, "account-123")
        XCTAssertEqual(account.name, "Personal Account")
        XCTAssertEqual(account.type, "standard")
        XCTAssertNotNil(account.settings)
        XCTAssertEqual(account.settings?.enforceTwofactor, true)
        XCTAssertEqual(account.settings?.useLegacyNs, false)
        XCTAssertNotNil(account.createdOn)
    }

    func testAccountDecoding_Enterprise() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountEnterprise)

        XCTAssertEqual(account.id, "account-enterprise")
        XCTAssertEqual(account.name, "Acme Corporation")
        XCTAssertEqual(account.type, "enterprise")
        XCTAssertTrue(account.isEnterprise)
    }

    func testAccountDecoding_Minimal() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountMinimal)

        XCTAssertEqual(account.id, "account-minimal")
        XCTAssertEqual(account.name, "Minimal Account")
        XCTAssertNil(account.type)
        XCTAssertNil(account.settings)
        XCTAssertNil(account.createdOn)
    }

    func testAccountDecoding_NullType() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountNullType)

        XCTAssertEqual(account.id, "account-null-type")
        XCTAssertNil(account.type)
    }

    // MARK: - Computed Properties Tests

    func testAccountIsEnterprise_True() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountEnterprise)
        XCTAssertTrue(account.isEnterprise)
    }

    func testAccountIsEnterprise_False() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountComplete)
        XCTAssertFalse(account.isEnterprise)
    }

    func testAccountTypeDescription_Standard() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountComplete)
        XCTAssertEqual(account.typeDescription, "Standard")
    }

    func testAccountTypeDescription_Enterprise() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountEnterprise)
        XCTAssertEqual(account.typeDescription, "Enterprise")
    }

    func testAccountTypeDescription_Nil() throws {
        let account: Account = try decode(Account.self, from: JSONFixtures.accountNullType)
        XCTAssertEqual(account.typeDescription, "Standard")
    }

    // MARK: - Error Cases

    func testAccountDecoding_MissingId() {
        let json = """
        {
            "name": "Missing ID Account"
        }
        """
        assertDecodingFails(Account.self, from: json)
    }

    func testAccountDecoding_MissingName() {
        let json = """
        {
            "id": "account-no-name"
        }
        """
        assertDecodingFails(Account.self, from: json)
    }

    // MARK: - Comparison Tests

    func testAccountComparison() throws {
        let accountA = Account(id: "1", name: "Aardvark Inc", type: nil, settings: nil, createdOn: nil)
        let accountB = Account(id: "2", name: "Zebra Corp", type: nil, settings: nil, createdOn: nil)

        XCTAssertTrue(accountA < accountB)
        XCTAssertFalse(accountB < accountA)
    }
}

// MARK: - Tunnel Model Tests

final class TunnelModelTests: XCTestCase {

    // MARK: - Basic Decoding Tests

    func testTunnelDecoding_Healthy() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelHealthy)

        XCTAssertEqual(tunnel.id, "tunnel-healthy-123")
        XCTAssertEqual(tunnel.name, "my-dev-tunnel")
        XCTAssertNotNil(tunnel.createdAt)
        XCTAssertNil(tunnel.deletedAt)
        XCTAssertEqual(tunnel.connections.count, 1)
        XCTAssertEqual(tunnel.status, .healthy)
        XCTAssertEqual(tunnel.accountTag, "account-123")
        XCTAssertNotNil(tunnel.metadata)
        XCTAssertEqual(tunnel.metadata?.isLegacy, false)
        XCTAssertEqual(tunnel.metadata?.configSrc, "cloudflare")
    }

    func testTunnelDecoding_Inactive() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelInactive)

        XCTAssertEqual(tunnel.id, "tunnel-inactive-456")
        XCTAssertEqual(tunnel.name, "api-tunnel")
        XCTAssertNil(tunnel.deletedAt)
        XCTAssertTrue(tunnel.connections.isEmpty)
        XCTAssertEqual(tunnel.status, .inactive)
    }

    func testTunnelDecoding_Deleted() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelDeleted)

        XCTAssertEqual(tunnel.id, "tunnel-deleted-789")
        XCTAssertEqual(tunnel.name, "old-tunnel")
        XCTAssertNotNil(tunnel.deletedAt)
        XCTAssertTrue(tunnel.connections.isEmpty)
        XCTAssertNil(tunnel.status)
    }

    func testTunnelDecoding_Minimal() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelMinimal)

        XCTAssertEqual(tunnel.id, "tunnel-minimal")
        XCTAssertEqual(tunnel.name, "minimal-tunnel")
        XCTAssertNotNil(tunnel.createdAt)
        XCTAssertTrue(tunnel.connections.isEmpty)
    }

    func testTunnelDecoding_MultipleConnections() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelMultipleConnections)

        XCTAssertEqual(tunnel.id, "tunnel-multi")
        XCTAssertEqual(tunnel.connections.count, 3)
        XCTAssertEqual(tunnel.status, .degraded)
    }

    // MARK: - Computed Properties Tests

    func testTunnelIsActive_True() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelHealthy)
        XCTAssertTrue(tunnel.isActive)
    }

    func testTunnelIsActive_False_NoConnections() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelInactive)
        XCTAssertFalse(tunnel.isActive)
    }

    func testTunnelIsActive_False_Deleted() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelDeleted)
        XCTAssertFalse(tunnel.isActive)
    }

    func testTunnelIsDeleted() throws {
        let deleted: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelDeleted)
        let notDeleted: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelHealthy)

        XCTAssertTrue(deleted.isDeleted)
        XCTAssertFalse(notDeleted.isDeleted)
    }

    func testTunnelIsHealthy() throws {
        let healthy: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelHealthy)
        let inactive: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelInactive)

        XCTAssertTrue(healthy.isHealthy)
        XCTAssertFalse(inactive.isHealthy)
    }

    func testTunnelActiveConnectionCount() throws {
        let single: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelHealthy)
        let multi: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelMultipleConnections)
        let none: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelInactive)

        XCTAssertEqual(single.activeConnectionCount, 1)
        XCTAssertEqual(multi.activeConnectionCount, 3)
        XCTAssertEqual(none.activeConnectionCount, 0)
    }

    func testTunnelHasConnections() throws {
        let withConnections: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelHealthy)
        let withoutConnections: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelInactive)

        XCTAssertTrue(withConnections.hasConnections)
        XCTAssertFalse(withoutConnections.hasConnections)
    }

    func testTunnelLatestConnection() throws {
        let tunnel: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelMultipleConnections)

        XCTAssertNotNil(tunnel.latestConnection)
        // The latest connection should be the one with the most recent openedAt
        XCTAssertEqual(tunnel.latestConnection?.coloName, "LAX")
    }

    func testTunnelStatusDescription() throws {
        let healthy: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelHealthy)
        let deleted: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelDeleted)
        let inactive: Tunnel = try decode(Tunnel.self, from: JSONFixtures.tunnelInactive)

        XCTAssertEqual(healthy.statusDescription, "Healthy")
        XCTAssertEqual(deleted.statusDescription, "Deleted")
        XCTAssertEqual(inactive.statusDescription, "Inactive")
    }

    // MARK: - TunnelStatus Tests

    func testTunnelStatus_DisplayName() {
        XCTAssertEqual(TunnelStatus.healthy.displayName, "Healthy")
        XCTAssertEqual(TunnelStatus.degraded.displayName, "Degraded")
        XCTAssertEqual(TunnelStatus.inactive.displayName, "Inactive")
        XCTAssertEqual(TunnelStatus.down.displayName, "Down")
    }

    func testTunnelStatus_SystemImage() {
        XCTAssertEqual(TunnelStatus.healthy.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(TunnelStatus.degraded.systemImage, "exclamationmark.triangle.fill")
        XCTAssertEqual(TunnelStatus.inactive.systemImage, "minus.circle.fill")
        XCTAssertEqual(TunnelStatus.down.systemImage, "xmark.circle.fill")
    }

    // MARK: - Error Cases

    func testTunnelDecoding_MissingId() {
        let json = """
        {
            "name": "missing-id",
            "created_at": "2024-01-01T00:00:00Z",
            "connections": []
        }
        """
        assertDecodingFails(Tunnel.self, from: json)
    }

    func testTunnelDecoding_MissingName() {
        let json = """
        {
            "id": "tunnel-no-name",
            "created_at": "2024-01-01T00:00:00Z",
            "connections": []
        }
        """
        assertDecodingFails(Tunnel.self, from: json)
    }

    func testTunnelDecoding_MissingCreatedAt() {
        let json = """
        {
            "id": "tunnel-no-date",
            "name": "no-date-tunnel",
            "connections": []
        }
        """
        assertDecodingFails(Tunnel.self, from: json)
    }

    func testTunnelDecoding_MissingConnections() {
        let json = """
        {
            "id": "tunnel-no-connections",
            "name": "no-connections-tunnel",
            "created_at": "2024-01-01T00:00:00Z"
        }
        """
        assertDecodingFails(Tunnel.self, from: json)
    }
}

// MARK: - Connection Model Tests

final class ConnectionModelTests: XCTestCase {

    // MARK: - Basic Decoding Tests

    func testConnectionDecoding_Complete() throws {
        let connection: Connection = try decode(Connection.self, from: JSONFixtures.connectionComplete)

        XCTAssertEqual(connection.uuid, "connection-uuid-123")
        XCTAssertEqual(connection.coloName, "SJC")
        XCTAssertFalse(connection.isPendingReconnect)
        XCTAssertEqual(connection.clientId, "client-id-456")
        XCTAssertEqual(connection.clientVersion, "2024.1.1")
        XCTAssertNotNil(connection.openedAt)
        XCTAssertEqual(connection.originIp, "192.168.1.100")
        XCTAssertEqual(connection.arch, "darwin_arm64")
    }

    func testConnectionDecoding_Pending() throws {
        let connection: Connection = try decode(Connection.self, from: JSONFixtures.connectionPending)

        XCTAssertEqual(connection.uuid, "connection-pending")
        XCTAssertEqual(connection.coloName, "LAX")
        XCTAssertTrue(connection.isPendingReconnect)
    }

    func testConnectionDecoding_Minimal() throws {
        let connection: Connection = try decode(Connection.self, from: JSONFixtures.connectionMinimal)

        XCTAssertEqual(connection.uuid, "connection-minimal")
        XCTAssertEqual(connection.coloName, "ORD")
        XCTAssertFalse(connection.isPendingReconnect)
        XCTAssertNil(connection.clientId)
        XCTAssertNil(connection.clientVersion)
        XCTAssertNil(connection.originIp)
        XCTAssertNil(connection.arch)
    }

    // MARK: - Computed Properties Tests

    func testConnectionId() throws {
        let connection: Connection = try decode(Connection.self, from: JSONFixtures.connectionComplete)
        XCTAssertEqual(connection.id, connection.uuid)
    }

    func testConnectionIsHealthy() throws {
        let healthy: Connection = try decode(Connection.self, from: JSONFixtures.connectionComplete)
        let pending: Connection = try decode(Connection.self, from: JSONFixtures.connectionPending)

        XCTAssertTrue(healthy.isHealthy)
        XCTAssertFalse(pending.isHealthy)
    }

    func testConnectionVersionDisplay() throws {
        let withVersion: Connection = try decode(Connection.self, from: JSONFixtures.connectionComplete)
        let withoutVersion: Connection = try decode(Connection.self, from: JSONFixtures.connectionMinimal)

        XCTAssertEqual(withVersion.versionDisplay, "2024.1.1")
        XCTAssertEqual(withoutVersion.versionDisplay, "Unknown")
    }

    func testConnectionArchitectureDisplay() throws {
        let withArch: Connection = try decode(Connection.self, from: JSONFixtures.connectionComplete)
        let withoutArch: Connection = try decode(Connection.self, from: JSONFixtures.connectionMinimal)

        XCTAssertEqual(withArch.architectureDisplay, "darwin_arm64")
        XCTAssertEqual(withoutArch.architectureDisplay, "Unknown")
    }

    func testConnectionConnectorInfo() throws {
        let complete: Connection = try decode(Connection.self, from: JSONFixtures.connectionComplete)
        let minimal: Connection = try decode(Connection.self, from: JSONFixtures.connectionMinimal)

        XCTAssertEqual(complete.connectorInfo, "2024.1.1 (darwin_arm64)")
        XCTAssertEqual(minimal.connectorInfo, "Unknown version")
    }

    // MARK: - Date Parsing Tests

    func testConnectionDateParsing_WithFractionalSeconds() throws {
        let connection: Connection = try decode(Connection.self, from: JSONFixtures.connectionComplete)
        XCTAssertNotNil(connection.openedAt)
    }

    func testConnectionDateParsing_WithoutFractionalSeconds() throws {
        let connection: Connection = try decode(Connection.self, from: JSONFixtures.connectionPending)
        XCTAssertNotNil(connection.openedAt)
    }

    // MARK: - Error Cases

    func testConnectionDecoding_MissingUuid() {
        let json = """
        {
            "colo_name": "SJC",
            "is_pending_reconnect": false,
            "opened_at": "2024-06-20T12:00:00Z"
        }
        """
        assertDecodingFails(Connection.self, from: json)
    }

    func testConnectionDecoding_MissingColoName() {
        let json = """
        {
            "uuid": "connection-no-colo",
            "is_pending_reconnect": false,
            "opened_at": "2024-06-20T12:00:00Z"
        }
        """
        assertDecodingFails(Connection.self, from: json)
    }

    func testConnectionDecoding_MissingOpenedAt() {
        let json = """
        {
            "uuid": "connection-no-date",
            "colo_name": "SJC",
            "is_pending_reconnect": false
        }
        """
        assertDecodingFails(Connection.self, from: json)
    }
}

// MARK: - IngressRule Model Tests

final class IngressRuleModelTests: XCTestCase {

    // MARK: - Basic Decoding Tests

    func testIngressRuleDecoding_HTTP() throws {
        let rule: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTP)

        XCTAssertEqual(rule.hostname, "app.example.com")
        XCTAssertNil(rule.path)
        XCTAssertEqual(rule.service, "http://localhost:3000")
        XCTAssertNil(rule.originRequest)
    }

    func testIngressRuleDecoding_HTTPS() throws {
        let rule: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTPS)

        XCTAssertEqual(rule.hostname, "secure.example.com")
        XCTAssertEqual(rule.service, "https://localhost:8443")
    }

    func testIngressRuleDecoding_TCP() throws {
        let rule: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressTCP)

        XCTAssertEqual(rule.hostname, "tcp.example.com")
        XCTAssertEqual(rule.service, "tcp://localhost:5432")
    }

    func testIngressRuleDecoding_SSH() throws {
        let rule: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressSSH)

        XCTAssertEqual(rule.hostname, "ssh.example.com")
        XCTAssertEqual(rule.service, "ssh://localhost:22")
    }

    func testIngressRuleDecoding_CatchAll() throws {
        let rule: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressCatchAll)

        XCTAssertNil(rule.hostname)
        XCTAssertEqual(rule.service, "http_status:404")
        XCTAssertTrue(rule.isCatchAll)
    }

    func testIngressRuleDecoding_WithPath() throws {
        let rule: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressWithPath)

        XCTAssertEqual(rule.hostname, "app.example.com")
        XCTAssertEqual(rule.path, "/api/v1/*")
        XCTAssertEqual(rule.service, "http://localhost:3000")
    }

    // MARK: - Tunnel Configuration Decoding Tests

    func testTunnelConfigurationDecoding() throws {
        let config: TunnelConfiguration = try decode(TunnelConfiguration.self, from: JSONFixtures.tunnelConfiguration)

        XCTAssertEqual(config.config.ingress.count, 3)
        XCTAssertEqual(config.source, "cloudflare")
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.config.warpRouting?.enabled, true)

        // First rule
        let firstRule = config.config.ingress[0]
        XCTAssertEqual(firstRule.hostname, "app.example.com")
        XCTAssertEqual(firstRule.path, "/api")
        XCTAssertEqual(firstRule.service, "http://localhost:3000")
        XCTAssertEqual(firstRule.originRequest?.connectTimeout, 30)
        XCTAssertEqual(firstRule.originRequest?.noTLSVerify, false)

        // Last rule (catch-all)
        let catchAll = config.config.ingress.last!
        XCTAssertNil(catchAll.hostname)
        XCTAssertEqual(catchAll.service, "http_status:404")
        XCTAssertTrue(catchAll.isCatchAll)
    }

    // MARK: - Computed Properties Tests

    func testIngressRuleId() throws {
        let withHostname: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTP)
        let catchAll: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressCatchAll)
        let withPath: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressWithPath)

        XCTAssertEqual(withHostname.id, "app.example.com:http://localhost:3000")
        XCTAssertEqual(catchAll.id, "*:http_status:404")
        XCTAssertEqual(withPath.id, "app.example.com/api/v1/*:http://localhost:3000")
    }

    func testIngressRuleIsCatchAll() throws {
        let regular: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTP)
        let catchAll: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressCatchAll)

        XCTAssertFalse(regular.isCatchAll)
        XCTAssertTrue(catchAll.isCatchAll)
    }

    func testIngressRuleDisplayHostname() throws {
        let regular: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTP)
        let catchAll: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressCatchAll)

        XCTAssertEqual(regular.displayHostname, "app.example.com")
        XCTAssertEqual(catchAll.displayHostname, "*")
    }

    func testIngressRuleDescription() throws {
        let regular: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTP)
        let catchAll: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressCatchAll)
        let withPath: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressWithPath)

        XCTAssertEqual(regular.description, "app.example.com -> http://localhost:3000")
        XCTAssertEqual(catchAll.description, "Catch-all -> http_status:404")
        XCTAssertEqual(withPath.description, "app.example.com/api/v1/* -> http://localhost:3000")
    }

    // MARK: - ServiceType Tests

    func testIngressRuleServiceType() throws {
        let http: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTP)
        let https: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressHTTPS)
        let tcp: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressTCP)
        let ssh: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressSSH)
        let catchAll: IngressRule = try decode(IngressRule.self, from: JSONFixtures.ingressCatchAll)

        XCTAssertEqual(http.serviceType, .http)
        XCTAssertEqual(https.serviceType, .https)
        XCTAssertEqual(tcp.serviceType, .tcp)
        XCTAssertEqual(ssh.serviceType, .ssh)
        XCTAssertEqual(catchAll.serviceType, .httpStatus)
    }

    func testServiceType_From() {
        XCTAssertEqual(ServiceType.from(service: "http://localhost:3000"), .http)
        XCTAssertEqual(ServiceType.from(service: "https://localhost:8443"), .https)
        XCTAssertEqual(ServiceType.from(service: "tcp://localhost:5432"), .tcp)
        XCTAssertEqual(ServiceType.from(service: "ssh://localhost:22"), .ssh)
        XCTAssertEqual(ServiceType.from(service: "rdp://localhost:3389"), .rdp)
        XCTAssertEqual(ServiceType.from(service: "http_status:404"), .httpStatus)
        XCTAssertEqual(ServiceType.from(service: "unix:/var/run/socket"), .unix)
        XCTAssertEqual(ServiceType.from(service: "unknown://localhost"), .unknown)
    }

    func testServiceType_DefaultPort() {
        XCTAssertEqual(ServiceType.http.defaultPort, 80)
        XCTAssertEqual(ServiceType.https.defaultPort, 443)
        XCTAssertEqual(ServiceType.ssh.defaultPort, 22)
        XCTAssertEqual(ServiceType.rdp.defaultPort, 3389)
        XCTAssertEqual(ServiceType.tcp.defaultPort, 0)
    }

    // MARK: - Error Cases

    func testIngressRuleDecoding_MissingService() {
        let json = """
        {
            "hostname": "app.example.com"
        }
        """
        assertDecodingFails(IngressRule.self, from: json)
    }
}

// MARK: - API Response Tests

final class APIResponseModelTests: XCTestCase {

    // MARK: - API Response Tests

    func testAPIResponseDecoding_User() throws {
        let response: APIResponse<User> = try decode(APIResponse<User>.self, from: JSONFixtures.apiResponseUser)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.result.id, "user-123")
        XCTAssertEqual(response.result.email, "user@example.com")
        XCTAssertEqual(response.errors?.count ?? 0, 0)
        XCTAssertEqual(response.messages?.count ?? 0, 0)
    }

    func testAPIResponseDecoding_Accounts() throws {
        let response: APIResponse<[Account]> = try decode(APIResponse<[Account]>.self, from: JSONFixtures.apiResponseAccounts)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.result.count, 2)
        XCTAssertNotNil(response.resultInfo)
        XCTAssertEqual(response.resultInfo?.page, 1)
        XCTAssertEqual(response.resultInfo?.perPage, 25)
        XCTAssertEqual(response.resultInfo?.totalCount, 2)
        XCTAssertEqual(response.resultInfo?.totalPages, 1)
    }

    // MARK: - Error Response Tests

    func testAPIErrorResponseDecoding() throws {
        let response: APIErrorResponse = try decode(APIErrorResponse.self, from: JSONFixtures.apiErrorResponse)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.errors.count, 1)
        XCTAssertEqual(response.errors[0].code, 10000)
        XCTAssertEqual(response.errors[0].message, "Authentication error")
    }

    func testAPIErrorResponseDecoding_WithChain() throws {
        let response: APIErrorResponse = try decode(APIErrorResponse.self, from: JSONFixtures.apiErrorWithChain)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.errors.count, 1)
        XCTAssertEqual(response.errors[0].code, 1001)
        XCTAssertEqual(response.errors[0].message, "Invalid request")
        XCTAssertEqual(response.errors[0].errorChain?.count, 1)
        XCTAssertEqual(response.errors[0].errorChain?[0].code, 1002)
    }

    func testAPIErrorResponseCombinedMessage() throws {
        let response: APIErrorResponse = try decode(APIErrorResponse.self, from: JSONFixtures.apiErrorResponse)
        XCTAssertEqual(response.combinedErrorMessage, "10000: Authentication error")
    }

    // MARK: - ResultInfo Tests

    func testResultInfoHasMorePages() throws {
        let response: APIResponse<[Account]> = try decode(APIResponse<[Account]>.self, from: JSONFixtures.apiResponseAccounts)

        XCTAssertFalse(response.resultInfo?.hasMorePages ?? true)
        XCTAssertNil(response.resultInfo?.nextPage)
    }

    func testResultInfoHasMorePages_True() {
        let resultInfo = ResultInfo(page: 1, perPage: 25, totalCount: 100, totalPages: 4, count: 25)

        XCTAssertTrue(resultInfo.hasMorePages)
        XCTAssertEqual(resultInfo.nextPage, 2)
    }
}
