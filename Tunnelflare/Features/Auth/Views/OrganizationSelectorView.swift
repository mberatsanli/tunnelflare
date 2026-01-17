//
//  OrganizationSelectorView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// A view for selecting an organization when the user has access to multiple.
///
/// This view is displayed after successful login when the user belongs to
/// multiple Cloudflare organizations/accounts.
///
/// ## Features
/// - Lists all available organizations
/// - Single selection with radio buttons
/// - Remembers selection in UserDefaults
/// - Professional, native macOS appearance
///
/// ## Usage
/// ```swift
/// OrganizationSelectorView(
///     organizations: accounts,
///     onSelect: { org in
///         // Handle selection
///     }
/// )
/// ```
struct OrganizationSelectorView: View {
    /// The list of organizations to display.
    let organizations: [Organization]

    /// Callback when an organization is selected.
    let onSelect: (Organization) -> Void

    /// The currently selected organization ID.
    @State private var selectedId: String?

    /// Previously selected organization ID from UserDefaults.
    private var previouslySelectedId: String? {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.selectedOrganizationId)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()
                .padding(.top, 24)

            // Organization list
            organizationList

            Divider()
                .padding(.bottom, 24)

            // Continue button
            continueButton
        }
        .frame(width: 480)
        .padding(32)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Pre-select previously selected organization if available
            if let previousId = previouslySelectedId,
               organizations.contains(where: { $0.id == previousId }) {
                selectedId = previousId
            }
        }
    }

    // MARK: - View Components

    /// The header section with title and description.
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: "building.2")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Select Organization")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You have access to multiple organizations.\nSelect one to continue.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    /// The list of organizations.
    private var organizationList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(organizations) { organization in
                    OrganizationRow(
                        organization: organization,
                        isSelected: selectedId == organization.id,
                        onSelect: {
                            selectedId = organization.id
                        }
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxHeight: 300)
    }

    /// The continue button.
    private var continueButton: some View {
        Button(action: {
            if let selectedId = selectedId,
               let organization = organizations.first(where: { $0.id == selectedId }) {
                onSelect(organization)
            }
        }) {
            Text("Continue")
                .font(.headline)
                .frame(minWidth: 200)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .controlSize(.large)
        .disabled(selectedId == nil)
    }
}

// MARK: - Organization Row

/// A single row in the organization list.
struct OrganizationRow: View {
    /// The organization to display.
    let organization: Organization

    /// Whether this organization is selected.
    let isSelected: Bool

    /// Callback when tapped.
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.orange : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                    }
                }

                // Organization info
                VStack(alignment: .leading, spacing: 4) {
                    Text(organization.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(organizationTypeLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Type badge
                OrganizationTypeBadge(type: organization.type ?? "standard")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.orange.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.orange.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// The label for the organization type.
    private var organizationTypeLabel: String {
        switch (organization.type ?? "standard").lowercased() {
        case "enterprise":
            return "Enterprise Account"
        case "business":
            return "Business Account"
        case "pro":
            return "Pro Account"
        default:
            return "Personal Account"
        }
    }
}

// MARK: - Organization Type Badge

/// A badge showing the organization type.
struct OrganizationTypeBadge: View {
    /// The organization type.
    let type: String

    var body: some View {
        Text(badgeText)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(badgeColor.opacity(0.12))
            )
    }

    /// The badge text based on type.
    private var badgeText: String {
        switch type.lowercased() {
        case "enterprise":
            return "Enterprise"
        case "business":
            return "Business"
        case "pro":
            return "Pro"
        default:
            return "Free"
        }
    }

    /// The badge color based on type.
    private var badgeColor: Color {
        switch type.lowercased() {
        case "enterprise":
            return .purple
        case "business":
            return .blue
        case "pro":
            return .green
        default:
            return .secondary
        }
    }
}

// MARK: - Preview

#Preview("Organization Selector") {
    OrganizationSelectorView(
        organizations: [
            Organization(id: "1", name: "Personal Account", type: "standard", settings: nil, createdOn: nil),
            Organization(id: "2", name: "Acme Corporation", type: "enterprise", settings: nil, createdOn: nil),
            Organization(id: "3", name: "Startup Inc.", type: "business", settings: nil, createdOn: nil)
        ],
        onSelect: { org in
            print("Selected: \(org.name)")
        }
    )
    .frame(height: 500)
}

#Preview("Single Organization") {
    OrganizationSelectorView(
        organizations: [
            Organization(id: "1", name: "Personal Account", type: "standard", settings: nil, createdOn: nil)
        ],
        onSelect: { _ in }
    )
    .frame(height: 400)
}
