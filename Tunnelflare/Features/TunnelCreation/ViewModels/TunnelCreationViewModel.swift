//
//  TunnelCreationViewModel.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - Wizard Step

/// The steps in the tunnel creation wizard.
enum TunnelWizardStep: Int, CaseIterable {
    /// Step 1: Enter tunnel name.
    case name = 1

    /// Step 2: Configure hostname.
    case hostname = 2

    /// Step 3: Configure target service.
    case service = 3

    /// The display title for this step.
    var title: String {
        switch self {
        case .name:
            return "Tunnel Name"
        case .hostname:
            return "Public Hostname"
        case .service:
            return "Local Service"
        }
    }

    /// The total number of steps.
    static var totalSteps: Int {
        allCases.count
    }

    /// The next step, if available.
    var next: TunnelWizardStep? {
        TunnelWizardStep(rawValue: rawValue + 1)
    }

    /// The previous step, if available.
    var previous: TunnelWizardStep? {
        TunnelWizardStep(rawValue: rawValue - 1)
    }
}

// MARK: - Service Preset

/// Common service presets for quick selection.
struct ServicePreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
    let type: ServiceType

    /// Common development presets.
    static let presets: [ServicePreset] = [
        ServicePreset(name: "React/Node/Rails (3000)", url: "localhost:3000", type: .http),
        ServicePreset(name: "Vite/Vue (5173)", url: "localhost:5173", type: .http),
        ServicePreset(name: "Astro (4322)", url: "localhost:4322", type: .http),
        ServicePreset(name: "Django (8000)", url: "localhost:8000", type: .http),
        ServicePreset(name: "PHP/Apache (80)", url: "localhost:80", type: .http),
        ServicePreset(name: "Nginx (8080)", url: "localhost:8080", type: .http),
        ServicePreset(name: "SSH", url: "localhost:22", type: .ssh),
        ServicePreset(name: "RDP", url: "localhost:3389", type: .rdp),
    ]
}

// MARK: - Tunnel Creation ViewModel

/// View model for the tunnel creation wizard.
///
/// Manages the wizard state, validates input, and performs API calls to create tunnels.
///
/// ## Usage
/// ```swift
/// @State private var viewModel = TunnelCreationViewModel()
///
/// TunnelWizardView()
///     .environment(viewModel)
/// ```
@Observable
@MainActor
final class TunnelCreationViewModel {

    // MARK: - Wizard State

    /// The current step in the wizard.
    var currentStep: TunnelWizardStep = .name

    /// Whether the wizard is currently creating a tunnel.
    var isCreating: Bool = false

    /// Whether the creation was successful.
    var creationSucceeded: Bool = false

    /// Error message if creation failed.
    var errorMessage: String?

    /// Whether to show the error alert.
    var showError: Bool = false

    // MARK: - Step 1: Name

    /// The entered tunnel name.
    var tunnelName: String = "" {
        didSet {
            validateName()
        }
    }

    /// The validation result for the tunnel name.
    var nameValidation: TunnelNameValidator.Result = .invalid("")

    /// Whether the name is currently valid.
    var isNameValid: Bool {
        nameValidation.isValid
    }

    /// The name validation error message, if any.
    var nameError: String? {
        // Only show error if user has started typing
        guard !tunnelName.isEmpty else { return nil }
        return nameValidation.errorMessage
    }

    // MARK: - Step 2: Hostname

    /// The subdomain for the hostname.
    var subdomain: String = "" {
        didSet {
            // Clear warning when subdomain changes
            subdomainWarning = nil
            existingRecord = nil
        }
    }

    /// The selected domain.
    var domain: String = "" {
        didSet {
            // Clear warning when domain changes
            subdomainWarning = nil
            existingRecord = nil
        }
    }

    /// Whether to use manual domain entry.
    var useManualDomain: Bool = false

    /// Available zones (domains) from the user's Cloudflare account.
    var zones: [Zone] = []

    /// The selected zone for the hostname.
    var selectedZone: Zone? {
        didSet {
            if let zone = selectedZone {
                domain = zone.name
            }
        }
    }

    /// Whether zones are currently being loaded.
    var isLoadingZones: Bool = false

    /// Error message when loading zones fails.
    var zonesLoadError: String?

    /// Available domains from the user's Cloudflare account (for backwards compatibility).
    var availableDomains: [String] {
        zones.map { $0.name }
    }

    /// Warning message for subdomain (e.g., already exists).
    var subdomainWarning: String?

    /// Whether the subdomain is being checked.
    var isCheckingSubdomain: Bool = false

    /// Existing DNS record if subdomain already exists.
    var existingRecord: DNSRecord?

