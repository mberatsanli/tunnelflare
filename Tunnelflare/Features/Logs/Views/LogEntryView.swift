//
//  LogEntryView.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

// MARK: - LogEntryView

/// View for displaying a single log entry.
///
/// LogEntryView shows a log entry with:
/// - Timestamp
/// - Level badge with color coding
/// - Message content in monospace font
/// - Context menu for copying
///
/// ## Usage
/// ```swift
/// ForEach(entries) { entry in
///     LogEntryView(entry: entry)
/// }
/// ```
struct LogEntryView: View {

    // MARK: - Properties

    /// The log entry to display.
    let entry: LogEntry

    /// Whether to show the tunnel badge.
    var showTunnelId: Bool = false

    /// Optional tunnel name to display instead of ID.
    var tunnelName: String? = nil

    /// Whether the entry is currently highlighted (e.g., search match).
    var isHighlighted: Bool = false

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.formattedTime)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 85, alignment: .leading)

            // Level badge
            levelBadge

            // Tunnel ID badge (optional)
            if showTunnelId {
                tunnelIdBadge
            }

            // Message
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(entry.level.color)
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(backgroundView)
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuItems
        }
    }

    // MARK: - Subviews

    private var levelBadge: some View {
        Text(entry.level.rawValue)
            .font(.system(.caption, design: .monospaced).bold())
            .foregroundStyle(entry.level.color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(entry.level.backgroundColor)
            .cornerRadius(4)
            .frame(width: 40)
    }

    private var tunnelIdBadge: some View {
        Text(tunnelName ?? String(entry.tunnelId.prefix(8)))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(4)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if isHighlighted {
            Color.accentColor.opacity(0.1)
        } else if entry.level.isImportant {
            entry.level.backgroundColor.opacity(0.3)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy Message") {
            copyToClipboard(entry.message)
        }

        Button("Copy Full Line") {
            copyToClipboard(entry.rawLine)
        }

        Divider()

        Button("Copy Timestamp") {
            copyToClipboard(entry.formattedTimestamp)
        }

        if showTunnelId {
            Button("Copy Tunnel ID") {
                copyToClipboard(entry.tunnelId)
            }
        }
    }

    // MARK: - Actions

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Compact Log Entry View

/// A more compact version of the log entry view for dense displays.
struct CompactLogEntryView: View {

    let entry: LogEntry

    var body: some View {
        HStack(spacing: 4) {
            // Level indicator
            Circle()
                .fill(entry.level.color)
                .frame(width: 6, height: 6)

            // Time
            Text(entry.formattedTime)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            // Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Log Entry - Info") {
    LogEntryView(entry: LogEntry.previewEntries[0])
        .frame(width: 600)
}

#Preview("Log Entry - Warning") {
    LogEntryView(entry: LogEntry.previewEntries[2])
        .frame(width: 600)
}

#Preview("Log Entry - Error") {
    LogEntryView(entry: LogEntry.previewEntries[3])
        .frame(width: 600)
}

#Preview("Log Entry - With Tunnel ID") {
    LogEntryView(entry: LogEntry.previewEntries[0], showTunnelId: true)
        .frame(width: 700)
}

#Preview("Log Entry - Highlighted") {
    LogEntryView(entry: LogEntry.previewEntries[1], isHighlighted: true)
        .frame(width: 600)
}

#Preview("Compact Log Entry") {
    VStack(alignment: .leading, spacing: 2) {
        ForEach(LogEntry.previewEntries) { entry in
            CompactLogEntryView(entry: entry)
        }
    }
    .frame(width: 400)
    .padding()
}

#Preview("Multiple Log Entries") {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(LogEntry.previewEntries) { entry in
                LogEntryView(entry: entry, showTunnelId: true)
                Divider()
            }
        }
    }
    .frame(width: 700, height: 300)
}
#endif
