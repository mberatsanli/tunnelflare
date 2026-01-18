//
//  StatusIconManager.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import AppKit
import SwiftUI

/// Manages the dynamic menu bar status icons.
///
/// StatusIconManager provides template images for each connection state
/// and handles the animated "connecting" state.
///
/// ## Icon States
/// - **Connected**: Solid filled icon (all tunnels healthy)
/// - **Partial**: Half-filled icon (some tunnels connected)
/// - **Disconnected**: Outline icon (no tunnels connected)
/// - **Connecting**: Animated pulsing icon (transition state)
/// - **Error**: Icon with warning indicator (error condition)
/// - **Unauthenticated**: Outline icon with question mark
///
/// ## Usage
/// ```swift
/// let manager = StatusIconManager()
/// let icon = manager.iconImage(for: .connected)
/// statusButton.image = icon
/// ```
final class StatusIconManager {

    // MARK: - Properties

    /// Timer for the connecting animation.
    private var animationTimer: Timer?

    /// Current frame of the animation (0-3).
    private var animationFrame: Int = 0

    /// Callback for animation frame updates.
    private var animationCallback: ((NSImage?) -> Void)?

    /// Size of the menu bar icons.
    private let iconSize = NSSize(width: 18, height: 18)

    // MARK: - Public Methods

    /// Returns the appropriate icon image for the given status.
    ///
    /// - Parameter status: The aggregate status to represent.
    /// - Returns: An NSImage configured as a template image.
    func iconImage(for status: AggregateStatus) -> NSImage? {
        let image: NSImage?

        switch status {
        case .connected:
            image = createConnectedIcon()
        case .partial:
            image = createPartialIcon()
        case .disconnected:
            image = createDisconnectedIcon()
        case .connecting:
            image = createConnectingIcon(frame: 0)
        case .error:
            image = createErrorIcon()
        case .unauthenticated:
            image = createUnauthenticatedIcon()
        }

        image?.isTemplate = true
        return image
    }

    /// Starts the connecting animation.
    ///
    /// - Parameter callback: Called on each frame with the updated image.
    func startAnimation(callback: @escaping (NSImage?) -> Void) {
        stopAnimation()

        animationCallback = callback
        animationFrame = 0

        // Animate at 4 fps for subtle pulsing effect
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            self.animationFrame = (self.animationFrame + 1) % 4
            let image = self.createConnectingIcon(frame: self.animationFrame)
            image?.isTemplate = true
            self.animationCallback?(image)
        }
    }

    /// Stops the connecting animation.
    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        animationCallback = nil
        animationFrame = 0
    }

    // MARK: - Icon Creation

    /// Creates the connected (solid) icon.
    ///
    /// Uses custom MenuBarIcons for consistent branding.
    private func createConnectedIcon() -> NSImage? {
        return createMenuBarIcon()
    }

    /// Creates the partial connection icon.
    ///
    /// Uses a half-filled cloud to indicate partial connectivity.
    private func createPartialIcon() -> NSImage? {
        // Use a different symbol to indicate partial state
        return createSFSymbolImage(
            systemName: "cloud.bolt.fill",
            pointSize: 16,
            weight: .medium
        )
    }

    /// Creates the disconnected (outline) icon.
    ///
    /// Uses custom MenuBarIcons with reduced opacity for disconnected state.
    private func createDisconnectedIcon() -> NSImage? {
        guard let image = createMenuBarIcon() else { return nil }
        // Return same icon but template will handle the appearance
        return image
    }

    /// Creates the connecting (animated) icon for a given frame.
    ///
    /// - Parameter frame: The animation frame (0-3).
    private func createConnectingIcon(frame: Int) -> NSImage? {
        // Use custom icon - animation handled by opacity changes externally
        return createMenuBarIcon()
    }

    /// Creates the error icon with a warning badge.
    private func createErrorIcon() -> NSImage? {
        return createSFSymbolImage(
            systemName: "exclamationmark.icloud.fill",
            pointSize: 16,
            weight: .medium
        )
    }

    /// Creates the unauthenticated icon.
    private func createUnauthenticatedIcon() -> NSImage? {
        return createSFSymbolImage(
            systemName: "icloud.slash",
            pointSize: 16,
            weight: .medium
        )
    }

    // MARK: - Custom Icon Helper

    /// Creates an NSImage from the custom MenuBarIcons asset.
    ///
    /// - Returns: An NSImage configured for menu bar use.
    private func createMenuBarIcon() -> NSImage? {
        guard let image = NSImage(named: "MenuBarIcons") else { return nil }
        image.size = iconSize
        image.isTemplate = true
        return image
    }

    // MARK: - SF Symbol Helper

    /// Creates an NSImage from an SF Symbol.
    ///
    /// - Parameters:
    ///   - systemName: The SF Symbol name.
    ///   - pointSize: The symbol point size.
    ///   - weight: The symbol weight.
    /// - Returns: An NSImage configured for menu bar use.
    private func createSFSymbolImage(
        systemName: String,
        pointSize: CGFloat,
        weight: NSFont.Weight
    ) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)

        // Ensure proper sizing for menu bar
        if let image = image {
            image.size = iconSize
        }

        return image
    }
}

// MARK: - StatusIconManager + SwiftUI

extension StatusIconManager {
    /// Returns an SF Symbol name for use in SwiftUI views.
    ///
    /// - Parameter status: The aggregate status.
    /// - Returns: The SF Symbol system name.
    static func symbolName(for status: AggregateStatus) -> String {
        switch status {
        case .connected:
            return "cloud.fill"
        case .partial:
            return "cloud.bolt.fill"
        case .disconnected:
            return "cloud"
        case .connecting:
            return "cloud"
        case .error:
            return "exclamationmark.icloud.fill"
        case .unauthenticated:
            return "icloud.slash"
        }
    }

    /// Returns a color for the status indicator.
    ///
    /// - Parameter status: The aggregate status.
    /// - Returns: The SwiftUI color for the status.
    static func color(for status: AggregateStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .partial:
            return .yellow
        case .disconnected:
            return .gray
        case .connecting:
            return .blue
        case .error:
            return .red
        case .unauthenticated:
            return .gray
        }
    }

    /// Returns a status description for accessibility.
    ///
    /// - Parameter status: The aggregate status.
    /// - Returns: A human-readable description.
    static func accessibilityLabel(for status: AggregateStatus) -> String {
        switch status {
        case .connected:
            return "All tunnels connected"
        case .partial:
            return "Some tunnels connected"
        case .disconnected:
            return "No tunnels connected"
        case .connecting:
            return "Connecting to tunnels"
        case .error:
            return "Tunnel error"
        case .unauthenticated:
            return "Not authenticated"
        }
    }
}
