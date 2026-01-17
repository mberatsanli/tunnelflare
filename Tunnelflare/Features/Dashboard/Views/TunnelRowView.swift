//
//  TunnelRowView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// A single tunnel row in the tunnel list.
///
/// TunnelRowView displays:
/// - Status indicator (colored dot)
/// - Tunnel name
/// - Type badge (Local/Remote)
/// - Primary service or hostname
/// - Created date
/// - Control buttons (Start/Stop, Logs)
struct TunnelRowView: View {

    // MARK: - Properties

    /// The tunnel to display.
    let tunnel: Tunnel

    /// The local run state for this tunnel.
    let localState: TunnelRunState?

    /// Called when the row is selected.
    let onSelect: () -> Void

    /// Called when the toggle button is pressed.
    let onToggle: () -> Void

    // MARK: - State

    @State private var isHovered = false

    // MARK: - Body

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Status indicator
                StatusIndicator(runState: localState, size: .medium)

                // Tunnel info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tunnel.name)
                            .font(.headline)
                            .lineLimit(1)

                        typeBadge
                    }

                    HStack(spacing: 12) {
                        // Service info
                        if let service = primaryService {
                            Label(service, systemImage: serviceIcon)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        // Created date
                        Text("Created \(tunnel.createdAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Connection info
                connectionInfo
                    .frame(width: 120, alignment: .trailing)

                // Control buttons
                controlButtons
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(backgroundColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view tunnel details")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        var description = "Tunnel \(tunnel.name). "
        description += statusText + ". "

        if isRunningLocally {
            description += "Running locally. "
        } else if tunnel.isActive {
            description += "Running remotely. "
        }

        if tunnel.hasConnections {
            description += "\(tunnel.activeConnectionCount) active connector\(tunnel.activeConnectionCount == 1 ? "" : "s"). "
        }

        return description
    }

    // MARK: - Subviews

    private var typeBadge: some View {
        Group {
            if isRunningLocally {
                BadgeView(text: "Local", color: .blue)
                    .accessibilityLabel("Running locally")
            } else if tunnel.isActive {
                BadgeView(text: "Remote", color: .gray)
                    .accessibilityLabel("Running remotely")
            }
        }
    }

    private var connectionInfo: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(statusTextColor)

            if tunnel.hasConnections {
                Text("\(tunnel.activeConnectionCount) connector\(tunnel.activeConnectionCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true) // Included in parent accessibility label
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            // Start/Stop toggle
            if canToggle {
                Button(action: onToggle) {
                    Image(systemName: toggleIcon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isTransitioning)
                .help(toggleHelp)
                .accessibilityLabel(toggleHelp)
                .accessibilityHint("Double tap to \(isRunningLocally ? "stop" : "start") this tunnel")
            }

            // View details button (chevron)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        if isHovered {
            return Color.gray.opacity(0.1)
        }
        return Color.clear
    }

    private var isRunningLocally: Bool {
        localState?.isRunning == true
    }

    private var isTransitioning: Bool {
        localState?.isTransitioning == true
    }

    private var canToggle: Bool {
        // Can toggle if not a remote-only tunnel
        localState != nil || !tunnel.isActive
    }

    private var toggleIcon: String {
        guard let state = localState else {
            return "play.fill"
        }

        switch state {
        case .running:
            return "stop.fill"
        case .starting, .stopping:
            return "hourglass"
        case .stopped, .error:
            return "play.fill"
        }
    }

    private var toggleHelp: String {
        guard let state = localState else {
            return "Start tunnel"
        }

        switch state {
        case .running:
            return "Stop tunnel"
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        case .stopped:
            return "Start tunnel"
        case .error:
            return "Retry"
        }
    }

    private var statusText: String {
        guard let state = localState else {
            if tunnel.isActive {
                return "Connected"
            }
            return "Not connected"
        }

        switch state {
        case .running(_, let startedAt):
            return formatUptime(since: startedAt)
        case .starting:
            return "Starting..."
        case .stopping:
            return "Stopping..."
        case .stopped:
            return "Stopped"
        case .error:
            return "Error"
        }
    }

    private var statusTextColor: Color {
        guard let state = localState else {
            return tunnel.isActive ? .green : .secondary
        }

        switch state {
        case .running:
            return .green
        case .starting, .stopping:
            return .yellow
        case .error:
            return .red
        case .stopped:
            return .secondary
        }
    }

    private var primaryService: String? {
        // Would come from ingress rules in real implementation
        // For now, return nil or a placeholder
        nil
    }

    private var serviceIcon: String {
        "globe"
    }

    // MARK: - Helpers

    private func formatUptime(since date: Date) -> String {
        let duration = Date().timeIntervalSince(date)

        if duration < 60 {
            return "Up < 1 min"
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            return "Up \(minutes) min"
        } else if duration < 86400 {
            let hours = Int(duration / 3600)
            return "Up \(hours) hr\(hours == 1 ? "" : "s")"
        } else {
            let days = Int(duration / 86400)
            return "Up \(days) day\(days == 1 ? "" : "s")"
        }
    }
}

// MARK: - Badge View

/// A small badge view for displaying labels.
struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Preview

#Preview("Tunnel Row - Running") {
    VStack(spacing: 0) {
        TunnelRowView(
            tunnel: .preview,
            localState: .running(pid: 1234, startedAt: Date().addingTimeInterval(-3600)),
            onSelect: { },
            onToggle: { }
        )

        Divider()

        TunnelRowView(
            tunnel: .inactivePreview,
            localState: nil,
            onSelect: { },
            onToggle: { }
        )

        Divider()

        TunnelRowView(
            tunnel: .preview,
            localState: .starting,
            onSelect: { },
            onToggle: { }
        )
    }
    .frame(width: 700)
    .environment(AppState())
}
