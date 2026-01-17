//
//  ZoneEndpoints.swift
//  Tunnelflare
//
//  Created on 2026-01-12.
//  Copyright 2026. All rights reserved.
//

import Foundation

// MARK: - Zone Endpoints

/// Endpoints for zone-related operations.
enum ZoneEndpoints {

    // MARK: - List Zones

    /// Endpoint to list all zones the user has access to.
    ///
    /// Returns a list of zones (domains) that the authenticated user
    /// can manage.
    ///
    /// ## API Reference
    /// `GET /zones`
    struct ListZones: Endpoint, PaginatedEndpoint {
        typealias Response = [Zone]

        let path = "zones"
        let method = HTTPMethod.get
        let page: Int
        let perPage: Int

        /// Optional account ID to filter zones by account.
        let accountId: String?

        /// Optional status filter.
        let status: ZoneStatus?

        var queryItems: [URLQueryItem]? {
            var items = paginationQueryItems

            if let accountId = accountId {
                items.append(URLQueryItem(name: "account.id", value: accountId))
            }

            if let status = status {
                items.append(URLQueryItem(name: "status", value: status.rawValue))
            }

            return items
        }

        init(
            accountId: String? = nil,
            status: ZoneStatus? = nil,
            page: Int = 1,
            perPage: Int = 50
        ) {
            self.accountId = accountId
            self.status = status
            self.page = page
            self.perPage = perPage
        }
    }

    // MARK: - Get Zone

    /// Endpoint to get details for a specific zone.
    ///
    /// ## API Reference
    /// `GET /zones/{zone_id}`
    struct GetZone: Endpoint {
        typealias Response = Zone

        let zoneId: String

        var path: String {
            "zones/\(zoneId)"
        }

        let method = HTTPMethod.get

        init(zoneId: String) {
            self.zoneId = zoneId
        }
    }

    // MARK: - List DNS Records

    /// Endpoint to list DNS records for a zone.
    ///
    /// Used to check if a subdomain already exists.
    ///
    /// ## API Reference
    /// `GET /zones/{zone_id}/dns_records`
    struct ListDNSRecords: Endpoint, PaginatedEndpoint {
        typealias Response = [DNSRecord]

        let zoneId: String
        let page: Int
        let perPage: Int

        /// Optional filter by record type (e.g., "CNAME", "A").
        let recordType: String?

        /// Optional filter by record name.
        let name: String?

        var path: String {
            "zones/\(zoneId)/dns_records"
        }

        let method = HTTPMethod.get

        var queryItems: [URLQueryItem]? {
            var items = paginationQueryItems

            if let recordType = recordType {
                items.append(URLQueryItem(name: "type", value: recordType))
            }

            if let name = name {
                items.append(URLQueryItem(name: "name", value: name))
            }

            return items
        }

        init(
            zoneId: String,
            recordType: String? = nil,
            name: String? = nil,
            page: Int = 1,
            perPage: Int = 100
        ) {
            self.zoneId = zoneId
            self.recordType = recordType
            self.name = name
            self.page = page
            self.perPage = perPage
        }
    }

    // MARK: - Create DNS Record

    /// Payload for creating a DNS record.
    struct CreateDNSRecordPayload: Encodable {
        let type: String
        let name: String
        let content: String
        let proxied: Bool
        let ttl: Int
    }

    /// Endpoint to create a DNS record for a zone.
    ///
    /// Used to create CNAME records for tunnel hostnames.
    ///
    /// ## API Reference
    /// `POST /zones/{zone_id}/dns_records`
    struct CreateDNSRecord: Endpoint {
        typealias Response = DNSRecord

        let zoneId: String
        let payload: CreateDNSRecordPayload

        var path: String {
            "zones/\(zoneId)/dns_records"
        }

        let method = HTTPMethod.post

        var body: Encodable? {
            payload
        }

        init(
            zoneId: String,
            recordType: String = "CNAME",
            name: String,
            content: String,
            proxied: Bool = true,
            ttl: Int = 1  // 1 = automatic
        ) {
            self.zoneId = zoneId
            self.payload = CreateDNSRecordPayload(
                type: recordType,
                name: name,
                content: content,
                proxied: proxied,
                ttl: ttl
            )
        }
    }

    // MARK: - Update DNS Record

    /// Endpoint to update an existing DNS record.
    ///
    /// ## API Reference
    /// `PUT /zones/{zone_id}/dns_records/{record_id}`
    struct UpdateDNSRecord: Endpoint {
        typealias Response = DNSRecord

        let zoneId: String
        let recordId: String
        let payload: CreateDNSRecordPayload

        var path: String {
            "zones/\(zoneId)/dns_records/\(recordId)"
        }

        let method = HTTPMethod.put

        var body: Encodable? {
            payload
        }

        init(
            zoneId: String,
            recordId: String,
            recordType: String = "CNAME",
            name: String,
            content: String,
            proxied: Bool = true,
            ttl: Int = 1
        ) {
            self.zoneId = zoneId
            self.recordId = recordId
            self.payload = CreateDNSRecordPayload(
                type: recordType,
                name: name,
                content: content,
                proxied: proxied,
                ttl: ttl
            )
        }
    }
}
