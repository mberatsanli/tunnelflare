//
//  LocalServicesViewModel.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import Foundation
import SwiftUI

/// View model for the Local Services list.
///
/// Manages scanning for local dev servers, exposes the results for the
/// dashboard page and the menu bar section, and handles lightweight polling
/// while the list is visible.
///
/// ## Usage
/// ```swift
/// @State private var viewModel = LocalServicesViewModel()
///
/// LocalServicesView()
///     .onAppear { viewModel.startPolling() }
///     .onDisappear { viewModel.stopPolling() }
/// ```
@Observable
@MainActor
final class LocalServicesViewModel {

    // MARK: - Constants

    /// Interval between polls while the list is visible, in seconds.
    static let pollInterval: TimeInterval = 5

    // MARK: - State

    /// The discovered local services, sorted by port.
    var services: [LocalService] = []

    /// Whether a scan is currently in progress.
    var isScanning: Bool = false

    /// Whether the first scan has completed (used to distinguish the initial
    /// loading state from an empty result).
    var hasScanned: Bool = false

    /// Timestamp of the last completed scan.
    var lastScannedAt: Date?

    // MARK: - Private Properties

    /// The scanner performing the lsof enumeration.
    private let scanner = LocalServiceScanner()

    /// The polling task, active while the list is visible.
    private var pollingTask: Task<Void, Never>?

    // MARK: - Public Methods

    /// Performs a single scan and updates the service list.
    func refresh() async {
        guard !isScanning else { return }

        isScanning = true
        defer { isScanning = false }

        services = await scanner.scan()
        hasScanned = true
        lastScannedAt = Date()
    }

    /// Starts lightweight polling: scans immediately, then repeats while
    /// visible. Call from `onAppear`.
    func startPolling() {
        stopPolling()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()

                try? await Task.sleep(for: .seconds(Self.pollInterval))
            }
        }
    }

    /// Stops polling. Call from `onDisappear`.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Row Actions

    /// Copies the service's local URL to the pasteboard.
    ///
    /// - Parameter service: The service whose URL to copy.
    func copyURL(for service: LocalService) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(service.localURL.absoluteString, forType: .string)
    }

    /// Opens the service's local URL in the default browser.
    ///
    /// - Parameter service: The service to open.
    func openInBrowser(_ service: LocalService) {
        NSWorkspace.shared.open(service.localURL)
    }

    /// Requests the new-tunnel wizard prefilled with this service's address.
    ///
    /// - Parameters:
    ///   - service: The service to tunnel.
    ///   - appState: The app state used to trigger the wizard.
    func createTunnel(for service: LocalService, appState: AppState) {
        appState.pendingWizardServiceURL = service.serviceAddress
        appState.isShowingNewTunnelWizard = true
    }
}
