//
//  SettingsView.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

// MARK: - SettingsView

/// The main settings view for the application.
///
/// SettingsView organizes application settings into logical sections:
/// - General: Launch at login, Show in Dock
/// - Notifications: Enable toggle, category toggles
/// - Tunnels: Auto-reconnect, reconnect delay, refresh interval
/// - Advanced: Custom cloudflared path, version display
/// - About: App version, cloudflared version, links
struct SettingsView: View {

    // MARK: - State

    @State private var viewModel = SettingsViewModel()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Settings sections
            ScrollView {
                VStack(spacing: 20) {
                    generalSection
                    Divider()
                    notificationsSection
                    Divider()
                    tunnelsSection
                    Divider()
                    logsSection
                    Divider()
                    advancedSection
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.loadVersionInfo()
            viewModel.refreshLaunchAtLoginStatus()
        }
        .confirmationDialog(
            "Reset Settings",
            isPresented: $viewModel.showResetConfirmation
        ) {
            Button("Reset to Defaults", role: .destructive) {
                viewModel.resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reset all settings to their default values?")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    // MARK: - Header

    private var header: some View {
        PageHeader(title: "Settings")
    }

    // MARK: - General Section

    private var generalSection: some View {
        SettingsSection(title: "General", icon: "gear") {
            VStack(spacing: 12) {
                SettingsToggle(
                    title: "Launch at Login",
                    description: "Automatically start Tunnelflare when you log in to your Mac",
                    isOn: $viewModel.launchAtLogin
                )
                .accessibilityLabel("Launch at Login")
                .accessibilityValue(viewModel.launchAtLogin ? "On" : "Off")
                .accessibilityHint("Toggle to automatically start the app when you log in")

                SettingsToggle(
                    title: "Show in Dock",
                    description: "Display the app icon in the Dock. The menu bar icon is always visible.",
                    isOn: $viewModel.showInDock
                )
                .accessibilityLabel("Show in Dock")
                .accessibilityValue(viewModel.showInDock ? "On" : "Off")
                .accessibilityHint("Toggle to show or hide the app icon in the Dock")

                SettingsToggle(
                    title: "Automatically Check for Updates",
                    description: viewModel.isUpdaterConfigured
                        ? "Check for new versions of Tunnelflare in the background"
                        : UpdaterService.notConfiguredHelp,
                    isOn: $viewModel.automaticallyChecksForUpdates
                )
                .disabled(!viewModel.isUpdaterConfigured)
                .accessibilityLabel("Automatically Check for Updates")
                .accessibilityValue(viewModel.automaticallyChecksForUpdates ? "On" : "Off")
                .accessibilityHint("Toggle to check for app updates automatically")

                HStack {
                    Text("Version \(viewModel.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Check for Updates…") {
                        viewModel.checkForUpdates()
                    }
                    .disabled(!viewModel.canCheckForUpdates)
                    .help(
                        viewModel.isUpdaterConfigured
                            ? "Check for a new version of Tunnelflare"
                            : UpdaterService.notConfiguredHelp
                    )
                    .accessibilityLabel("Check for Updates")
                    .accessibilityHint("Checks for a new version of Tunnelflare now")
                }
            }
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        SettingsSection(title: "Notifications", icon: "bell") {
            VStack(spacing: 12) {
                SettingsToggle(
                    title: "Enable Notifications",
                    description: "Show system notifications for tunnel events",
                    isOn: $viewModel.notificationsEnabled
                )
                .accessibilityLabel("Enable Notifications")
                .accessibilityValue(viewModel.notificationsEnabled ? "On" : "Off")
                .accessibilityHint("Toggle to enable or disable all notifications")

                if viewModel.notificationsEnabled {
                    VStack(spacing: 8) {
                        SettingsToggle(
                            title: "Disconnect Notifications",
                            description: "Notify when a tunnel loses connection",
                            isOn: $viewModel.notifyOnDisconnect,
                            indent: true
                        )
                        .accessibilityLabel("Disconnect Notifications")
                        .accessibilityValue(viewModel.notifyOnDisconnect ? "On" : "Off")

                        SettingsToggle(
                            title: "Reconnect Notifications",
                            description: "Notify when a tunnel reconnects",
                            isOn: $viewModel.notifyOnReconnect,
                            indent: true
                        )
                        .accessibilityLabel("Reconnect Notifications")
                        .accessibilityValue(viewModel.notifyOnReconnect ? "On" : "Off")

                        SettingsToggle(
                            title: "Crash Notifications",
                            description: "Notify when cloudflared crashes unexpectedly",
                            isOn: $viewModel.notifyOnCrash,
                            indent: true
                        )
                        .accessibilityLabel("Crash Notifications")
                        .accessibilityValue(viewModel.notifyOnCrash ? "On" : "Off")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button("Open System Notification Settings") {
                    viewModel.openNotificationPreferences()
                }
                .buttonStyle(.link)
                .font(.caption)
                .accessibilityLabel("Open System Notification Settings")
                .accessibilityHint("Opens macOS System Preferences to notification settings")
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.notificationsEnabled)
        }
    }

    // MARK: - Tunnels Section

    private var tunnelsSection: some View {
        SettingsSection(title: "Tunnels", icon: "network") {
            VStack(spacing: 16) {
                SettingsToggle(
                    title: "Auto-Reconnect",
                    description: "Automatically reconnect tunnels when they disconnect",
                    isOn: $viewModel.autoReconnect
                )
                .accessibilityLabel("Auto-Reconnect")
                .accessibilityValue(viewModel.autoReconnect ? "On" : "Off")
                .accessibilityHint("Toggle to automatically reconnect disconnected tunnels")

                if viewModel.autoReconnect {
                    SettingsPicker(
                        title: "Reconnect Delay",
                        description: "Time to wait before attempting to reconnect",
                        selection: $viewModel.reconnectDelaySeconds,
                        options: ReconnectDelayOption.allCases.map { ($0.rawValue, $0.displayName) }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityLabel("Reconnect Delay")
                    .accessibilityHint("Select how long to wait before reconnecting")
                }

                SettingsPicker(
                    title: "Status Refresh Interval",
                    description: "How often to check tunnel status from Cloudflare",
                    selection: $viewModel.refreshIntervalSeconds,
                    options: RefreshIntervalOption.allCases.map { ($0.rawValue, $0.displayName) }
                )
                .accessibilityLabel("Status Refresh Interval")
                .accessibilityHint("Select how often to refresh tunnel status")
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.autoReconnect)
        }
    }

    // MARK: - Logs Section

    private var logsSection: some View {
        SettingsSection(title: "Logs", icon: "doc.text") {
            VStack(spacing: 16) {
                // Log display mode
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log Display Mode")
                            .font(.subheadline)

                        Text("How log entries are displayed in the tunnel detail view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("", selection: $viewModel.logDisplayMode) {
                        ForEach(LogDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    Text(viewModel.logDisplayMode.description)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Log Display Mode")
                .accessibilityHint("Choose between terminal-style or row-by-row log display")

                // Note: Logs are always saved per-tunnel at ~/.tunnelflare/tunnels/<id>/logs/
                Text("Logs are automatically saved per-tunnel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        SettingsSection(title: "Advanced", icon: "terminal") {
            VStack(spacing: 16) {
                // Custom cloudflared path
                VStack(alignment: .leading, spacing: 8) {
                    SettingsToggle(
                        title: "Use Custom cloudflared Path",
                        description: "Specify a custom path to the cloudflared binary",
                        isOn: $viewModel.useCustomCloudflaredPath
                    )
                    .accessibilityLabel("Use Custom cloudflared Path")
                    .accessibilityValue(viewModel.useCustomCloudflaredPath ? "On" : "Off")

                    if viewModel.useCustomCloudflaredPath {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                TextField("Path to cloudflared", text: $viewModel.customCloudflaredPath)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Custom cloudflared path")
                                    .accessibilityHint("Enter the full path to cloudflared binary")
                                    .onChange(of: viewModel.customCloudflaredPath) { _, newValue in
                                        Task {
                                            await viewModel.validateCustomPath(newValue)
                                        }
                                    }

                                Button("Browse...") {
                                    viewModel.browseForCloudflared()
                                }
                                .accessibilityLabel("Browse for cloudflared")
                                .accessibilityHint("Opens a file picker to select cloudflared binary")
                            }

                            if viewModel.isValidatingPath {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text("Validating...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel("Validating path")
                            } else if let error = viewModel.pathValidationError {
                                Label(error, systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Error: \(error)")
                            } else if viewModel.isPathValid {
                                Label("Valid cloudflared binary", systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Valid cloudflared binary found")
                            }

                            Button("Clear Custom Path") {
                                viewModel.clearCustomPath()
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                            .accessibilityLabel("Clear custom path")
                            .accessibilityHint("Removes the custom path and uses default location")
                        }
                        .padding(.leading, 24)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: viewModel.useCustomCloudflaredPath)

                Divider()

                // Version information
                VStack(alignment: .leading, spacing: 8) {
                    Text("cloudflared Version")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)

                    if viewModel.isLoadingVersion {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking version...")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Checking cloudflared version")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Version:")
                                    .foregroundStyle(.secondary)
                                Text(viewModel.cloudflaredVersion)
                                    .fontWeight(.medium)
                                    .fontDesign(.monospaced)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("cloudflared version \(viewModel.cloudflaredVersion)")

                            HStack {
                                Text("Path:")
                                    .foregroundStyle(.secondary)
                                Text(viewModel.cloudflaredPath)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Located at \(viewModel.cloudflaredPath)")
                        }
                        .font(.subheadline)
                    }

                    Button("Refresh") {
                        Task {
                            await viewModel.loadVersionInfo()
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                    .accessibilityLabel("Refresh version")
                    .accessibilityHint("Recheck the cloudflared version")
                }

                Divider()

                // Reset settings
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Settings")
                            .font(.headline)
                        Text("Restore all settings to their default values")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Reset...") {
                        viewModel.showResetConfirmation = true
                    }
                    .accessibilityLabel("Reset all settings")
                    .accessibilityHint("Shows confirmation dialog to reset all settings to defaults")
                }
            }
        }
    }

}

// MARK: - Settings Section

/// A container for a group of related settings.
private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(.leading, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) section")
    }
}

// MARK: - Settings Toggle

/// A toggle row with title and description.
private struct SettingsToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var indent: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.leading, indent ? 24 : 0)
    }
}

// MARK: - Settings Picker

/// A picker row with title and description.
private struct SettingsPicker: View {
    let title: String
    let description: String
    @Binding var selection: Int
    let options: [(Int, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview

#Preview("Settings View") {
    SettingsView()
        .frame(width: 600, height: 800)
}
