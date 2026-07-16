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

        canCheckForUpdatesSubscription = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
    }

    // MARK: - Automatic Checks

    /// Whether Sparkle checks for updates automatically in the background.
    ///
    /// Persisted by Sparkle itself in UserDefaults (`SUEnableAutomaticChecks`).
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: - Public Methods

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
