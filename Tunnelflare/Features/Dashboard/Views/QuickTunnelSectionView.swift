//
//  QuickTunnelSectionView.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

// MARK: - QuickTunnelSectionView

/// The "Quick Tunnels" section shown in the dashboard tunnel list.
///
/// Quick tunnels are ephemeral trycloudflare.com tunnels — they are NOT part
/// of the Cloudflare API tunnel list, so they are rendered in their own
/// section above the named tunnels. The section is hidden when no quick
/// tunnels are active.
struct QuickTunnelSectionView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - Body

    var body: some View {
        if !appState.quickTunnels.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                sectionHeader

                ForEach(appState.quickTunnels) { quickTunnel in
                    QuickTunnelRowView(
                        quickTunnel: quickTunnel,
                        onCopy: { appState.copyQuickTunnelURL(id: quickTunnel.id) },
                        onStop: {
                            Task {
                                await appState.stopQuickTunnel(id: quickTunnel.id)
                            }
                        }
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick tunnels section")
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Quick Tunnels")
                .font(.headline)

            Text("Ephemeral")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(Capsule())

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

// MARK: - Quick Tunnel Row View

/// A single quick tunnel row in the dashboard list.
struct QuickTunnelRowView: View {
    let quickTunnel: QuickTunnel
    let onCopy: () -> Void
    let onStop: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            StatusIndicator(status: indicatorStatus)
                .accessibilityHidden(true)

            // Tunnel info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("localhost:\(String(quickTunnel.port))")
                        .font(.system(size: 13, weight: .medium))

                    Text("Quick")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                if let url = quickTunnel.publicURL {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text(quickTunnel.state.errorMessage ?? "Waiting for URL...")
                        .font(.caption)
                        .foregroundStyle(quickTunnel.state.errorMessage != nil ? .red : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Uptime
            Text(uptimeText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            // Actions
            HStack(spacing: 8) {
                if let url = quickTunnel.publicURL {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Copy public URL")
                    .accessibilityLabel("Copy public URL")

                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                    .help("Open in browser")
                    .accessibilityLabel("Open public URL in browser")
                }

                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .disabled(quickTunnel.state.isTransitioning)
                .help("Stop quick tunnel")
                .accessibilityLabel("Stop quick tunnel")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.gray.opacity(0.05) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var indicatorStatus: StatusIndicator.Status {
        switch quickTunnel.state {
        case .running:
            return .connected
        case .starting, .stopping:
            return .connecting
        case .error:
            return .error
        case .stopped:
            return .disconnected
        }
    }

    private var uptimeText: String {
        let duration = Date().timeIntervalSince(quickTunnel.startedAt)
        if duration < 60 {
            return "< 1 min"
        } else if duration < 3600 {
            return "\(Int(duration / 60)) min"
        } else {
            return "\(Int(duration / 3600)) hr"
        }
    }

    private var accessibilityDescription: String {
        var description = "Quick tunnel for port \(quickTunnel.port). "
        if let url = quickTunnel.publicURL {
            description += "Public URL \(url.absoluteString). "
        }
        description += "Running for \(uptimeText)."
        return description
    }
}

// MARK: - Preview

#Preview {
    let appState = AppState()
    appState.quickTunnels = [QuickTunnel(port: 3000)]

    return QuickTunnelSectionView()
        .environment(appState)
        .frame(width: 700)
}
