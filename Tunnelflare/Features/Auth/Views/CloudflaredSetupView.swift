//
//  CloudflaredSetupView.swift
//  Tunnelflare
//
//  Created on 2026-01-18.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// View shown when cloudflared is not installed on the system.
///
/// This view guides the user through installing cloudflared either via:
/// - Homebrew (recommended)
/// - Direct download from GitHub
struct CloudflaredSetupView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - State

    @State private var selectedMethod: InstallMethod = .homebrew
    @State private var showTerminalInstructions = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon and title
            headerSection

            Spacer()
                .frame(height: 40)

            // Installation options
            installationSection

            Spacer()

            // Footer with manual instructions
            footerSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("cloudflared Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tunnelflare needs cloudflared to manage\nyour Cloudflare Tunnels.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Installation Section

    private var installationSection: some View {
        VStack(spacing: 24) {
            // Method picker
            Picker("Installation Method", selection: $selectedMethod) {
                ForEach(InstallMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            // Method description
            VStack(spacing: 16) {
                Text(selectedMethod.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Install button
                Button(action: install) {
                    HStack(spacing: 8) {
                        if appState.isInstallingCloudflared {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(appState.isInstallingCloudflared ? "Installing..." : selectedMethod.buttonTitle)
                    }
                    .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(appState.isInstallingCloudflared)

                // Error message
                if let error = appState.cloudflaredInstallError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(maxWidth: 400)
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button("Manual Installation Instructions") {
                showTerminalInstructions.toggle()
            }
            .buttonStyle(.link)
            .font(.subheadline)

            if showTerminalInstructions {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Run in Terminal:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("brew install cloudflared")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }

            HStack(spacing: 16) {
                Link(destination: URL(string: "https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/")!) {
                    Text("Documentation")
                        .font(.caption)
                }

                Text("•")
                    .foregroundStyle(.tertiary)

                Button("Retry Detection") {
                    Task {
                        await appState.checkCloudflaredAvailability()
                    }
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(appState.isCheckingCloudflared)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func install() {
        Task {
            switch selectedMethod {
            case .homebrew:
                await appState.installCloudflaredWithHomebrew()
            case .direct:
                await appState.installCloudflaredDirect()
            }
        }
    }
}

// MARK: - Install Method

private enum InstallMethod: String, CaseIterable, Identifiable {
    case homebrew
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .homebrew: return "Homebrew"
        case .direct: return "Direct Download"
        }
    }

    var description: String {
        switch self {
        case .homebrew:
            return "Install via Homebrew package manager.\nRecommended for easy updates."
        case .direct:
            return "Download directly from GitHub.\nRequires administrator password."
        }
    }

    var buttonTitle: String {
        switch self {
        case .homebrew: return "Install with Homebrew"
        case .direct: return "Download & Install"
        }
    }
}

// MARK: - Preview

#Preview("Cloudflared Setup") {
    CloudflaredSetupView()
        .environment(AppState())
        .frame(width: 500, height: 600)
}
