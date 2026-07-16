//
//  IngressEditorViewModel.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI

/// View model for editing a tunnel's ingress rules.
///
/// IngressEditorViewModel manages a draft copy of the tunnel's remote-managed
/// configuration, supporting add/edit/delete/reorder of ingress rules,
/// validation before save, and optional automatic DNS record creation
/// (CNAME `<hostname>` -> `<tunnel-id>.cfargotunnel.com`).
@Observable
@MainActor
final class IngressEditorViewModel {

    // MARK: - Dependencies

    /// The tunnel whose configuration is being edited.
    var tunnel: Tunnel?

    /// Reference to the app state.
    weak var appState: AppState?

    /// The API client used for configuration and DNS operations.
    var apiClient: CloudflareAPIClient?

    /// Called after a successful save with the saved rules.
    var onSaved: (([IngressRule]) -> Void)?

    // MARK: - Draft State

    /// The editable hostname rules (catch-all excluded).
    var rules: [IngressRule] = []

    /// The catch-all rule, always pinned last and preserved on save.
    var catchAllRule: IngressRule = IngressRuleValidator.defaultCatchAll

    /// The last saved full rule list, for dirty tracking.
    private var savedRules: [IngressRule] = []

    /// The loaded configuration (preserves warp-routing and origin settings).
    private var loadedConfig: IngressConfig?

    /// The source of the configuration ("cloudflare" or "local").
    var configSource: String?

    /// Hostnames that should get a DNS record created on save.
    var pendingDNSHostnames: [String: Zone] = [:]

    // MARK: - Loading State

    /// Whether the configuration is being loaded.
    var isLoading: Bool = false

    /// Whether a save is in progress.
    var isSaving: Bool = false

    /// Error message when loading fails.
    var loadError: String?

    /// Error message when saving fails.
    var saveError: String?

    /// Whether to show the save error alert.
    var showSaveError: Bool = false

    /// Validation issues from the last save attempt.
    var validationIssues: [IngressRuleValidator.Issue] = []

    /// Non-fatal DNS warnings from the last save.
    var dnsWarnings: [String] = []

    /// Whether the last save succeeded (for transient success feedback).
    var didSave: Bool = false

    // MARK: - Zone State

    /// Available zones (domains) for the hostname picker.
    var zones: [Zone] = []

    /// Whether zones are being loaded.
    var isLoadingZones: Bool = false

    /// Error message when loading zones fails.
    var zonesLoadError: String?

    // MARK: - Rule Form State

    /// Whether the rule form sheet is showing.
    var isShowingRuleForm: Bool = false

    /// The index of the rule being edited, or nil when adding a new rule.
    var editingIndex: Int?

    /// The selected zone for the hostname.
    var formZone: Zone?

    /// The subdomain part of the hostname (empty for the zone apex).
    var formSubdomain: String = ""

    /// Whether to enter the hostname manually instead of using a zone.
    var formUseManualHostname: Bool = false

    /// Manually entered hostname (when no zone is available/selected).
    var formManualHostname: String = ""

    /// Optional path to match.
    var formPath: String = ""

    /// The service type (scheme) for the rule.
    var formServiceType: ServiceType = .http

    /// The service host (e.g., "localhost").
    var formServiceHost: String = "localhost"

    /// The service port as text (empty for scheme default).
    var formServicePort: String = "8080"

    /// Whether the service is entered as a raw string instead of
    /// scheme/host/port fields (needed for `http_status:` and `unix:`
    /// services, which the structured fields can't represent).
    var formUseRawService: Bool = false

    /// The raw service string (when `formUseRawService` is on).
    var formRawService: String = ""

    /// Whether to create a DNS record for the hostname on save.
    var formCreateDNSRecord: Bool = true

    // MARK: - Initialization

    init(tunnel: Tunnel? = nil, appState: AppState? = nil, apiClient: CloudflareAPIClient? = nil) {
        self.tunnel = tunnel
        self.appState = appState
        self.apiClient = apiClient
    }

    // MARK: - Setup

    /// Sets up the view model for a specific tunnel.
    func setup(tunnel: Tunnel, appState: AppState) {
        self.tunnel = tunnel
        self.appState = appState
        if apiClient == nil {
            apiClient = CloudflareAPIClient(authManager: .shared)
        }
    }

    // MARK: - Computed Properties

    /// The full rule list in save order (hostname rules + catch-all).
    var fullRules: [IngressRule] {
        rules + [catchAllRule]
    }

