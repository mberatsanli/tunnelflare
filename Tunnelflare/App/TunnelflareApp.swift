//
//  TunnelflareApp.swift
//  Tunnelflare
//
//  Created on 2026-01-10.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// Main entry point for the Tunnelflare application.
///
/// This is a menu bar application that provides a native macOS interface
/// for managing Cloudflare Tunnels. The app runs primarily in the menu bar
/// with a dashboard window available for detailed tunnel management.
@main
struct TunnelflareApp: App {
    /// Bridge to AppKit's NSApplicationDelegate for menu bar and system integration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The global application state container.
    @State private var appState = AppState()

    var body: some Scene {
        // Main dashboard window
        WindowGroup("Tunnelflare", id: WindowIdentifier.dashboard) {
            DashboardWindowContent(appState: appState, appDelegate: appDelegate)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: UIConstants.defaultWindowWidth,
            height: UIConstants.defaultWindowHeight
        )
        .commands {
            // Custom menu commands with keyboard shortcuts
            CommandGroup(replacing: .newItem) {
                // Remove default "New" menu item
            }

            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    UpdaterService.shared.checkForUpdates()
                }
                .disabled(!UpdaterService.shared.canCheckForUpdates)

                Divider()

                Button("Open Dashboard") {
                    openDashboard()
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()
            }

            // Tunnel commands
            CommandMenu("Tunnels") {
                Button("Start All Tunnels") {
                    startAllTunnels()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!appState.isAuthenticated)

                Button("Stop All Tunnels") {
                    stopAllTunnels()
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])
                .disabled(!appState.isAuthenticated)

                Divider()

                Button("Refresh Tunnels") {
                    refreshTunnels()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!appState.isAuthenticated)

                Divider()

                Button("New Tunnel...") {
                    appState.isShowingNewTunnelWizard = true
                    openDashboard()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!appState.isAuthenticated)
            }
        }

        // Settings window
        Settings {
            SettingsContainerView()
                .environment(appState)
        }

        // Menu bar extra (menu bar icon and dropdown)
        MenuBarExtra {
            MenuBarView(dismissAction: {
                // The MenuBarExtra handles dismissal automatically
            })
            .environment(appState)
        } label: {
            MenuBarIconLabel(aggregateStatus: appState.aggregateStatus)
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Actions

    /// Opens the main dashboard window.
    private func openDashboard() {
        DashboardWindowOpener.shared.openDashboard()
    }

    /// Starts all tunnels.
    private func startAllTunnels() {
        Task {
            for tunnel in appState.tunnels {
                if appState.localTunnelStates[tunnel.id]?.isRunning != true {
                    try? await appState.startTunnel(tunnelId: tunnel.id)
                }
            }
        }
    }

    /// Stops all tunnels.
    private func stopAllTunnels() {
        Task {
            await appState.stopAllTunnels()
        }
    }

    /// Refreshes tunnel status from API.
    private func refreshTunnels() {
        Task {
            await appState.refreshAllTunnels()
        }
    }

    /// Restores the window frame from UserDefaults.
    private func restoreWindowFrame() {
        guard let savedFrame = DashboardView.loadWindowFrame(),
              let window = NSApp.windows.first(where: { $0.identifier?.rawValue == WindowIdentifier.dashboard }) else {
            return
        }

        // Ensure the saved frame is still visible on screen
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(savedFrame) }) {
            // Adjust if needed to ensure the window is fully visible
            var adjustedFrame = savedFrame
            adjustedFrame = adjustedFrame.intersection(screen.visibleFrame)

            if adjustedFrame.width >= UIConstants.minWindowWidth &&
               adjustedFrame.height >= UIConstants.minWindowHeight {
                window.setFrame(savedFrame, display: true)
            }
        }
    }
}

// MARK: - Window Identifiers

/// Window identifiers for the application's windows.
enum WindowIdentifier {
    static let dashboard = "dashboard"
}

// MARK: - Dashboard Window Content