    /// The full hostname preview.
    var fullHostname: String {
        let sub = subdomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let dom = domain.trimmingCharacters(in: .whitespacesAndNewlines)

        if sub.isEmpty && dom.isEmpty {
            return ""
        } else if sub.isEmpty {
            return dom
        } else if dom.isEmpty {
            return sub
        } else {
            return "\(sub).\(dom)"
        }
    }

    /// Whether the hostname configuration is valid.
    var isHostnameValid: Bool {
        // Hostname is optional - can be configured later
        // But if entered, it should be somewhat valid
        if subdomain.isEmpty && domain.isEmpty {
            return true // Allow empty for "configure later"
        }
        return !fullHostname.isEmpty
    }

    // MARK: - Step 3: Service

    /// The selected service type.
    var serviceType: ServiceType = .http

    /// The service URL/address (without scheme prefix).
    var serviceURL: String = "localhost:3000"

    /// The full service URL with scheme.
    var fullServiceURL: String {
        let url = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip any existing scheme if present (user might paste full URL)
        let cleanURL: String
        if let schemeRange = url.range(of: "://") {
            cleanURL = String(url[schemeRange.upperBound...])
        } else {
            cleanURL = url
        }

        // Prepend the scheme based on service type
        return "\(serviceType.scheme)://\(cleanURL)"
    }

    /// Whether the service configuration is valid.
    var isServiceValid: Bool {
        let url = serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return !url.isEmpty
    }

    // MARK: - Dependencies

    /// Reference to the app state.
    weak var appState: AppState?

    /// Reference to the API client.
    var apiClient: CloudflareAPIClient?

    // MARK: - Created Tunnel

    /// The tunnel that was created.
    var createdTunnel: Tunnel?

    // MARK: - Initialization

    init(appState: AppState? = nil, apiClient: CloudflareAPIClient? = nil) {
        self.appState = appState
        self.apiClient = apiClient
    }

    // MARK: - Navigation

    /// Whether the user can proceed to the next step.
    var canProceed: Bool {
        switch currentStep {
        case .name:
            return isNameValid
        case .hostname:
            return isHostnameValid
        case .service:
            return isServiceValid
        }
    }

    /// Whether this is the last step.
    var isLastStep: Bool {
        currentStep == .service
    }

    /// Whether this is the first step.
    var isFirstStep: Bool {
        currentStep == .name
    }

    /// Advances to the next step.
    func nextStep() {
        guard canProceed, let next = currentStep.next else { return }
        currentStep = next
    }

    /// Goes back to the previous step.
    func previousStep() {
        guard let previous = currentStep.previous else { return }
        currentStep = previous
    }

    /// Resets the wizard to the initial state.
    func reset() {
        currentStep = .name
        tunnelName = ""
        subdomain = ""
        domain = ""
        selectedZone = nil
        serviceType = .http
        serviceURL = "localhost:3000"
        isCreating = false
        creationSucceeded = false
        errorMessage = nil
        showError = false
        createdTunnel = nil
        nameValidation = .invalid("")
        subdomainWarning = nil
        existingRecord = nil
        isCheckingSubdomain = false
        // Note: Don't reset zones - they can be reused
    }

    // MARK: - Validation

    /// Validates the tunnel name.
    private func validateName() {
        nameValidation = TunnelNameValidator.validate(tunnelName)
    }

    // MARK: - Zone Loading

    /// Loads available zones from Cloudflare.
    func loadZones() async {
        print("[TunnelCreation] loadZones called, apiClient: \(apiClient != nil ? "available" : "nil")")

        guard let apiClient = apiClient else {
            zonesLoadError = "API client not available"
            print("[TunnelCreation] ERROR: API client not available")
            return
        }

        // Don't reload if we already have zones
        guard zones.isEmpty else {
            print("[TunnelCreation] Zones already loaded: \(zones.count)")
            return
        }

        isLoadingZones = true
        zonesLoadError = nil

        do {
            print("[TunnelCreation] Fetching zones from API (all statuses)...")
            let fetchedZones = try await apiClient.fetchZones(activeOnly: false)
            zones = fetchedZones.sorted { $0.name < $1.name }
            print("[TunnelCreation] Loaded \(zones.count) zones: \(zones.map { $0.name })")

            // Auto-select the first zone if available
            if selectedZone == nil, let first = zones.first {
                selectedZone = first
                useManualDomain = false
            }
        } catch {
            zonesLoadError = "Failed to load domains: \(error.localizedDescription)"
            print("[TunnelCreation] ERROR loading zones: \(error)")
            // Fall back to manual entry
            useManualDomain = true
        }

        isLoadingZones = false
    }

    // MARK: - Subdomain Validation

    /// Checks if the current subdomain already exists in DNS.
    func checkSubdomain() async {
        guard let apiClient = apiClient,
              let zone = selectedZone,
              !subdomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            subdomainWarning = nil
            existingRecord = nil
            return
        }

        isCheckingSubdomain = true
        subdomainWarning = nil
        existingRecord = nil

