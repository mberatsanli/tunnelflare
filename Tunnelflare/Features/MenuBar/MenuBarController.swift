//
//  MenuBarController.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import AppKit
import SwiftUI

/// Controller for managing the menu bar status item and popover.
///
/// MenuBarController handles the NSStatusItem lifecycle, click events,
/// and the popover containing the SwiftUI menu bar view.
///
/// ## Usage
/// ```swift
/// let controller = MenuBarController(appState: appState)
/// controller.setup()
/// ```
///
/// ## Note
/// This controller is designed for use with SwiftUI's MenuBarExtra,
/// which handles the status item automatically. However, for advanced
/// use cases requiring direct NSStatusItem control, this class provides
/// a programmatic alternative.
@MainActor
final class MenuBarController: NSObject {

    // MARK: - Properties

    /// The menu bar status item.
    private var statusItem: NSStatusItem?

    /// The popover for displaying the menu bar content.
    private let popover: NSPopover

    /// The icon manager for dynamic status icons.
    private let iconManager: StatusIconManager

    /// The application state.
    private let appState: AppState

    /// Monitor for click-outside-to-dismiss behavior.
    private var eventMonitor: Any?

    // MARK: - Initialization

    /// Creates a new menu bar controller.
    ///
    /// - Parameter appState: The application state to observe.
    init(appState: AppState) {
        self.appState = appState
        self.iconManager = StatusIconManager()
        self.popover = NSPopover()

        super.init()

        configurePopover()
    }

    // MARK: - Setup

    /// Sets up the menu bar status item.
    ///
    /// Call this method once during app initialization to create
    /// the menu bar presence.
    func setup() {
        createStatusItem()
        updateIcon()
    }

    /// Removes the menu bar status item.
    ///
    /// Call this method when the app is terminating or when
    /// the menu bar item should be hidden.
    func teardown() {
        cleanupEventMonitor()

        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    // MARK: - Status Item Management

    /// Creates and configures the status item.
    private func createStatusItem() {
        // Create status item with variable length
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else {
            return
        }

        // Configure button
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Set initial icon
        button.image = iconManager.iconImage(for: .disconnected)
        button.image?.isTemplate = true

        // Set accessibility
        button.setAccessibilityLabel("Cloudflare Tunnel Status")
        button.setAccessibilityHelp("Click to show tunnel status and controls")
    }

    /// Configures the popover appearance and content.
    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true

        // Create the SwiftUI content view
        let contentView = MenuBarView(
            dismissAction: { [weak self] in
                self?.hidePopover()
            }
        )
        .environment(appState)

        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 320, height: 400)
    }

    // MARK: - Icon Updates

    /// Updates the menu bar icon based on current state.
    ///
    /// Call this method whenever the aggregate status changes.
    func updateIcon() {
        guard let button = statusItem?.button else { return }

        let status = appState.aggregateStatus
        let runningCount = appState.localRunningTunnelCount

        // Stop any existing animation
        iconManager.stopAnimation()

        if status == .connecting {
            // Start connecting animation
            iconManager.startAnimation { [weak self] image in
                DispatchQueue.main.async {
                    self?.statusItem?.button?.image = image
                }
            }
        } else {
            // Set static icon
            button.image = iconManager.iconImage(for: status)
            button.image?.isTemplate = true
        }

        // Add badge count next to icon
        if runningCount > 0 {
            button.title = " \(runningCount)"
        } else {
            button.title = ""
        }
    }

    // MARK: - Popover Management

    /// Shows the popover anchored to the status item button.
    func showPopover() {
        guard let button = statusItem?.button else { return }

        // Update the content with fresh state
        let contentView = MenuBarView(
            dismissAction: { [weak self] in
                self?.hidePopover()
            }
        )
        .environment(appState)

        popover.contentViewController = NSHostingController(rootView: contentView)

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Add event monitor to dismiss on click outside
        addEventMonitor()

        // Make the popover's window key to receive keyboard events
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Hides the popover.
    func hidePopover() {
        popover.performClose(nil)
        cleanupEventMonitor()
    }

    /// Toggles the popover visibility.
    func togglePopover() {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    // MARK: - Event Handling

    /// Handles clicks on the status item button.
    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        togglePopover()
    }

    /// Adds an event monitor for click-outside-to-dismiss behavior.
    private func addEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.popover.isShown == true {
                    self?.hidePopover()
                }
            }
        }
    }

    /// Cleans up the event monitor.
    /// This is safe to call from any context.
    private func cleanupEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - NSPopoverDelegate

extension MenuBarController: NSPopoverDelegate {
    nonisolated func popoverWillClose(_ notification: Notification) {
        Task { @MainActor in
            cleanupEventMonitor()
        }
    }
}
