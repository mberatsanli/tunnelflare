//
//  LocalServicesView.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// The Local Services page in the dashboard.
///
/// Lists dev servers detected on localhost and offers one-click actions to
/// copy their URL, open them in the browser, or create a tunnel for them.
/// Scans on appear and polls lightly while visible.
struct LocalServicesView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - Properties

    /// The view model driving the list.
    let viewModel: LocalServicesViewModel

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding()

            Divider()

            content
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local Services")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(subtitleText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var subtitleText: String {
        guard viewModel.hasScanned else {
            return "Scanning for local dev servers..."
        }

        let count = viewModel.services.count
        if count == 0 {
            return "No local dev servers detected"
        }
        return "\(count) service\(count == 1 ? "" : "s") listening on localhost"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasScanned {
            CenteredLoadingView(message: "Scanning local ports...")
        } else if viewModel.services.isEmpty {
            emptyState
        } else {
            serviceList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No local services found")
                .font(.headline)

            Text("Start a dev server (e.g. vite, rails, flask) and it will show up here automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var serviceList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.services) { service in
                    LocalServiceRowView(
                        service: service,
                        onCopyURL: { viewModel.copyURL(for: service) },
                        onOpenInBrowser: { viewModel.openInBrowser(service) },
                        onCreateTunnel: {
                            viewModel.createTunnel(for: service, appState: appState)
                        }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Local Service Row

/// A single local service row with quick actions.
struct LocalServiceRowView: View {
    let service: LocalService
    let onCopyURL: () -> Void
    let onOpenInBrowser: () -> Void
    let onCreateTunnel: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Kind icon
            Image(systemName: service.kind.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(.orange)
                .frame(width: 28, height: 28)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)

            // Service info
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(service.portLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: onCopyURL) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy URL (\(service.localURL.absoluteString))")
                .accessibilityLabel("Copy URL for \(service.displayName)")

                Button(action: onOpenInBrowser) {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help("Open in browser")
                .accessibilityLabel("Open \(service.displayName) in browser")

                Button("Create Tunnel...", action: onCreateTunnel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Create tunnel for \(service.displayName)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isHovered ? Color.orange.opacity(0.4) : Color.gray.opacity(0.15))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(service.displayName), port \(service.port)")
    }
}

// MARK: - Preview

#Preview {
    LocalServicesView(viewModel: LocalServicesViewModel())
        .environment(AppState())
        .frame(width: 600, height: 400)
}