        do {
            let record = try await apiClient.checkSubdomainExists(
                subdomain: subdomain.trimmingCharacters(in: .whitespacesAndNewlines),
                zone: zone
            )

            if let record = record {
                existingRecord = record
                let recordType = record.type
                let content = record.content

                if record.isCNAME && content.contains("cfargotunnel.com") {
                    subdomainWarning = "This subdomain is already configured for a tunnel (points to \(content))"
                } else {
                    subdomainWarning = "This subdomain already has a \(recordType) record pointing to \(content)"
                }
            }
        } catch {
            // Silently ignore errors - subdomain check is not critical
            // The user can still proceed
        }

        isCheckingSubdomain = false
    }

    // MARK: - Service Presets

    /// Applies a service preset.
    func applyPreset(_ preset: ServicePreset) {
        serviceType = preset.type
        // Strip scheme if present (presets should not have schemes, but handle it safely)
        if let schemeRange = preset.url.range(of: "://") {
            serviceURL = String(preset.url[schemeRange.upperBound...])
        } else {
            serviceURL = preset.url
        }
    }

    // MARK: - Tunnel Creation

    /// Creates the tunnel with the configured settings.
    func createTunnel() async {
        guard canProceed else { return }
        guard let appState = appState else {
            showError(message: "App state not available")
            return
        }
        guard let accountId = appState.selectedOrganization?.id else {
            showError(message: "No organization selected")
            return
        }
        guard let apiClient = apiClient else {
            showError(message: "API client not available")
            return
        }

        isCreating = true
        errorMessage = nil

        do {
            // Step 1: Create the tunnel
            let tunnel = try await apiClient.createTunnel(accountId: accountId, name: tunnelName)
            createdTunnel = tunnel

            // Step 2: Configure the tunnel with ingress rules (if hostname provided)
            if !fullHostname.isEmpty {
                let ingressRules: [IngressRule] = [
                    IngressRule(
                        hostname: fullHostname,
                        path: nil,
                        service: fullServiceURL,
                        originRequest: nil
                    ),
                    // Catch-all rule (required)
                    IngressRule(
                        hostname: nil,
                        path: nil,
                        service: "http_status:404",
                        originRequest: nil
                    )
                ]

                let config = IngressConfig(
                    ingress: ingressRules,
                    warpRouting: nil,
                    originRequest: nil
                )

                try await apiClient.updateTunnelConfiguration(
                    accountId: accountId,
                    tunnelId: tunnel.id,
                    config: config
                )

                // Step 3: Create or update DNS record for the hostname
                if let zone = selectedZone {
                    // Use subdomain only for DNS record name
                    let dnsName = subdomain.trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[TunnelCreation] Creating DNS record: '\(dnsName)' in zone \(zone.name) -> \(tunnel.id).cfargotunnel.com")

                    do {
                        // Check if record already exists by fetching it fresh
                        let existingRecords = try await apiClient.fetchDNSRecords(
                            zoneId: zone.id,
                            name: fullHostname
                        )

                        if let existing = existingRecords.first {
                            // Update existing record
                            print("[TunnelCreation] Found existing record (ID: \(existing.id)), updating...")
                            try await apiClient.updateTunnelDNSRecord(
                                zoneId: zone.id,
                                recordId: existing.id,
                                name: dnsName,
                                tunnelId: tunnel.id
                            )
                            print("[TunnelCreation] Updated existing DNS record")
                        } else {
                            // Create new record
                            print("[TunnelCreation] No existing record, creating new...")
                            try await apiClient.createTunnelDNSRecord(
                                zoneId: zone.id,
                                name: dnsName,
                                tunnelId: tunnel.id
                            )
                            print("[TunnelCreation] Created new DNS record")
                        }
                    } catch {
                        // DNS record creation failed, but tunnel was created successfully
                        // Log the error but don't fail the whole operation
                        print("[TunnelCreation] WARNING: DNS record operation failed: \(error)")
                        print("[TunnelCreation] Tunnel created successfully, but you may need to add DNS record manually")
                    }
                }
            }

            // Step 4: Add tunnel to app state (if not already present)
            if !appState.tunnels.contains(where: { $0.id == tunnel.id }) {
                var updatedTunnels = appState.tunnels
                updatedTunnels.insert(tunnel, at: 0)
                appState.tunnels = updatedTunnels
            }

            isCreating = false
            creationSucceeded = true

        } catch let error as APIError {
            isCreating = false
            showError(message: error.localizedDescription)
        } catch {
            isCreating = false
            showError(message: error.localizedDescription)
        }
    }

    // MARK: - Error Handling

    /// Shows an error message.
    private func showError(message: String) {
        errorMessage = message
        showError = true
    }

    /// Dismisses the error alert.
    func dismissError() {
        showError = false
    }
}
