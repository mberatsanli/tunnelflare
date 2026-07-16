//
//  LoginView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// The login screen for authenticating with Cloudflare.
///
/// This view displays:
/// - Cloudflare branding and app title
/// - API Token input field for authentication
/// - Loading state during token validation
/// - Error messages if authentication fails
///
/// ## Usage
/// ```swift
/// LoginView()
///     .environment(AuthViewModel())
/// ```
struct LoginView: View {
    /// The authentication view model.
    @Environment(AuthViewModel.self) private var viewModel: AuthViewModel?

    /// The app state for authentication updates.
    @Environment(AppState.self) private var appState: AppState?

    /// Internal state for when no view model is provided.
    @State private var internalViewModel = AuthViewModel()

    /// The API token input.
    @State private var apiToken: String = ""

    /// Whether to show the token (vs masked).
    @State private var showToken: Bool = false

    /// Whether the app state has been set on the view model.
    @State private var hasSetAppState = false

    /// Whether the API-token fallback card is expanded.
    @State private var showTokenLogin = false

    /// The actual view model to use.
    private var activeViewModel: AuthViewModel {
        viewModel ?? internalViewModel
    }

    /// Whether the login button should be enabled.
    private var isLoginEnabled: Bool {
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !activeViewModel.isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo and branding
            brandingSection

            Spacer()
                .frame(height: 48)

            // API Token input and login
            loginSection

            Spacer()

            // Help section
            helpSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(background)
        .alert("Login Error", isPresented: Binding(
            get: { activeViewModel.showError },
            set: { _ in activeViewModel.dismissError() }
        )) {
            Button("OK") {
                activeViewModel.dismissError()
            }
        } message: {
            if let message = activeViewModel.errorMessage {
                Text(message)
            }
        }
        .onAppear {
            // Set the app state on the view model so it can update authentication status
            if let appState = appState, !hasSetAppState {
                activeViewModel.setAppState(appState)
                hasSetAppState = true
            }
        }
    }

    // MARK: - View Components

    /// The background - clean system color.
    private var background: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }

    /// The branding section with logo and title.
    private var brandingSection: some View {
        VStack(spacing: 16) {
            // Custom tunnel icon
            Image("TunnelIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)

            VStack(spacing: 8) {
                Text("Tunnelflare")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Text("Manage your Cloudflare Tunnels\nfrom your Mac.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /// The primary sign-in section: OAuth first, API token as a fallback.
    private var loginSection: some View {
        VStack(spacing: 20) {
            // Primary: Sign in with Cloudflare (OAuth + PKCE)
            oauthButton

            // Fallback: API token login, tucked into a disclosure.
            DisclosureGroup(isExpanded: $showTokenLogin) {
                tokenCard
                    .padding(.top, 12)
            } label: {
                // On macOS only the chevron toggles a DisclosureGroup; make the
                // label text toggle it too so the whole row is clickable.
                Button {
                    withAnimation { showTokenLogin.toggle() }
                } label: {
                    Text("Or use an API token")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
        .frame(maxWidth: 380)
    }

    /// The prominent "Sign in with Cloudflare" OAuth button.
    private var oauthButton: some View {
        Button(action: {
            Task {
                await activeViewModel.loginWithOAuth()
            }
        }) {
            HStack(spacing: 8) {
                if activeViewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Sign in with Cloudflare")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.large)
        .disabled(activeViewModel.isLoading)
    }

    /// The API Token input card (fallback authentication).
    private var tokenCard: some View {
        VStack(spacing: 24) {
            // API Token input
            VStack(alignment: .leading, spacing: 8) {
                Text("API Token")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Group {
                        if showToken {
                            TextField("Enter your Cloudflare API Token", text: $apiToken)
                        } else {
                            SecureField("Enter your Cloudflare API Token", text: $apiToken)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button(action: { showToken.toggle() }) {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 28)
                }
            }

            // Login button
            Button(action: {
                Task {
                    await activeViewModel.loginWithAPIToken(apiToken.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }) {
                HStack(spacing: 8) {
                    if activeViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(activeViewModel.isLoading ? "Connecting..." : "Connect")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .disabled(!isLoginEnabled)
            .keyboardShortcut(.return, modifiers: [])

            // Loading message
            if activeViewModel.isLoading {
                Text("Validating your API token with Cloudflare...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// The help section with link to create token.
    private var helpSection: some View {
        VStack(spacing: 8) {
            Text("Need an API Token?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Link(destination: URL(string: "https://github.com/mberatsanli/tunnelflare/blob/main/HOWTO.md#1-getting-your-api-token")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "book")
                            .font(.caption)
                        Text("How to get one")
                            .font(.subheadline)
                    }
                    .foregroundColor(.orange)
                }

                Link(destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!) {
                    HStack(spacing: 4) {
                        Text("Cloudflare Dashboard")
                            .font(.subheadline)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Login View") {
    LoginView()
        .environment(AuthViewModel())
        .frame(width: 600, height: 700)
}

#Preview("Login View - Loading") {
    let viewModel = AuthViewModel()
    // Note: Can't easily set isLoading in preview, but this shows the view
    return LoginView()
        .environment(viewModel)
        .frame(width: 600, height: 700)
}
