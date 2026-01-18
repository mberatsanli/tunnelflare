//
//  PageHeader.swift
//  Tunnelflare
//
//  Created on 2026-01-18.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

// MARK: - PageHeader

/// A standardized page header component for consistent styling across views.
///
/// PageHeader provides a consistent layout with:
/// - Title (required)
/// - Subtitle text or custom view (optional)
/// - Trailing action buttons (optional)
///
/// ## Usage
/// ```swift
/// PageHeader(title: "Tunnels") {
///     // Trailing actions
///     Button("Refresh") { }
///     Button("New") { }
/// } subtitle: {
///     Text("3 tunnels")
/// }
/// ```
struct PageHeader<Actions: View, Subtitle: View>: View {

    // MARK: - Properties

    let title: String
    let actions: Actions
    let subtitle: Subtitle

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Title row
            HStack {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                actions
            }

            // Subtitle row (if provided)
            if Subtitle.self != EmptyView.self {
                HStack {
                    Spacer()
                    subtitle
                }
            }
        }
        .padding()
    }
}

// MARK: - Initializers

extension PageHeader {
    /// Creates a page header with title, actions, and subtitle.
    init(
        title: String,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder subtitle: () -> Subtitle
    ) {
        self.title = title
        self.actions = actions()
        self.subtitle = subtitle()
    }
}

extension PageHeader where Subtitle == EmptyView {
    /// Creates a page header with title and actions, without subtitle.
    init(
        title: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.actions = actions()
        self.subtitle = EmptyView()
    }
}

extension PageHeader where Actions == EmptyView {
    /// Creates a page header with title and subtitle, without actions.
    init(
        title: String,
        @ViewBuilder subtitle: () -> Subtitle
    ) {
        self.title = title
        self.actions = EmptyView()
        self.subtitle = subtitle()
    }
}

extension PageHeader where Actions == EmptyView, Subtitle == EmptyView {
    /// Creates a simple page header with just a title.
    init(title: String) {
        self.title = title
        self.actions = EmptyView()
        self.subtitle = EmptyView()
    }
}

// MARK: - Preview

#Preview("Page Header - Full") {
    VStack(spacing: 0) {
        PageHeader(title: "Tunnels", actions: {
            HStack(spacing: 8) {
                Text("3 tunnels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button(action: {}) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(action: {}) {
                    Label("New Tunnel", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }, subtitle: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Auto-refresh")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text("Updated 2 min ago")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        })

        Divider()

        Spacer()
    }
    .frame(width: 600, height: 200)
}

#Preview("Page Header - Simple") {
    VStack(spacing: 0) {
        PageHeader(title: "Settings")
        Divider()
        Spacer()
    }
    .frame(width: 600, height: 200)
}

#Preview("Page Header - Actions Only") {
    VStack(spacing: 0) {
        PageHeader(title: "Logs", actions: {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Live")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: {}) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Menu {
                    Button("Copy All") { }
                    Button("Clear All") { }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }
        })

        Divider()

        Spacer()
    }
    .frame(width: 600, height: 200)
}
