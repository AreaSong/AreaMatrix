import SwiftUI

struct RemoteModelConfigSheet: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: RemoteProviderConfigModel
    @StateObject private var privacyModel: RemotePrivacyGateModel
    @State private var isDisableConfirmationPresented = false
    @State private var removeCredentialOnDisable = false
    let onOpenPrivacyRules: () -> Void
    let onClose: () -> Void

    init(
        model: RemoteProviderConfigModel,
        privacyModel: RemotePrivacyGateModel? = nil,
        onOpenPrivacyRules: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        _privacyModel = StateObject(wrappedValue: privacyModel ?? RemotePrivacyGateModel(repoPath: model.repoPath))
        self.onOpenPrivacyRules = onOpenPrivacyRules
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
        .task {
            await model.load()
            await privacyModel.load()
        }
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
                        if model.snapshot?.remoteProviderEnabled == false {
                            _ = await privacyModel.disablePrivacyGate(providerConfig: model.snapshot)
                        }
                        if didDisable, privacyModel.pendingAction == nil {
                            onClose()
                        }
                    }
                }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Configure remote AI"))
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
            Button(L10n.string("Cancel"), action: closeWithoutSaving)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder
    private var remoteProviderBanner: some View {
        switch model.outcome {
        case let .success(message):
            TintedStatusBanner(tint: .green, fillsWidth: false) {
                Label(localizer.resolve(message), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        case let .failed(error):
            AISettingsInlineBanner(error: error, tint: .red) {
                if model.unusedCredentialReference != nil {
                    if model.canRetryEnable {
                        Button(L10n.string("Retry save")) { Task { await model.retryEnable() } }
                    }
                    Button(L10n.string("Remove unused key"), action: model.removeUnusedCredential)
                }
            }
        case nil:
            if case let .failed(error) = model.loadState {
                AISettingsInlineBanner(error: error, tint: .red) {
                    Button(L10n.string("Retry")) { Task { await model.load() } }
                }
            }
        }
    }

    private var providerSection: some View {
        AdvancedSettingsSection(title: L10n.string("Provider")) {
            Picker(L10n.string("Provider"), selection: $model.provider) {
                ForEach(RemoteProviderKindState.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-provider-picker")
            TextField(L10n.string("Model"), text: $model.modelID)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-model")
            if model.provider == .other {
                TextField(L10n.string("Endpoint URL"), text: $model.endpointURL)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-endpoint-url")
            }
        }
    }

    private var credentialSection: some View {
        AdvancedSettingsSection(title: L10n.string("Credential")) {
            SecureField(L10n.string("API key"), text: $model.apiKey)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-api-key")
            Text(L10n.string("Stored in Keychain. Never written to logs or diagnostics."))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(testButtonTitle) { Task { await model.testConnection() } }
                    .disabled(!model.canTestConnection)
                    .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-test-connection")
                if let result = model.testResult {
                    Text(result.sanitizedMessage)
                        .font(.callout)
                        .foregroundStyle(result.providerVerified ? Color.green : Color.secondary)
                }
            }
        }
    }

    private var scopeSection: some View {
        AdvancedSettingsSection(title: L10n.string("Usage scope")) {
            ForEach(AISettingsFeatureKind.allCases) { feature in
                Toggle(feature.title, isOn: scopeBinding(feature))
                    .accessibilityIdentifier(
                        "remote-provider-config-remote-provider-config-core-scope-\(feature.rawValue)"
                    )
                Text(sentFieldsText(for: feature))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        AdvancedSettingsSection(title: L10n.string("Privacy")) {
            privacyGateStatus
            privacyGateFailureBanner
            Text(L10n.string("ai.remote.dataFlowDetail"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle(
                L10n.string("I understand remote AI sends allowed content to a third-party provider."),
                isOn: $model.dataFlowConfirmed
            )
            .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-data-flow-confirmed")
        }
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            if model.snapshot?.remoteProviderEnabled == true {
                Button(L10n.string("Disable remote AI"), role: .destructive) {
                    removeCredentialOnDisable = false
                    isDisableConfirmationPresented = true
                }
                .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-disable-remote-ai")
            }
            Spacer()
            Button(L10n.string("Cancel"), action: closeWithoutSaving)
            Button(L10n.string("Enable remote AI")) {
                Task {
                    let didEnable = await model.enableRemoteAI()
                    guard didEnable else { return }
                    let didEnableGate = await privacyModel.enablePrivacyGate(providerConfig: model.snapshot)
                    if didEnableGate { onClose() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canEnable || privacyModel.isSaving)
            .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-enable-remote-ai")
            .accessibilityHint(model.enableDisabledReason)
        }
    }

    private var privacyGateStatus: some View {
        HStack(spacing: 8) {
            Label(privacyModel.statusText, systemImage: privacyGateIconName)
                .foregroundStyle(privacyGateTint)
            if privacyModel.isSaving {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .font(.callout)
        .accessibilityIdentifier("remote-provider-config-ai-privacy-rules-core-privacy-gate-status")
    }

    @ViewBuilder
    private var privacyGateFailureBanner: some View {
        if let failure = privacyModel.failure {
            AISettingsInlineBanner(error: failure, tint: .red) {
                if privacyModel.pendingAction != nil {
                    Button(retryPrivacyGateTitle, action: retryPrivacyGate)
                        .accessibilityIdentifier("remote-provider-config-ai-privacy-rules-core-retry-privacy-gate")
                }
                Button(L10n.string("Open privacy rules"), action: onOpenPrivacyRules)
                    .accessibilityIdentifier("remote-provider-config-ai-privacy-rules-core-open-privacy-rules")
                if privacyModel.pendingAction == .enable {
                    Button(L10n.string("Disable remote AI"), role: .destructive) {
                        removeCredentialOnDisable = false
                        isDisableConfirmationPresented = true
                    }
                    .accessibilityIdentifier("remote-provider-config-ai-privacy-rules-core-disable-after-gate-failure")
                }
            }
        }
    }

    private var testButtonTitle: String {
        model.loadState == .testing ? L10n.string("Testing...") : L10n.string("Test connection")
    }

    private var retryPrivacyGateTitle: String {
        switch privacyModel.pendingAction {
        case .enable: L10n.string("Retry enable privacy gate")
        case .disable: L10n.string("Retry disable privacy gate")
        case nil: L10n.string("Retry privacy gate")
        }
    }

    private var privacyGateIconName: String {
        privacyModel.snapshot?.privacyGateEnabled == true ? "lock.shield" : "lock.slash"
    }

    private var privacyGateTint: Color {
        if privacyModel.failure != nil { return .red }
        return privacyModel.snapshot?.privacyGateEnabled == true ? .green : .secondary
    }

    private func closeWithoutSaving() {
        if model.cancelEditing() {
            onClose()
        }
    }

    private func retryPrivacyGate() {
        Task {
            let succeeded = await privacyModel.retryPending(providerConfig: model.snapshot)
            if succeeded { onClose() }
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
            L10n.string("May send file name, repo-relative path, extension, tag and category context.")
        case .autoSummaries:
            L10n.string("May send extracted text snippets and existing AI summary context.")
        case .autoTags:
            L10n.string("May send file name, extension, extracted text snippets, tag and category context.")
        case .semanticSearch:
            L10n.string(
                "May send repo-relative path, extracted text snippets and note summary, never full Note text."
            )
        }
    }
}

private struct DisableRemoteAIConfirmationSheet: View {
    @Binding var removeStoredCredential: Bool
    let onCancel: () -> Void
    let onDisable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("Disable remote AI?"))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(L10n.string("ai.remote.disableDetail"))
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L10n.string("Also remove stored API key"), isOn: $removeStoredCredential)
                .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-disable-remove-stored-key")
            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Disable remote AI"), role: .destructive, action: onDisable)
                    .accessibilityIdentifier(
                        "remote-provider-config-remote-provider-config-core-confirm-disable-remote-ai"
                    )
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
