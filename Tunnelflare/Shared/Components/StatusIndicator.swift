//
//  StatusIndicator.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// A reusable status indicator component.
///
/// StatusIndicator displays a colored circle indicating the current status,
/// with an optional text label. Uses system colors for proper dark/light mode support.
///
/// ## Usage
/// ```swift
/// // Simple dot indicator
/// StatusIndicator(status: .connected)
///
/// // With label
/// StatusIndicator(status: .connected, showLabel: true)
///
/// // Custom size
/// StatusIndicator(status: .error, size: .large)
/// ```
struct StatusIndicator: View {

    // MARK: - Types

    /// The status to display.
    enum Status: Equatable {
        case connected
        case disconnected
        case connecting
        case partial
        case error
        case unknown

        /// Custom status with explicit color and label.
        case custom(color: Color, label: String)

        /// The color for this status.
        var color: Color {
            switch self {
            case .connected:
                return .green
            case .disconnected:
                return .gray
            case .connecting:
                return .yellow
            case .partial:
                return .orange
            case .error:
                return .red
            case .unknown:
                return .gray.opacity(0.5)
            case .custom(let color, _):
                return color
            }
        }

        /// The label for this status.
        var label: String {
            switch self {
            case .connected:
                return "Connected"
            case .disconnected:
                return "Disconnected"
            case .connecting:
                return "Connecting"
            case .partial:
                return "Partial"
            case .error:
                return "Error"
            case .unknown:
                return "Unknown"
            case .custom(_, let label):
                return label
            }
        }

        static func == (lhs: Status, rhs: Status) -> Bool {
            switch (lhs, rhs) {
            case (.connected, .connected),
                 (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.partial, .partial),
                 (.error, .error),
                 (.unknown, .unknown):
                return true
            case (.custom(let lColor, let lLabel), .custom(let rColor, let rLabel)):
                return lLabel == rLabel && lColor == rColor
            default:
                return false
            }
        }
    }

    /// The size of the indicator.
    enum Size {
        case small
        case medium
        case large

        var dotSize: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            case .large: return 10
            }
        }

        var fontSize: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .subheadline
            }
        }

        var spacing: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            case .large: return 8
            }
        }
    }

    // MARK: - Properties

    /// The status to display.
    let status: Status

    /// The size of the indicator.
    var size: Size = .medium

    /// Whether to show the text label.
    var showLabel: Bool = false

    /// Whether to animate the indicator (for connecting state).
    var animated: Bool = true

    // MARK: - State

    @State private var isAnimating = false

    // MARK: - Body

    var body: some View {
        HStack(spacing: size.spacing) {
            statusDot

            if showLabel {
                Text(status.label)
                    .font(size.fontSize)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.label)
    }

    // MARK: - Subviews

    private var statusDot: some View {
        Circle()
            .fill(status.color)
            .frame(width: size.dotSize, height: size.dotSize)
            .opacity(shouldPulse ? (isAnimating ? 0.4 : 1.0) : 1.0)
            .animation(
                shouldPulse && animated
                    ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
            .onAppear {
                if shouldPulse && animated {
                    isAnimating = true
                }
            }
            .onChange(of: status) { _, newStatus in
                if case .connecting = newStatus {
                    isAnimating = true
                } else {
                    isAnimating = false
                }
            }
    }

    private var shouldPulse: Bool {
        if case .connecting = status {
            return true
        }
        return false
    }
}

// MARK: - Convenience Initializers

extension StatusIndicator {
    /// Creates a status indicator from a TunnelStatus.
    init(tunnelStatus: TunnelStatus?, size: Size = .medium, showLabel: Bool = false) {
        let status: Status
        switch tunnelStatus {
        case .healthy:
            status = .connected
        case .degraded:
            status = .partial
        case .inactive:
            status = .disconnected
        case .down:
            status = .error
        case nil:
            status = .unknown
        }
        self.status = status
        self.size = size
        self.showLabel = showLabel
    }

    /// Creates a status indicator from TunnelRunState.
    init(runState: TunnelRunState?, size: Size = .medium, showLabel: Bool = false) {
        let status: Status
        switch runState {
        case .running:
            status = .connected
        case .starting, .stopping:
            status = .connecting
        case .error:
            status = .error
        case .stopped, nil:
            status = .disconnected
        }
        self.status = status
        self.size = size
        self.showLabel = showLabel
    }

    /// Creates a status indicator from AggregateStatus.
    init(aggregateStatus: AggregateStatus, size: Size = .medium, showLabel: Bool = false) {
        let status: Status
        switch aggregateStatus {
        case .connected:
            status = .connected
        case .partial:
            status = .partial
        case .disconnected:
            status = .disconnected
        case .connecting:
            status = .connecting
        case .error:
            status = .error
        case .unauthenticated:
            status = .unknown
        }
        self.status = status
        self.size = size
        self.showLabel = showLabel
    }
}

// MARK: - Preview

#Preview("Status Indicator States") {
    VStack(alignment: .leading, spacing: 20) {
        Group {
            StatusIndicator(status: .connected, showLabel: true)
            StatusIndicator(status: .disconnected, showLabel: true)
            StatusIndicator(status: .connecting, showLabel: true)
            StatusIndicator(status: .partial, showLabel: true)
            StatusIndicator(status: .error, showLabel: true)
            StatusIndicator(status: .unknown, showLabel: true)
        }

        Divider()

        Text("Sizes")
            .font(.headline)

        HStack(spacing: 20) {
            StatusIndicator(status: .connected, size: .small, showLabel: true)
            StatusIndicator(status: .connected, size: .medium, showLabel: true)
            StatusIndicator(status: .connected, size: .large, showLabel: true)
        }
    }
    .padding()
}