    /// Whether the draft differs from the last saved state.
    ///
    /// Pending DNS records count as unsaved work so a failed DNS creation
    /// can be retried with another save.
    var isDirty: Bool {
        fullRules != savedRules || !pendingDNSHostnames.isEmpty
    }

    /// Whether the tunnel is locally managed (remote config is ignored).
    ///
    /// Locally-managed tunnels run from a config file on the connector
    /// machine; edits made here won't affect routing until the tunnel is
    /// migrated to a remote-managed configuration.
    var isLocallyManaged: Bool {
        if let source = configSource {
            return source == "local"
        }
        return tunnel?.metadata?.configSrc == "local"
    }

    /// The full hostname assembled from the form fields.
    var formFullHostname: String {
        if formUseManualHostname {
            return formManualHostname.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let zone = formZone else { return "" }
        let sub = formSubdomain.trimmingCharacters(in: .whitespacesAndNewlines)
        return sub.isEmpty ? zone.name : "\(sub).\(zone.name)"
    }

    /// The optional path from the form, normalized with a leading slash.
    var formNormalizedPath: String {
        let trimmed = formPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
    }

    /// The full service URL assembled from the form fields.
    var formFullService: String {
        if formUseRawService {
            return formRawService.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Strip a pasted scheme so "http://localhost:3000" in the host field
        // doesn't produce "http://http://localhost:3000"
        var host = formServiceHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeRange = host.range(of: "://") {
            host = String(host[schemeRange.upperBound...])
        }

        let port = formServicePort.trimmingCharacters(in: .whitespacesAndNewlines)

        if port.isEmpty {
            return "\(formServiceType.scheme)://\(host)"
        }
        return "\(formServiceType.scheme)://\(host):\(port)"
    }

    /// Whether the rule form can be committed.
    var isFormValid: Bool {
        IngressRuleValidator.isValidHostname(formFullHostname)
            && IngressRuleValidator.isValidService(formFullService)
    }

    /// Whether the DNS toggle applies to the current form state.
    ///
    /// DNS records can only be created when the hostname comes from a
    /// selected zone (the zone ID is needed for the DNS API).
    var canCreateDNSRecord: Bool {
        !formUseManualHostname && formZone != nil
    }

    // MARK: - Loading

    /// Whether the configuration has been loaded (successfully) at least once.
    private var hasLoaded: Bool = false

    /// Loads the tunnel configuration, preferring an already-fetched one.
    ///
    /// - Parameter preloaded: A configuration already loaded elsewhere (e.g.
    ///   by the tunnel detail view model), adopted without a network call.
    ///
    /// No-op once loaded, so returning to the tab preserves draft edits.
    func loadConfiguration(preloaded: TunnelConfiguration? = nil) async {
        guard !hasLoaded else { return }

        if let preloaded = preloaded {
            adopt(configuration: preloaded)
            return
        }

        guard let tunnel = tunnel, !isLoading else { return }
        guard let accountId = appState?.selectedOrganization?.id,
              let apiClient = apiClient else {
            loadError = "No organization selected"
            return
        }

        isLoading = true
        loadError = nil

        defer { isLoading = false }

        do {
            let configuration = try await apiClient.fetchTunnelConfiguration(
                accountId: accountId,
                tunnelId: tunnel.id
            )

            adopt(configuration: configuration)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Adopts a fetched configuration as the saved baseline.
    private func adopt(configuration: TunnelConfiguration) {
        loadedConfig = configuration.config
        configSource = configuration.source

        // A never-configured tunnel has "config": null; treat it as an empty
        // config (normalization appends the default catch-all below).
        let normalized = IngressRuleValidator.normalized(configuration.config?.ingress ?? [])
        rules = normalized.filter { !$0.isCatchAll }
        catchAllRule = normalized.last ?? IngressRuleValidator.defaultCatchAll
        savedRules = fullRules
        pendingDNSHostnames = [:]
        validationIssues = []
        dnsWarnings = []
        hasLoaded = true
    }

    /// Loads available zones for the hostname picker.
    func loadZones() async {
        guard let apiClient = apiClient, zones.isEmpty, !isLoadingZones else { return }

        isLoadingZones = true
        zonesLoadError = nil

        defer { isLoadingZones = false }

        do {
            let fetchedZones = try await apiClient.fetchZones(activeOnly: false)
            zones = fetchedZones.sorted { $0.name < $1.name }

            if formZone == nil, let first = zones.first {
                formZone = first
            }
        } catch {
            zonesLoadError = "Failed to load domains: \(error.localizedDescription)"
            formUseManualHostname = true
        }
    }

    // MARK: - Rule Form Actions

    /// Begins adding a new rule.
    func beginAddRule() {
        editingIndex = nil
        formZone = zones.first
        formSubdomain = ""
        formUseManualHostname = zones.isEmpty
        formManualHostname = ""
        formPath = ""
        formServiceType = .http
        formServiceHost = "localhost"
        formServicePort = "8080"
        formUseRawService = false
        formRawService = ""
        formCreateDNSRecord = true
        isShowingRuleForm = true
    }

    /// Begins editing the rule at the given index.
    func beginEditRule(at index: Int) {
        guard rules.indices.contains(index) else { return }
        let rule = rules[index]

        editingIndex = index
        populateForm(from: rule)
        isShowingRuleForm = true
    }

    /// Populates the form fields from an existing rule.
    private func populateForm(from rule: IngressRule) {
        let hostname = rule.hostname ?? ""

        // Try to match the hostname against a known zone
        if let zone = matchingZone(for: hostname) {
            formZone = zone
            formUseManualHostname = false
            if hostname == zone.name {
                formSubdomain = ""
            } else {
                formSubdomain = String(hostname.dropLast(zone.name.count + 1))
            }
        } else {
            formUseManualHostname = true
            formManualHostname = hostname
            formSubdomain = ""
        }

        formPath = rule.path ?? ""

        let serviceType = rule.serviceType
        if serviceType == .httpStatus || serviceType == .unix || serviceType == .unknown {
            // Not representable in scheme/host/port fields; edit as raw text
            // so the service is preserved verbatim
            formUseRawService = true
            formRawService = rule.service
            formServiceType = .http
            formServiceHost = "localhost"
            formServicePort = ""
        } else {
            formUseRawService = false
            formRawService = ""
            formServiceType = serviceType
            formServiceHost = rule.serviceHost ?? ""
            formServicePort = rule.servicePort.map(String.init) ?? ""
        }

        formCreateDNSRecord = pendingDNSHostnames[hostname] != nil
    }

    /// Finds the most specific zone matching a hostname.
    private func matchingZone(for hostname: String) -> Zone? {
        zones
            .filter { hostname == $0.name || hostname.hasSuffix(".\($0.name)") }
            .max { $0.name.count < $1.name.count }
    }

    /// Commits the rule form, adding or replacing the rule.
    func commitRuleForm() {
        guard isFormValid else { return }

        let hostname = formFullHostname
        let normalizedPath = formNormalizedPath
        let path: String? = normalizedPath.isEmpty ? nil : normalizedPath

        // Preserve per-rule origin settings and raw JSON when editing, so
        // fields the form doesn't touch survive the round-trip
        let editedRule = editingIndex.flatMap { rules.indices.contains($0) ? rules[$0] : nil }

        let rule = IngressRule(
            hostname: hostname,
            path: path,
            service: formFullService,
            originRequest: editedRule?.originRequest,
            raw: editedRule?.raw
        )

        if let index = editingIndex, rules.indices.contains(index) {
            let oldHostname = rules[index].hostname
            if oldHostname != hostname, let oldHostname = oldHostname {
                pendingDNSHostnames.removeValue(forKey: oldHostname)
            }
            rules[index] = rule
        } else {
            rules.append(rule)
        }

        // Track the DNS record request for this hostname
        if formCreateDNSRecord, canCreateDNSRecord, let zone = formZone {
            pendingDNSHostnames[hostname] = zone
        } else {
            pendingDNSHostnames.removeValue(forKey: hostname)
        }

        validationIssues = []
        isShowingRuleForm = false
    }

    /// Cancels the rule form without applying changes.
    func cancelRuleForm() {
        isShowingRuleForm = false
        editingIndex = nil
    }

    // MARK: - Rule List Actions

    /// Deletes the rule at the given index.
    func deleteRule(at index: Int) {
        guard rules.indices.contains(index) else { return }
        if let hostname = rules[index].hostname {
            pendingDNSHostnames.removeValue(forKey: hostname)
        }
        rules.remove(at: index)
        validationIssues = []
    }

    /// Moves a rule up one position.
    func moveRuleUp(at index: Int) {
        guard index > 0, rules.indices.contains(index) else { return }
        rules.swapAt(index, index - 1)
        validationIssues = []
    }

    /// Moves a rule down one position.
    func moveRuleDown(at index: Int) {
        guard rules.indices.contains(index), index < rules.count - 1 else { return }
        rules.swapAt(index, index + 1)
        validationIssues = []
    }

    /// Discards all unsaved changes, restoring the last saved state.
    func discardChanges() {
        let normalized = IngressRuleValidator.normalized(savedRules)
        rules = normalized.filter { !$0.isCatchAll }
        catchAllRule = normalized.last ?? IngressRuleValidator.defaultCatchAll
        pendingDNSHostnames = [:]
        validationIssues = []
        dnsWarnings = []
    }

    // MARK: - Save

    /// Validates and saves the draft configuration to the Cloudflare API,
    /// then creates any requested DNS records.
    func save() async {
        guard let tunnel = tunnel, !isSaving else { return }
        guard let accountId = appState?.selectedOrganization?.id,
              let apiClient = apiClient else {
            saveError = "No organization selected"
            showSaveError = true
            return
        }

        // Validate before saving
        let issues = IngressRuleValidator.validate(fullRules)
        validationIssues = issues
        guard issues.isEmpty else { return }

        isSaving = true
        saveError = nil
        dnsWarnings = []
        didSave = false

        defer { isSaving = false }

        do {
            // Carry the raw config JSON through so fields the editor does
            // not model (originRequest extras, unknown keys) are merged back
            // instead of being clobbered by the full PUT
            let config = IngressConfig(
                ingress: fullRules,
                warpRouting: loadedConfig?.warpRouting,
                originRequest: loadedConfig?.originRequest,
                raw: loadedConfig?.raw
            )

            let updated = try await apiClient.updateTunnelConfiguration(
                accountId: accountId,
                tunnelId: tunnel.id,
                config: config
            )
            configSource = updated.source
            loadedConfig = updated.config ?? config

            // Create requested DNS records; failed ones stay pending so
            // another save retries them
            await createPendingDNSRecords(tunnelId: tunnel.id, apiClient: apiClient)

            savedRules = fullRules

            // Persist locally for quick display
            try? await TunnelStorageManager.shared.saveConfig(
                tunnelId: tunnel.id,
                ingressRules: fullRules
            )

            onSaved?(fullRules)

            didSave = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                didSave = false
            }
        } catch {
            saveError = error.localizedDescription
            showSaveError = true
        }
    }

    /// Creates or updates DNS records for all pending hostnames.
    ///
    /// Successful hostnames are removed from the pending map; failed ones
    /// remain so a later save retries them.
    private func createPendingDNSRecords(tunnelId: String, apiClient: CloudflareAPIClient) async {
        for (hostname, zone) in pendingDNSHostnames {
            do {
                // Only consider CNAME records: a same-name A/AAAA/TXT/MX
                // record must never be converted into a tunnel CNAME
                let existingRecords = try await apiClient.fetchDNSRecords(
                    zoneId: zone.id,
                    recordType: "CNAME",
                    name: hostname
                )

                // Only auto-update CNAMEs that already point at a tunnel;
                // anything else belongs to the user (or another product) and
                // must not be silently rehomed
                if let tunnelCNAME = existingRecords.first(where: { $0.content.hasSuffix(".cfargotunnel.com") }) {
                    try await apiClient.updateTunnelDNSRecord(
                        zoneId: zone.id,
                        recordId: tunnelCNAME.id,
                        name: hostname,
                        tunnelId: tunnelId
                    )
                } else if let existing = existingRecords.first {
                    dnsWarnings.append(
                        "A CNAME record for \(hostname) already exists (pointing to \(existing.content)) and was not modified. Update or remove it in the Cloudflare dashboard to route it to this tunnel."
                    )
                    pendingDNSHostnames.removeValue(forKey: hostname)
                    continue
                } else {
                    // No CNAME exists; creation fails with a clear API error
                    // if a record of another type occupies the name
                    try await apiClient.createTunnelDNSRecord(
                        zoneId: zone.id,
                        name: hostname,
                        tunnelId: tunnelId
                    )
                }

                pendingDNSHostnames.removeValue(forKey: hostname)
            } catch {
                dnsWarnings.append("DNS record for \(hostname) failed: \(error.localizedDescription). Save again to retry.")
            }
        }
    }

    /// Dismisses the save error alert.
    func dismissSaveError() {
        saveError = nil
        showSaveError = false
    }
}
