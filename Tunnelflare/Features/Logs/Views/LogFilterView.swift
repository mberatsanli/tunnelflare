//
//  LogFilterView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

// MARK: - LogFilterView

/// View for log filtering controls.
///
/// LogFilterView provides:
/// - Tunnel selector dropdown
/// - Log level filter toggles
/// - Text search field
///
/// ## Usage
/// ```swift
/// LogFilterView(
///     selectedTunnelId: $selectedTunnelId,
///     selectedLevels: $selectedLevels,
///     searchText: $searchText,
///     tunnelOptions: tunnelOptions
/// )
/// ```
struct LogFilterView: View {

    // MARK: - Properties

    /// The selected tunnel ID (nil for all).
    @Binding var selectedTunnelId: String?

    /// The selected log levels.
    @Binding var selectedLevels: Set<LogLevel>

    /// The search text.
    @Binding var searchText: String

    /// Available tunnel options.
    let tunnelOptions: [LogsViewModel.TunnelOption]

    /// Action to clear all filters.
    var onClearFilters: (() -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Tunnel picker
                tunnelPicker

                // Level filters
                levelFilters

                Spacer()

                // Clear filters button
                if isFiltering {
                    Button(action: { onClearFilters?() }) {
                        Label("Clear Filters", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear all filters")
                }
            }

            // Search field
            searchField
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Subviews

    private var tunnelPicker: some View {
        Picker("Tunnel", selection: $selectedTunnelId) {
            ForEach(tunnelOptions) { option in
                Text(option.displayName)
                    .tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 180)
    }

    private var levelFilters: some View {
        HStack(spacing: 4) {
            ForEach(LogLevel.allCases, id: \.self) { level in
                levelToggle(for: level)
            }
        }
    }

    private func levelToggle(for level: LogLevel) -> some View {
        Button(action: { toggleLevel(level) }) {
            Text(level.rawValue)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(selectedLevels.contains(level) ? level.color : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    selectedLevels.contains(level)
                        ? level.backgroundColor
                        : Color.gray.opacity(0.1)
                )
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help("Toggle \(level.displayName) logs")
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search logs...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Computed Properties

    private var isFiltering: Bool {
        selectedTunnelId != nil ||
        selectedLevels.count < LogLevel.allCases.count ||
        !searchText.isEmpty
    }

    // MARK: - Actions

    private func toggleLevel(_ level: LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
    }
}

// MARK: - Compact Filter Bar

/// A more compact filter bar for inline use.
struct CompactLogFilterBar: View {

    @Binding var searchText: String
    @Binding var selectedLevels: Set<LogLevel>

    var body: some View {
        HStack(spacing: 8) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: 200)

            // Level toggles
            ForEach(LogLevel.allCases, id: \.self) { level in
                Toggle(isOn: Binding(
                    get: { selectedLevels.contains(level) },
                    set: { if $0 { selectedLevels.insert(level) } else { selectedLevels.remove(level) } }
                )) {
                    Image(systemName: level.systemImage)
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(selectedLevels.contains(level) ? level.color : Color.secondary)
                .help(level.displayName)
            }
        }
    }
}

// MARK: - Level Filter Menu

/// A dropdown menu for level filtering.
struct LogLevelFilterMenu: View {

    @Binding var selectedLevels: Set<LogLevel>

    var body: some View {
        Menu {
            Button("Select All") {
                selectedLevels = Set(LogLevel.allCases)
            }

            Button("Select None") {
                selectedLevels = []
            }

            Divider()

            ForEach(LogLevel.allCases, id: \.self) { level in
                Toggle(isOn: Binding(
                    get: { selectedLevels.contains(level) },
                    set: { if $0 { selectedLevels.insert(level) } else { selectedLevels.remove(level) } }
                )) {
                    Label(level.displayName, systemImage: level.systemImage)
                }
            }
        } label: {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(filterSummary)
            }
        }
    }

    private var filterSummary: String {
        if selectedLevels.count == LogLevel.allCases.count {
            return "All Levels"
        } else if selectedLevels.isEmpty {
            return "No Levels"
        } else if selectedLevels.count == 1, let level = selectedLevels.first {
            return level.displayName
        } else {
            return "\(selectedLevels.count) Levels"
        }
    }
}

// MARK: - Preview

#Preview("Log Filter View") {
    LogFilterView(
        selectedTunnelId: .constant(nil),
        selectedLevels: .constant(Set(LogLevel.allCases)),
        searchText: .constant(""),
        tunnelOptions: [
            LogsViewModel.TunnelOption(id: nil, name: "All Tunnels"),
            LogsViewModel.TunnelOption(id: "1", name: "my-dev-tunnel"),
            LogsViewModel.TunnelOption(id: "2", name: "api-tunnel")
        ]
    )
    .frame(width: 600)
}

#Preview("Log Filter View - Filtered") {
    LogFilterView(
        selectedTunnelId: .constant("1"),
        selectedLevels: .constant([.info, .warning, .error]),
        searchText: .constant("connection"),
        tunnelOptions: [
            LogsViewModel.TunnelOption(id: nil, name: "All Tunnels"),
            LogsViewModel.TunnelOption(id: "1", name: "my-dev-tunnel"),
            LogsViewModel.TunnelOption(id: "2", name: "api-tunnel")
        ],
        onClearFilters: {}
    )
    .frame(width: 600)
}

#Preview("Compact Filter Bar") {
    CompactLogFilterBar(
        searchText: .constant(""),
        selectedLevels: .constant(Set(LogLevel.allCases))
    )
    .padding()
    .frame(width: 400)
}

#Preview("Level Filter Menu") {
    LogLevelFilterMenu(
        selectedLevels: .constant([.info, .warning])
    )
    .padding()
}
