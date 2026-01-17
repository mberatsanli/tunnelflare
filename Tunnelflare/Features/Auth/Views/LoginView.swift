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
        .background(backgroundGradient)
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

    /// The background gradient.
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.1, green: 0.1, blue: 0.15),
                Color(red: 0.08, green: 0.08, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    /// The branding section with logo and title.
    private var brandingSection: some View {
        VStack(spacing: 24) {
            // Cloudflare-inspired logo
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(0.3),
                                Color.orange.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Logo icon
                Image(systemName: "cloud.fill")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .orange.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 4)
            }

            VStack(spacing: 12) {
                Text("Cloudflare Tunnel UI")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Manage your Cloudflare Tunnels\nfrom your Mac.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    /// The login section with API Token input.
    private var loginSection: some View {
        VStack(spacing: 20) {
            // API Token input
            VStack(alignment: .leading, spacing: 8) {
                Text("API Token")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))

                HStack(spacing: 8) {
                    Group {
                        if showToken {
                            TextField("Enter your Cloudflare API Token", text: $apiToken)
                        } else {
                            SecureField("Enter your Cloudflare API Token", text: $apiToken)
                        }
                    }
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)

                    Button(action: { showToken.toggle() }) {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 32)
                }
            }
            .frame(maxWidth: 400)

            // Login button
            Button(action: {
                Task {
                    await activeViewModel.loginWithAPIToken(apiToken.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }) {
                HStack(spacing: 12) {
                    if activeViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }

                    Text(activeViewModel.isLoading ? "Validating..." : "Connect")
                        .font(.headline)
                }
                .frame(minWidth: 200)
                .padding(.vertical, 14)
                .padding(.horizontal, 32)
            }
            .buttonStyle(CloudflareButtonStyle())
            .disabled(!isLoginEnabled)
            .keyboardShortcut(.return, modifiers: [])

            // Loading message
            if activeViewModel.isLoading {
                Text("Validating your API token with Cloudflare...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }

    /// The help section with link to create token.
    private var helpSection: some View {
        VStack(spacing: 12) {
            Text("Need an API Token?")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Link(destination: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!) {
                HStack(spacing: 6) {
                    Text("Create one in Cloudflare Dashboard")
                        .font(.subheadline)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                }
                .foregroundColor(.orange)
            }

            Text("Required permissions: Account:Read, Cloudflare Tunnel:Edit")
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Cloudflare Button Style

/// A custom button style matching Cloudflare branding.
struct CloudflareButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.orange,
                                Color.orange.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: .orange.opacity(configuration.isPressed ? 0.2 : 0.4),
                        radius: configuration.isPressed ? 4 : 8,
                        x: 0,
                        y: configuration.isPressed ? 2 : 4
                    )
            )
            .opacity(isEnabled ? 1.0 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
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
