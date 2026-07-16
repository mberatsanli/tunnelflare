//
//  QuickShareView.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

// MARK: - QuickShareSection

/// The quick tunnel section of the menu bar dropdown.
///
/// QuickShareSection displays:
/// - A "Quick Share…" action that reveals a small inline port form
/// - Active quick tunnels with copy and stop controls
///
/// Quick tunnels need no Cloudflare account, so this section is shown
/// regardless of authentication state.
struct QuickShareSection: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    /// Whether the inline port form is visible.
    @State private var isShowingPortForm = false

    /// The port text being edited.
    @State private var portText = ""

    /// Whether a quick tunnel start is in progress.
    @State private var isStarting = false

    /// Error message from the last start attempt, if any.
    @State private var startError: String?

    /// Focus state for the port field.
    @FocusState private var isPortFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Active quick tunnels
            ForEach(appState.quickTunnels) { quickTunnel in
                QuickTunnelRowItem(
                    quickTunnel: quickTunnel,
                    onCopy: { appState.copyQuickTunnelURL(id: quickTunnel.id) },
                    onStop: { stopQuickTunnel(quickTunnel) }
                )
            }

            if isShowingPortForm {
                portForm
            } else {
                MenuBarActionButton(
                    title: "Quick Share…",
                    systemImage: "bolt.fill",
                    action: showPortForm,
                    disabled: !appState.isCloudflaredAvailable
                )
                .accessibilityLabel("Quick share a local port")
                .accessibilityHint(
                    appState.isCloudflaredAvailable
                        ? "Double tap to share a local port via trycloudflare.com"
                        : "cloudflared is not installed"
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick tunnels")
        .task {
            // The dashboard normally checks cloudflared availability, but the
            // menu bar can be used before the dashboard has ever been opened.
            if !appState.isCloudflaredAvailable && !appState.isCheckingCloudflared {
                await appState.checkCloudflaredAvailability()
            }
        }
    }

    // MARK: - Port Form

    private var portForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text("localhost:")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                TextField("3000", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(width: 70)
                    .focused($isPortFieldFocused)
                    .onSubmit(startQuickTunnel)
                    .disabled(isStarting)
                    .accessibilityLabel("Port number")

                Spacer()

                if isStarting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Share") {
                        startQuickTunnel()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(!isPortValid)
                    .accessibilityHint("Double tap to start sharing this port")

                    Button {
                        dismissPortForm()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cancel quick share")
                }
            }

            if let error = startError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var isPortValid: Bool {
        QuickTunnel.validatePort(portText) != nil
    }

    // MARK: - Actions

    private func showPortForm() {
        portText = String(appState.suggestedQuickTunnelPort())
        startError = nil
        isShowingPortForm = true
        isPortFieldFocused = true
    }

    private func dismissPortForm() {
        isShowingPortForm = false
        startError = nil
    }

    private func startQuickTunnel() {
        guard let port = QuickTunnel.validatePort(portText) else { return }

        isStarting = true
        startError = nil

        Task {
            do {
                try await appState.startQuickTunnel(port: port)
                isShowingPortForm = false
            } catch {
                startError = error.localizedDescription
            }
            isStarting = false
        }
    }

    private func stopQuickTunnel(_ quickTunnel: QuickTunnel) {
        Task {
            await appState.stopQuickTunnel(id: quickTunnel.id)
        }
    }
}

// MARK: - Quick Tunnel Row Item

/// A single quick tunnel row in the menu bar dropdown.
struct QuickTunnelRowItem: View {
    let quickTunnel: QuickTunnel
    let onCopy: () -> Void
    let onStop: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            // Tunnel info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("localhost:\(String(quickTunnel.port))")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    Text("Quick")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Copy URL button
            if quickTunnel.publicURL != nil {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Copy public URL")
                .accessibilityLabel("Copy public URL")
            }

            // Stop button
            Button(action: onStop) {
                Image(systemName: quickTunnel.state.isTransitioning ? "hourglass" : "stop.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(quickTunnel.state.isTransitioning)
            .help("Stop quick tunnel")
            .accessibilityLabel("Stop quick tunnel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Quick tunnel for port \(quickTunnel.port). \(subtitleText)")
    }

    private var statusColor: Color {
        switch quickTunnel.state {
        case .running:
            return .green
        case .starting, .stopping:
            return .yellow
        case .error:
            return .red
        case .stopped:
            return .gray
        }
    }

    private var subtitleText: String {
        if let error = quickTunnel.state.errorMessage {
            return error
        }
        if let url = quickTunnel.publicURL {
            return url.host() ?? url.absoluteString
        }
        return "Waiting for URL..."
    }
}

// MARK: - Preview

#Preview {
    QuickShareSection()
        .environment(AppState())
        .frame(width: 320)
}
