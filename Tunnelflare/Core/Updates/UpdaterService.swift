//
//  UpdaterService.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import AppKit
import Combine
import Foundation
import Sparkle
import SwiftUI

// MARK: - UpdaterService

/// Manages in-app updates via Sparkle.
///
/// UpdaterService wraps Sparkle's `SPUStandardUpdaterController` and exposes
/// the pieces the UI needs: a manual "Check for Updates…" action and a toggle
/// for automatic background checks.
///
/// ## Configuration
/// The update feed and signing key are configured in `Info.plist`:
/// - `SUFeedURL`: the appcast published by the release workflow
/// - `SUPublicEDKey`: the EdDSA public key matching the CI signing key
///
/// See `docs/RELEASING.md` for key generation and release setup.
@MainActor
@Observable
final class UpdaterService {

    // MARK: - Properties

    /// Shared instance for app-wide access.
    static let shared = UpdaterService()

    /// Whether a manual update check can be started right now.
    private(set) var canCheckForUpdates = false

    /// Whether Sparkle checks for updates automatically in the background.
    ///
    /// Stored here (rather than computed from Sparkle) so SwiftUI's
    /// Observation tracking sees changes and toggles bound to it re-render;
    /// writes are forwarded to Sparkle, which persists the choice in
    /// UserDefaults (`SUEnableAutomaticChecks`).
    var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// The underlying Sparkle updater controller.
    private let updaterController: SPUStandardUpdaterController

    /// Subscription that mirrors Sparkle's `canCheckForUpdates` into this class.
    private var canCheckForUpdatesSubscription: AnyCancellable?

    // MARK: - Initialization

    private init() {
        // Start the updater immediately so scheduled background checks run.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        canCheckForUpdatesSubscription = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    // MARK: - Public Methods

    /// Starts the updater.
    ///
    /// Sparkle begins its scheduled background checks when the shared
    /// instance is created; call this once at app launch so update checks
    /// never depend on the UI lazily touching `shared`.
    func start() {
        // Initialization happens in `init` — this exists to force it at launch.
    }

    /// Starts a user-initiated update check.
    ///
    /// Activates the app first so Sparkle's update window is visible — as a
    /// menu bar app (`LSUIElement`) Tunnelflare is usually not the active
    /// application when this is triggered.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - CheckForUpdatesButton

/// A "Check for Updates…" button wired to `UpdaterService`.
///
/// A dedicated view (rather than an inline `Button` in a `Commands` builder)
/// so Observation tracking reliably re-evaluates the disabled state when
/// `canCheckForUpdates` changes — `Commands` content alone is not
/// re-invalidated dependably on macOS 14.
struct CheckForUpdatesButton: View {
    private let updaterService = UpdaterService.shared

    var body: some View {
        Button("Check for Updates…") {
            updaterService.checkForUpdates()
        }
        .disabled(!updaterService.canCheckForUpdates)
    }
}