/// Wrapper view for the dashboard that handles window lifecycle and openWindow action.
struct DashboardWindowContent: View {
    let appState: AppState
    let appDelegate: AppDelegate

    @Environment(\.openWindow) private var openWindow

    /// View model used to restore a persisted session on launch.
    @State private var authViewModel = AuthViewModel()

    var body: some View {
        DashboardView()
            .environment(appState)
            .frame(
                minWidth: UIConstants.minWindowWidth,
                minHeight: UIConstants.minWindowHeight
            )
            .task {
                // Restore any persisted session (API token or OAuth) once on launch.
                authViewModel.setAppState(appState)
                await authViewModel.restoreSession()
            }
            .onAppear {
                appState.isDashboardVisible = true
                appDelegate.appState = appState
                // Store the openWindow action for later use
                DashboardWindowOpener.shared.openWindow = openWindow
            }
            .onDisappear {
                appState.isDashboardVisible = false
            }
    }
}

/// Singleton to store the openWindow action for use outside of SwiftUI views.
@MainActor
final class DashboardWindowOpener {
    static let shared = DashboardWindowOpener()
    var openWindow: OpenWindowAction?

    private init() {}

    func openDashboard() {
        // First try to find and show existing window
        if let window = NSApp.windows.first(where: { $0.title.contains("Tunnelflare") || $0.identifier?.rawValue.contains("dashboard") == true }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // If no window found, use openWindow action to create one
        if let openWindow = openWindow {
            openWindow(id: WindowIdentifier.dashboard)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Menu Bar Icon Label

/// The menu bar icon that updates based on aggregate status.
struct MenuBarIconLabel: View {
    let aggregateStatus: AggregateStatus

    @State private var isAnimating = false

    var body: some View {
        Image("MenuBarIcons")
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                aggregateStatus == .connecting
                    ? Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                    : .default,
                value: isAnimating
            )
            .onAppear {
                isAnimating = aggregateStatus == .connecting
            }
            .onChange(of: aggregateStatus) { _, newStatus in
                isAnimating = newStatus == .connecting
            }
            .accessibilityLabel(StatusIconManager.accessibilityLabel(for: aggregateStatus))
    }
}

// MARK: - Navigation Destination

/// Navigation destinations for the dashboard sidebar.
enum NavigationDestination: Hashable {
    case tunnels
    case logs
    case settings
}

// MARK: - Settings Container View

/// Placeholder view for settings.
struct SettingsContainerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            GeneralSettingsPlaceholder()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TunnelSettingsPlaceholder()
                .tabItem {
                    Label("Tunnels", systemImage: "network")
                }

            AboutSettingsPlaceholder()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct GeneralSettingsPlaceholder: View {
    @State private var launchAtLogin = false
    @State private var showInDock = true
    @State private var notificationsEnabled = true

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show in Dock", isOn: $showInDock)
            }

            Section("Notifications") {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { UpdaterService.shared.automaticallyChecksForUpdates },
                    set: { UpdaterService.shared.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check for Updates…") {
                    UpdaterService.shared.checkForUpdates()
                }
                .disabled(!UpdaterService.shared.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TunnelSettingsPlaceholder: View {
    @State private var autoReconnect = true
    @State private var reconnectDelay = 5
    @State private var refreshInterval = 30

    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Auto-reconnect failed tunnels", isOn: $autoReconnect)

                Picker("Reconnect delay", selection: $reconnectDelay) {
                    Text("3 seconds").tag(3)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                }
            }

            Section("Refresh") {
                Picker("Status refresh interval", selection: $refreshInterval) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutSettingsPlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("TunnelIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)

            Text("Tunnelflare")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version \(AppInfo.fullVersion)")
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 8) {
                Link("Documentation", destination: ExternalLinks.documentation)
                Link("Cloudflare Dashboard", destination: ExternalLinks.cloudfllareDashboard)
                Link("Support", destination: ExternalLinks.support)
            }
            .font(.subheadline)

            Spacer()

            Text(AppInfo.copyright)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
