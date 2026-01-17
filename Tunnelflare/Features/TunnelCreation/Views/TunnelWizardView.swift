//
//  TunnelWizardView.swift
//  Tunnelflare
//
//  Created on 2026-01-11.
//  Copyright 2026. All rights reserved.
//

import SwiftUI

/// The main container view for the tunnel creation wizard.
///
/// This view manages:
/// - Step-based navigation between wizard steps
/// - Progress indicator showing current step
/// - Sheet presentation
/// - Dismiss on complete or cancel
struct TunnelWizardView: View {
    /// The tunnel creation view model.
    @Bindable var viewModel: TunnelCreationViewModel

    /// Callback when tunnel creation is complete.
    var onComplete: (Tunnel?) -> Void

    /// Callback when wizard is cancelled.
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Fixed Header
            wizardHeader

            Divider()

            // Scrollable Content
            ScrollView {
                stepContent
                    .padding(24)
            }

            Divider()

            // Fixed Footer with navigation buttons
            wizardFooter
        }
        .frame(width: 580)
        .frame(minHeight: 500, maxHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Creation Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.dismissError()
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .onChange(of: viewModel.creationSucceeded) { _, succeeded in
            if succeeded {
                onComplete(viewModel.createdTunnel)
            }
        }
    }

    // MARK: - Header

    /// The wizard header with title and progress indicator.
    private var wizardHeader: some View {
        VStack(spacing: 12) {
            // Title row
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("Create New Tunnel")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Text("Step \(viewModel.currentStep.rawValue) of \(TunnelWizardStep.totalSteps)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            progressBar
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// The progress bar showing wizard progress.
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(TunnelWizardStep.allCases, id: \.rawValue) { step in
                stepIndicator(for: step)
            }
        }
    }

    /// A single step indicator in the progress bar.
    private func stepIndicator(for step: TunnelWizardStep) -> some View {
        HStack(spacing: 6) {
            // Step circle
            ZStack {
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 26, height: 26)

                if step.rawValue < viewModel.currentStep.rawValue {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(step == viewModel.currentStep ? .white : .secondary)
                }
            }

            // Step title - use fixedSize to prevent truncation
            Text(step.title)
                .font(.caption)
                .foregroundStyle(step == viewModel.currentStep ? .primary : .secondary)
                .fixedSize(horizontal: true, vertical: false)

            // Connector line (except for last step)
            if step != TunnelWizardStep.allCases.last {
                Rectangle()
                    .fill(step.rawValue < viewModel.currentStep.rawValue ? Color.green : Color.secondary.opacity(0.3))
                    .frame(height: 2)
                    .frame(minWidth: 20, maxWidth: 40)
            }
        }
    }

    /// The color for a step indicator.
    private func stepColor(for step: TunnelWizardStep) -> Color {
        if step.rawValue < viewModel.currentStep.rawValue {
            return .green
        } else if step == viewModel.currentStep {
            return .orange
        } else {
            return .secondary.opacity(0.3)
        }
    }

    // MARK: - Step Content

    /// The content view for the current step (without navigation buttons).
    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .name:
            TunnelNameStepContent(viewModel: viewModel)

        case .hostname:
            TunnelHostnameStepContent(viewModel: viewModel)

        case .service:
            TunnelServiceStepContent(viewModel: viewModel)
        }
    }

    // MARK: - Footer

    /// The wizard footer with navigation buttons.
    private var wizardFooter: some View {
        HStack {
            // Back/Cancel button
            Button(viewModel.isFirstStep ? "Cancel" : "Back") {
                if viewModel.isFirstStep {
                    viewModel.reset()
                    onCancel()
                } else {
                    viewModel.previousStep()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(viewModel.isCreating)

            Spacer()

            // Next/Create button
            if viewModel.isLastStep {
                Button {
                    Task {
                        await viewModel.createTunnel()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isCreating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isCreating ? "Creating..." : "Create Tunnel")
                    }
                    .frame(minWidth: 100)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceed || viewModel.isCreating)
            } else {
                Button("Next") {
                    viewModel.nextStep()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canProceed)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Step Content Views (without navigation buttons)

/// Content for the tunnel name step.
struct TunnelNameStepContent: View {
    @Bindable var viewModel: TunnelCreationViewModel
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose a Tunnel Name")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Give your tunnel a unique name to identify it. This name will be used internally and can be changed later.")
                .font(.body)
                .foregroundStyle(.secondary)

            // Name input
            VStack(alignment: .leading, spacing: 8) {
                Text("Tunnel Name")
                    .font(.headline)

                TextField("my-tunnel", text: $viewModel.tunnelName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .autocorrectionDisabled()

                if let error = viewModel.nameError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if viewModel.isNameValid && !viewModel.tunnelName.isEmpty {
                    Label("Name is valid", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // Naming rules
            VStack(alignment: .leading, spacing: 8) {
                Text("Naming Rules")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    ruleRow("3-63 characters long")
                    ruleRow("Lowercase letters (a-z), numbers (0-9), and hyphens (-)")
                    ruleRow("Must start and end with a letter or number")
                    ruleRow("No consecutive hyphens (--)")
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            isNameFieldFocused = true
        }
    }

    private func ruleRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Content for the hostname step.
struct TunnelHostnameStepContent: View {
    @Bindable var viewModel: TunnelCreationViewModel
    @FocusState private var isSubdomainFocused: Bool
    @State private var subdomainCheckTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure Public Hostname")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Set up the public URL where your tunnel will be accessible. You can skip this step and configure it later.")
                .font(.body)
                .foregroundStyle(.secondary)

            // Domain section
            domainSection

            // Subdomain section
            subdomainSection

            // Hostname preview
            if !viewModel.fullHostname.isEmpty {
                hostnamePreview
            }

            // Warning for existing subdomain
            if let warning = viewModel.subdomainWarning {
                warningBanner(warning)
            }

            // Skip note
            skipNote
        }
        .task {
            await viewModel.loadZones()
        }
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Domain")
                    .font(.headline)
                if viewModel.isLoadingZones {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if viewModel.isLoadingZones {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading your domains...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if viewModel.zones.isEmpty || viewModel.useManualDomain {
                TextField("example.com", text: $viewModel.domain)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                if viewModel.zonesLoadError != nil {
                    Label("Could not load domains. Enter manually.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !viewModel.zones.isEmpty {
                    Button("Select from my domains") {
                        viewModel.useManualDomain = false
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            } else {
                Picker("Domain", selection: $viewModel.selectedZone) {
                    Text("Select a domain...").tag(nil as Zone?)
                    ForEach(viewModel.zones) { zone in
                        Text(zone.name).tag(zone as Zone?)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text("\(viewModel.zones.count) domain(s) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Enter manually") {
                        viewModel.useManualDomain = true
                        viewModel.selectedZone = nil
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var subdomainSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subdomain")
                    .font(.headline)
                if viewModel.isCheckingSubdomain {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                TextField("app", text: $viewModel.subdomain)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSubdomainFocused)
                    .autocorrectionDisabled()
                    .onChange(of: viewModel.subdomain) { _, _ in
                        subdomainCheckTask?.cancel()
                        subdomainCheckTask = Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled else { return }
                            await viewModel.checkSubdomain()
                        }
                    }

                if !viewModel.domain.isEmpty {
                    Text(".\(viewModel.domain)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Text("The subdomain for your tunnel (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var hostnamePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Public URL preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Your public URL")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.blue)
                    Text("https://\(viewModel.fullHostname)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("https://\(viewModel.fullHostname)", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // DNS record notice
            dnsRecordNotice
        }
    }

    private var dnsRecordNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("DNS record will be created automatically")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("A CNAME record pointing to your tunnel will be added to \(viewModel.domain)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func warningBanner(_ message: String) -> some View {
        let isExistingTunnel = viewModel.existingRecord?.isCNAME == true &&
                               (viewModel.existingRecord?.content.contains("cfargotunnel.com") ?? false)

        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: isExistingTunnel ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                .foregroundStyle(isExistingTunnel ? .blue : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(isExistingTunnel ? "Subdomain is used by another tunnel" : "Subdomain already has a DNS record")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isExistingTunnel {
                    Text("This DNS record will be updated to point to your new tunnel.")
                        .font(.caption)
                        .foregroundStyle(.blue)
                } else {
                    Text("Warning: The existing DNS record will be replaced with a CNAME pointing to your tunnel.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fontWeight(.medium)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(isExistingTunnel ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var skipNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
            Text("Optional - You can configure the hostname later through the Cloudflare dashboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Content for the service step.
struct TunnelServiceStepContent: View {
    @Bindable var viewModel: TunnelCreationViewModel
    @FocusState private var isURLFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Configure Local Service")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Specify the local service that your tunnel will route traffic to.")
                .font(.body)
                .foregroundStyle(.secondary)

            // Service type
            VStack(alignment: .leading, spacing: 8) {
                Text("Service Type")
                    .font(.headline)

                Picker("Type", selection: $viewModel.serviceType) {
                    ForEach([ServiceType.http, .https, .tcp, .ssh, .rdp], id: \.self) { type in
                        Text(type.rawValue.uppercased()).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Service URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Service URL")
                    .font(.headline)

                HStack {
                    Text("\(viewModel.serviceType.scheme)://")
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))

                    TextField("localhost:3000", text: $viewModel.serviceURL)
                        .textFieldStyle(.roundedBorder)
                        .focused($isURLFieldFocused)
                        .autocorrectionDisabled()
                }

                Text("The address of your local service (e.g., localhost:3000)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Common presets
            VStack(alignment: .leading, spacing: 8) {
                Text("Common Presets")
                    .font(.subheadline)
                    .fontWeight(.medium)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ServicePreset.presets.prefix(6)) { preset in
                        Button {
                            viewModel.applyPreset(preset)
                        } label: {
                            HStack {
                                Image(systemName: preset.type.systemImage)
                                    .foregroundStyle(.secondary)
                                Text(preset.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Configuration preview
            VStack(alignment: .leading, spacing: 8) {
                Text("Configuration Preview")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 10) {
                    previewRow(label: "Tunnel Name", value: viewModel.tunnelName)
                    if !viewModel.fullHostname.isEmpty {
                        previewRow(label: "Public URL", value: "https://\(viewModel.fullHostname)")
                    } else {
                        previewRow(label: "Public URL", value: "(Configure later)")
                    }
                    previewRow(label: "Local Service", value: viewModel.fullServiceURL)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear {
            isURLFieldFocused = true
        }
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview("Wizard - Name Step") {
    TunnelWizardView(
        viewModel: TunnelCreationViewModel(),
        onComplete: { _ in },
        onCancel: {}
    )
}

#Preview("Wizard - Service Step") {
    let viewModel = TunnelCreationViewModel()
    viewModel.tunnelName = "my-tunnel"
    viewModel.subdomain = "app"
    viewModel.domain = "example.com"
    viewModel.currentStep = .service
    return TunnelWizardView(
        viewModel: viewModel,
        onComplete: { _ in },
        onCancel: {}
    )
}
