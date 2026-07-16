//
//  IngressEditorView.swift
//  Tunnelflare
//
//  Created on 2026-07-16.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// An editable list of a tunnel's ingress rules.
///
/// IngressEditorView lets the user add, edit, delete, and reorder ingress
/// rules, then save the configuration back to Cloudflare. Adding a hostname
/// can optionally create the matching CNAME DNS record. The catch-all rule
/// is always pinned last and preserved on save.
struct IngressEditorView: View {

    // MARK: - Environment

    @Environment(AppState.self) private var appState

    // MARK: - Properties

    /// The tunnel whose ingress rules are edited.
    let tunnel: Tunnel

    /// The editor view model.
    ///
    /// Owned by the parent (tunnel detail view) so draft edits survive
    /// switching tabs, which destroys and recreates this view.
    let viewModel: IngressEditorViewModel

    /// A configuration already fetched by the parent, adopted on first load
    /// to avoid a duplicate API call.
    var preloadedConfiguration: TunnelConfiguration?

    /// Called after a successful save with the saved rules.
    var onSaved: (([IngressRule]) -> Void)?

    // MARK: - Body

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(spacing: 0) {
            if viewModel.isLoading && viewModel.rules.isEmpty {
                CenteredLoadingView(message: "Loading configuration...")
            } else if let error = viewModel.loadError {
                loadErrorView(error)
            } else {
                editorContent
            }
        }
        .onAppear {
            viewModel.setup(tunnel: tunnel, appState: appState)
            viewModel.onSaved = onSaved
        }
        .task {
            await viewModel.loadConfiguration(preloaded: preloadedConfiguration)
            await viewModel.loadZones()
        }
        .sheet(isPresented: $viewModel.isShowingRuleForm) {
            IngressRuleFormView(viewModel: viewModel)
        }
        .alert(
            "Save Failed",
            isPresented: $viewModel.showSaveError
        ) {
            Button("OK") {
                viewModel.dismissSaveError()
            }
        } message: {
            if let error = viewModel.saveError {
                Text(error)
            }
        }
    }

    // MARK: - Editor Content

    private var editorContent: some View {
        VStack(spacing: 0) {
            // Warning banner for locally-managed tunnels
            if viewModel.isLocallyManaged {
                locallyManagedBanner
            }

            // Toolbar
            editorToolbar
                .padding()

            Divider()

            // Rule list
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if viewModel.rules.isEmpty {
                        emptyRulesView
                    } else {
                        rulesList
                    }

                    // Pinned catch-all rule
                    catchAllSection

                    // Validation issues
                    if !viewModel.validationIssues.isEmpty {
                        validationIssuesView
                    }

                    // DNS warnings from the last save
                    if !viewModel.dnsWarnings.isEmpty {
                        dnsWarningsView
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Button(action: {
                viewModel.beginAddRule()
            }) {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSaving)

            Spacer()

            if viewModel.didSave {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            if viewModel.isDirty {
                Button("Discard") {
                    viewModel.discardChanges()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSaving)

                Button(action: {
                    Task { await viewModel.save() }
                }) {
                    HStack(spacing: 4) {
                        if viewModel.isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(viewModel.isSaving)
            }
        }
    }

    // MARK: - Rules List

    private var rulesList: some View {
        LazyVStack(spacing: 1) {
            ForEach(Array(viewModel.rules.enumerated()), id: \.offset) { index, rule in
                EditableIngressRuleRow(
                    rule: rule,
                    index: index,
                    isFirst: index == 0,
                    isLast: index == viewModel.rules.count - 1,
                    hasPendingDNS: rule.hostname.map { viewModel.pendingDNSHostnames[$0] != nil } ?? false,
                    onEdit: { viewModel.beginEditRule(at: index) },
                    onDelete: { viewModel.deleteRule(at: index) },
                    onMoveUp: { viewModel.moveRuleUp(at: index) },
                    onMoveDown: { viewModel.moveRuleDown(at: index) }
                )
            }
        }
        .background(Color(nsColor: .separatorColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Catch-all Section

    private var catchAllSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catch-all")
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Any other traffic")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text("Always evaluated last")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(viewModel.catchAllRule.service)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Banners & Messages

    private var locallyManagedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text("This tunnel uses a local configuration file. Changes saved here are stored in Cloudflare but ignored until the tunnel is migrated to a remote-managed configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }

    private var validationIssuesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(viewModel.validationIssues.enumerated()), id: \.offset) { _, issue in
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)

                    Text(issue.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var dnsWarningsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(viewModel.dnsWarnings.enumerated()), id: \.offset) { _, warning in
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyRulesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No Ingress Rules")
                .font(.headline)

            Text("Add a rule to route a public hostname to a local service.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func loadErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Failed to Load Configuration")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.loadConfiguration() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - EditableIngressRuleRow

/// A row displaying an ingress rule with edit, delete, and reorder controls.
struct EditableIngressRuleRow: View {
    let rule: IngressRule
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    let hasPendingDNS: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Rule number
            Text("\(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Hostname + path
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.displayHostname)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let path = rule.path {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if hasPendingDNS {
                    Label("DNS record on save", systemImage: "network.badge.shield.half.filled")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            // Arrow
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Service
            HStack(spacing: 6) {
                Image(systemName: rule.serviceType.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(rule.service)
                    .font(.system(.subheadline, design: .monospaced))
            }

            Spacer()

            // Controls (visible on hover)
            if isHovered {
                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isFirst)
                    .help("Move up")

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLast)
                    .help("Move down")

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit rule")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete rule")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Edit", action: onEdit)
            Divider()
            Button("Move Up", action: onMoveUp)
                .disabled(isFirst)
            Button("Move Down", action: onMoveDown)
                .disabled(isLast)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - IngressRuleFormView

/// A form sheet for adding or editing an ingress rule.
struct IngressRuleFormView: View {

    /// The editor view model owning the form state.
    @Bindable var viewModel: IngressEditorViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(viewModel.editingIndex == nil ? "Add Ingress Rule" : "Edit Ingress Rule")
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                hostnameSection
                serviceSection
                dnsSection
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Spacer()

                Button("Cancel") {
                    viewModel.cancelRuleForm()
                }
                .keyboardShortcut(.cancelAction)

                Button(viewModel.editingIndex == nil ? "Add" : "Update") {
                    viewModel.commitRuleForm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!viewModel.isFormValid)
            }
            .padding()
        }
        .frame(width: 480, height: 520)
    }

    // MARK: - Hostname Section

    private var hostnameSection: some View {
        Section("Public Hostname") {
            if viewModel.isLoadingZones {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading domains...")
                        .foregroundStyle(.secondary)
                }
            } else if !viewModel.zones.isEmpty {
                Toggle("Enter hostname manually", isOn: $viewModel.formUseManualHostname)
            }

            if viewModel.formUseManualHostname || viewModel.zones.isEmpty {
                TextField("Hostname", text: $viewModel.formManualHostname, prompt: Text("app.example.com"))
                    .textFieldStyle(.roundedBorder)

                if let error = viewModel.zonesLoadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Picker("Domain", selection: $viewModel.formZone) {
                    ForEach(viewModel.zones) { zone in
                        Text(zone.name).tag(Optional(zone))
                    }
                }

                TextField("Subdomain", text: $viewModel.formSubdomain, prompt: Text("app (optional)"))
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Path", text: $viewModel.formPath, prompt: Text("/api (optional)"))
                .textFieldStyle(.roundedBorder)

            if !viewModel.formFullHostname.isEmpty {
                LabeledContent("Hostname") {
                    Text(viewModel.formFullHostname + viewModel.formNormalizedPath)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Service Section

    private var serviceSection: some View {
        Section("Service") {
            Toggle("Enter service manually", isOn: $viewModel.formUseRawService)

            if viewModel.formUseRawService {
                TextField("Service", text: $viewModel.formRawService, prompt: Text("http_status:404 or unix:/path.sock"))
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("Type", selection: $viewModel.formServiceType) {
                    ForEach([ServiceType.http, .https, .tcp, .ssh, .rdp], id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                TextField("Host", text: $viewModel.formServiceHost, prompt: Text("localhost"))
                    .textFieldStyle(.roundedBorder)

                TextField("Port", text: $viewModel.formServicePort, prompt: Text("8080"))
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Service URL") {
                Text(viewModel.formFullService)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(
                        IngressRuleValidator.isValidService(viewModel.formFullService)
                            ? Color.secondary
                            : Color.red
                    )
            }
        }
    }

    // MARK: - DNS Section

    private var dnsSection: some View {
        Section("DNS") {
            Toggle("Create DNS record", isOn: $viewModel.formCreateDNSRecord)
                .disabled(!viewModel.canCreateDNSRecord)

            if viewModel.canCreateDNSRecord && viewModel.formCreateDNSRecord {
                if let tunnelId = viewModel.tunnel?.id {
                    Text("CNAME \(viewModel.formFullHostname) → \(tunnelId).cfargotunnel.com (proxied), created when you save.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if !viewModel.canCreateDNSRecord {
                Text("DNS records can only be created for hostnames selected from your zones.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Preview

#Preview("Ingress Editor") {
    let appState = AppState()
    appState.isAuthenticated = true

    return IngressEditorView(tunnel: .preview, viewModel: IngressEditorViewModel())
        .environment(appState)
        .frame(width: 800, height: 600)
}
