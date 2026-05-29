import SwiftUI

struct RemoteModelConfigSheet: View {
    @StateObject private var model: RemoteProviderConfigModel
    @State private var isDisableConfirmationPresented = false
    @State private var removeCredentialOnDisable = false
    let onClose: () -> Void

    init(model: RemoteProviderConfigModel, onClose: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: model)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    remoteProviderBanner
                    providerSection
                    credentialSection
                    scopeSection
                    privacySection
                    footerActions
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
            }
        }
        .frame(minWidth: 680, minHeight: 620, alignment: .topLeading)
        .task { await model.load() }
        .sheet(isPresented: $isDisableConfirmationPresented) {
            DisableRemoteAIConfirmationSheet(
                removeStoredCredential: $removeCredentialOnDisable,
                onCancel: { isDisableConfirmationPresented = false },
                onDisable: {
                    isDisableConfirmationPresented = false
                    Task {
                        let didDisable = await model.disableRemoteAI(
                            removeStoredCredential: removeCredentialOnDisable
                        )
                        if didDisable { onClose() }
                    }
                }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Configure remote AI")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Cancel", action: closeWithoutSaving)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var remoteProviderBanner: some View {
        switch model.outcome {
        case let .success(message):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .padding(12)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case let .failed(error):
            AISettingsInlineBanner(error: error, tint: .red) {
                if model.unusedCredentialReference != nil {
                    if model.canRetryEnable {
                        Button("Retry save") { Task { await model.retryEnable() } }
                    }
                    Button("Remove unused key", action: model.removeUnusedCredential)
                }
            }
        case nil:
            if case let .failed(error) = model.loadState {
                AISettingsInlineBanner(error: error, tint: .red) {
                    Button("Retry") { Task { await model.load() } }
                }
            }
        }
    }

    private var providerSection: some View {
        AdvancedSettingsSection(title: "Provider") {
            Picker("Provider", selection: $model.provider) {
                ForEach(RemoteProviderKindState.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("S3-03-C3-03-provider-picker")
            TextField("Model", text: $model.modelID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("S3-03-C3-03-model")
            if model.provider == .other {
                TextField("Endpoint URL", text: $model.endpointURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("S3-03-C3-03-endpoint-url")
            }
        }
    }

    private var credentialSection: some View {
        AdvancedSettingsSection(title: "Credential") {
            SecureField("API key", text: $model.apiKey)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("S3-03-C3-03-api-key")
            Text("Stored in Keychain. Never written to logs or diagnostics.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(testButtonTitle) { Task { await model.testConnection() } }
                    .disabled(!model.canTestConnection)
                    .accessibilityIdentifier("S3-03-C3-03-test-connection")
                if let result = model.testResult {
                    Text(result.sanitizedMessage)
                        .font(.callout)
                        .foregroundStyle(result.providerVerified ? Color.green : Color.secondary)
                }
            }
        }
    }

    private var scopeSection: some View {
        AdvancedSettingsSection(title: "Usage scope") {
            ForEach(AISettingsFeatureKind.allCases) { feature in
                Toggle(feature.title, isOn: scopeBinding(feature))
                    .accessibilityIdentifier("S3-03-C3-03-scope-\(feature.rawValue)")
                Text(sentFieldsText(for: feature))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        AdvancedSettingsSection(title: "Privacy") {
            Text(
                "Remote AI may send selected file metadata or extracted text to the provider you choose. " +
                    "Privacy rules are checked before every remote call."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            Toggle(
                "I understand remote AI sends allowed content to a third-party provider.",
                isOn: $model.dataFlowConfirmed
            )
            .accessibilityIdentifier("S3-03-C3-03-data-flow-confirmed")
        }
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            if model.snapshot?.remoteProviderEnabled == true {
                Button("Disable remote AI", role: .destructive) {
                    removeCredentialOnDisable = false
                    isDisableConfirmationPresented = true
                }
                .accessibilityIdentifier("S3-03-C3-03-disable-remote-ai")
            }
            Spacer()
            Button("Cancel", action: closeWithoutSaving)
            Button("Enable remote AI") {
                Task {
                    let didEnable = await model.enableRemoteAI()
                    if didEnable { onClose() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canEnable)
            .accessibilityIdentifier("S3-03-C3-03-enable-remote-ai")
            .accessibilityHint(model.enableDisabledReason)
        }
    }

    private var testButtonTitle: String {
        model.loadState == .testing ? "Testing..." : "Test connection"
    }

    private func closeWithoutSaving() {
        if model.cancelEditing() {
            onClose()
        }
    }

    private func scopeBinding(_ feature: AISettingsFeatureKind) -> Binding<Bool> {
        Binding(
            get: { model.selectedScopes.contains(feature) },
            set: { enabled in
                if enabled { model.selectedScopes.insert(feature) } else { model.selectedScopes.remove(feature) }
            }
        )
    }

    private func sentFieldsText(for feature: AISettingsFeatureKind) -> String {
        switch feature {
        case .classificationSuggestions:
            "May send file name, repo-relative path, extension, tag and category context."
        case .autoSummaries:
            "May send extracted text snippets and existing AI summary context."
        case .autoTags:
            "May send file name, extension, extracted text snippets, tag and category context."
        case .semanticSearch:
            "May send repo-relative path, extracted text snippets and note summary, never full Note text."
        }
    }
}

private struct DisableRemoteAIConfirmationSheet: View {
    @Binding var removeStoredCredential: Bool
    let onCancel: () -> Void
    let onDisable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Disable remote AI?")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(
                "Remote AI calls will stop immediately. Local AI features and existing saved summaries, " +
                    "tags, and call logs will not be deleted."
            )
            .fixedSize(horizontal: false, vertical: true)
            Toggle("Also remove stored API key", isOn: $removeStoredCredential)
                .accessibilityIdentifier("S3-03-C3-03-disable-remove-stored-key")
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Disable remote AI", role: .destructive, action: onDisable)
                    .accessibilityIdentifier("S3-03-C3-03-confirm-disable-remote-ai")
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
