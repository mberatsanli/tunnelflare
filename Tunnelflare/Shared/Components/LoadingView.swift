//
//  LoadingView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// A reusable loading indicator component.
///
/// LoadingView displays a native macOS spinning progress indicator
/// with an optional text message.
///
/// ## Usage
/// ```swift
/// // Simple loading indicator
/// LoadingView()
///
/// // With message
/// LoadingView(message: "Loading tunnels...")
///
/// // Different sizes
/// LoadingView(message: "Please wait", size: .large)
/// ```
struct LoadingView: View {

    // MARK: - Types

    /// The size of the loading indicator.
    enum Size {
        case small
        case medium
        case large

        var controlSize: ControlSize {
            switch self {
            case .small: return .small
            case .medium: return .regular
            case .large: return .large
            }
        }

        var spacing: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 10
            case .large: return 14
            }
        }

        var font: Font {
            switch self {
            case .small: return .caption
            case .medium: return .subheadline
            case .large: return .body
            }
        }
    }

    /// The layout of the loading indicator and message.
    enum Layout {
        case vertical
        case horizontal
    }

    // MARK: - Properties

    /// The loading message to display (optional).
    var message: String?

    /// The size of the loading indicator.
    var size: Size = .medium

    /// The layout of the indicator and message.
    var layout: Layout = .vertical

    /// Whether to show a background overlay.
    var showBackground: Bool = false

    // MARK: - Body

    var body: some View {
        Group {
            switch layout {
            case .vertical:
                verticalLayout
            case .horizontal:
                horizontalLayout
            }
        }
        .frame(maxWidth: showBackground ? .infinity : nil, maxHeight: showBackground ? .infinity : nil)
        .background(showBackground ? backgroundOverlay : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Layouts

    private var verticalLayout: some View {
        VStack(spacing: size.spacing) {
            ProgressView()
                .controlSize(size.controlSize)

            if let message = message {
                Text(message)
                    .font(size.font)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var horizontalLayout: some View {
        HStack(spacing: size.spacing) {
            ProgressView()
                .controlSize(size.controlSize)

            if let message = message {
                Text(message)
                    .font(size.font)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var backgroundOverlay: some View {
        Color(nsColor: .controlBackgroundColor)
            .opacity(0.8)
    }
}

// MARK: - Centered Loading View

/// A loading view that centers itself in the available space.
struct CenteredLoadingView: View {
    var message: String?
    var size: LoadingView.Size = .medium

    var body: some View {
        LoadingView(message: message, size: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Overlay Loading View

/// A loading overlay that can be placed over existing content.
struct LoadingOverlay: View {
    var message: String?
    var isPresented: Bool

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)

                    if let message = message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(0.2), radius: 10)
                )
            }
            .transition(.opacity)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a loading overlay to the view.
    /// - Parameters:
    ///   - isLoading: Whether the loading overlay should be shown.
    ///   - message: The loading message to display.
    /// - Returns: A view with the loading overlay applied.
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        self.overlay {
            LoadingOverlay(message: message, isPresented: isLoading)
        }
    }
}

// MARK: - Preview

#Preview("Loading Views") {
    VStack(spacing: 40) {
        Group {
            Text("Vertical Layout")
                .font(.headline)

            HStack(spacing: 40) {
                LoadingView(message: "Small", size: .small)
                LoadingView(message: "Medium", size: .medium)
                LoadingView(message: "Large", size: .large)
            }
        }

        Divider()

        Group {
            Text("Horizontal Layout")
                .font(.headline)

            VStack(spacing: 16) {
                LoadingView(message: "Loading tunnels...", layout: .horizontal)
                LoadingView(message: "Please wait", size: .small, layout: .horizontal)
            }
        }

        Divider()

        Group {
            Text("No Message")
                .font(.headline)

            LoadingView()
        }
    }
    .frame(width: 400, height: 500)
    .padding()
}

#Preview("Loading Overlay") {
    VStack {
        Text("Content behind loading overlay")
            .font(.title)

        Text("This content is visible but dimmed")
            .foregroundStyle(.secondary)
    }
    .frame(width: 400, height: 300)
    .loadingOverlay(isLoading: true, message: "Loading tunnels...")
}
