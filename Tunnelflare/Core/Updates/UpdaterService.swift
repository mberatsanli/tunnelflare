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
///
/// Until a real `SUPublicEDKey` is configured (local dev and fork builds
/// ship the placeholder), the updater is never started and all update UI is
/// disabled — starting Sparkle without a valid key would surface a
/// confusing "The updater failed to start" error at the user.
@MainActor
@Observable
final class UpdaterService {

    // MARK: - Configuration

    /// User-facing explanation shown wherever the update UI is disabled
    /// because the build carries no valid Sparkle configuration.
    static let notConfiguredHelp = "Updates are not configured in this build"

    /// Whether Sparkle is configured with a real feed URL and signing key.
    ///
    /// Validates the key's shape rather than comparing against the
    /// `Info.plist` placeholder text: an ed25519 public key is exactly
    /// 32 bytes of base64. This keeps the gate closed for the placeholder
    /// (which is not valid base64) AND for malformed real keys — a typo'd
    /// or truncated key would otherwise start Sparkle straight into its
    /// "The updater failed to start" error dialog.
    static let isConfigured: Bool = {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let keyData = Data(base64Encoded: key),
              keyData.count == 32,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feed.isEmpty
        else {
            return false
        }
        return true
    }()

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
            guard Self.isConfigured else { return }
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// The underlying Sparkle updater controller.
    private let updaterController: SPUStandardUpdaterController

    /// Subscription that mirrors Sparkle's `canCheckForUpdates` into this class.
    private var canCheckForUpdatesSubscription: AnyCancellable?

    // MARK: - Initialization

    private init() {
        // Start the updater immediately so scheduled background checks run —
        // but only when a real signing key is configured; starting Sparkle
        // with the placeholder key fails with an error dialog.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: Self.isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        automaticallyChecksForUpdates = Self.isConfigured
            ? updaterController.updater.automaticallyChecksForUpdates
            : false

        // canCheckForUpdates stays false while the updater is not started,
        // which keeps all "Check for Updates…" UI disabled in
        // unconfigured builds.
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
        guard Self.isConfigured else { return }
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
        .help(
            UpdaterService.isConfigured
                ? "Check for a new version of Tunnelflare"
                : UpdaterService.notConfiguredHelp
        )
    }
}
