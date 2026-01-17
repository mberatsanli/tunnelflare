//
//  ErrorView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// A reusable error display component.
///
/// ErrorView displays error information with an icon, title, description,
/// optional retry button, and expandable details section.
///
/// ## Usage
/// ```swift
/// // Simple error
/// ErrorView(title: "Failed to load tunnels")
///
/// // With description and retry
/// ErrorView(
///     title: "Connection Failed",
///     description: "Unable to connect to Cloudflare API.",
///     retryAction: { await loadTunnels() }
/// )
///
/// // With expandable details
/// ErrorView(
///     title: "API Error",
///     description: "Request failed",
///     details: "HTTP 500: Internal Server Error",
///     retryAction: { await retry() }
/// )
/// ```
struct ErrorView: View {

    // MARK: - Types

    /// The style of the error view.
    enum Style {
        /// Full-page error with large icon.
        case fullPage

        /// Inline error with smaller presentation.
        case inline

        /// Banner-style error at top of content.
        case banner
    }

    // MARK: - Properties

    /// The error title.
    let title: String

    /// The error description (optional).
    var description: String?

    /// Additional error details (optional, expandable).
    var details: String?

    /// System image name for the icon.
    var systemImage: String = "exclamationmark.triangle.fill"

    /// The style of the error view.
    var style: Style = .fullPage

    /// Action to perform when retry is tapped (optional).
    var retryAction: (() async -> Void)?

    /// Label for the retry button.
    var retryLabel: String = "Try Again"

    // MARK: - State

    @State private var showDetails = false
    @State private var isRetrying = false

    // MARK: - Body

    var body: some View {
        switch style {
        case .fullPage:
            fullPageView
        case .inline:
            inlineView
        case .banner:
            bannerView
        }
    }

    // MARK: - Full Page View

    private var fullPageView: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            if let description = description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let retryAction = retryAction {
                Button(action: {
                    performRetry(retryAction)
                }) {
                    HStack(spacing: 6) {
                        if isRetrying {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(retryLabel)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isRetrying)
                .padding(.top, 8)
            }

            if let details = details {
                detailsSection(details)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Inline View

    private var inlineView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let description = description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let details = details {
                    inlineDetailsSection(details)
                        .padding(.top, 4)
                }

                if let retryAction = retryAction {
                    Button(action: {
                        performRetry(retryAction)
                    }) {
                        HStack(spacing: 4) {
                            if isRetrying {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(retryLabel)
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRetrying)
                    .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Banner View

    private var bannerView: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let retryAction = retryAction {
                Button(action: {
                    performRetry(retryAction)
                }) {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(retryLabel)
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRetrying)
            }

            if let details = details {
                Button(action: { showDetails.toggle() }) {
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.1))
        .overlay(alignment: .bottom) {
            if showDetails, let details = details {
                VStack(alignment: .leading) {
                    Divider()
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Details Section

    private func detailsSection(_ details: String) -> some View {
        VStack(spacing: 8) {
            Button(action: { showDetails.toggle() }) {
                HStack(spacing: 4) {
                    Text(showDetails ? "Hide Details" : "Show Details")
                        .font(.subheadline)
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showDetails {
                ScrollView {
                    Text(details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxHeight: 150)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDetails)
    }

    private func inlineDetailsSection(_ details: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: { showDetails.toggle() }) {
                HStack(spacing: 4) {
                    Text(showDetails ? "Hide Details" : "Show Details")
                        .font(.caption)
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showDetails {
                Text(details)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDetails)
    }

    // MARK: - Actions

    private func performRetry(_ action: @escaping () async -> Void) {
        isRetrying = true
        Task {
            await action()
            await MainActor.run {
                isRetrying = false
            }
        }
    }
}

// MARK: - Convenience Initializers

extension ErrorView {
    /// Creates an error view from an Error type.
    init(error: Error, style: Style = .fullPage, retryAction: (() async -> Void)? = nil) {
        self.title = "An Error Occurred"
        self.description = error.localizedDescription
        self.style = style
        self.retryAction = retryAction

        // Check for additional details
        if let localizedError = error as? LocalizedError {
            if let recoverySuggestion = localizedError.recoverySuggestion {
                self.details = recoverySuggestion
            }
        }
    }
}

// MARK: - Preview

#Preview("Error Views") {
    VStack(spacing: 20) {
        ErrorView(
            title: "Failed to Load Tunnels",
            description: "Unable to connect to Cloudflare API. Please check your internet connection.",
            details: "HTTP 500: Internal Server Error\nRequest ID: abc-123",
            retryAction: {
                try? await Task.sleep(for: .seconds(1))
            }
        )
        .frame(height: 300)

        Divider()

        ErrorView(
            title: "Connection Lost",
            description: "The tunnel connection was interrupted.",
            style: .inline,
            retryAction: {
                try? await Task.sleep(for: .seconds(1))
            }
        )
        .padding()

        ErrorView(
            title: "Network Error",
            description: "Check your connection",
            details: "Timeout after 30 seconds",
            style: .banner,
            retryAction: {
                try? await Task.sleep(for: .seconds(1))
            }
        )
    }
    .frame(width: 500)
}
