import SwiftUI

struct RemoteModelConfigSheet: View {
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
            privacyGateStatus
            privacyGateFailureBanner
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
                    guard didEnable else { return }
                    let didEnableGate = await privacyModel.enablePrivacyGate(providerConfig: model.snapshot)
                    if didEnableGate { onClose() }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canEnable || privacyModel.isSaving)
            .accessibilityIdentifier("S3-03-C3-03-enable-remote-ai")
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
        .accessibilityIdentifier("S3-03-C3-09-privacy-gate-status")
    }

    @ViewBuilder
    private var privacyGateFailureBanner: some View {
        if let failure = privacyModel.failure {
            AISettingsInlineBanner(error: failure, tint: .red) {
                if privacyModel.pendingAction != nil {
                    Button(retryPrivacyGateTitle, action: retryPrivacyGate)
                        .accessibilityIdentifier("S3-03-C3-09-retry-privacy-gate")
                }
                Button("Open privacy rules", action: onOpenPrivacyRules)
                    .accessibilityIdentifier("S3-03-C3-09-open-privacy-rules")
                if privacyModel.pendingAction == .enable {
                    Button("Disable remote AI", role: .destructive) {
                        removeCredentialOnDisable = false
                        isDisableConfirmationPresented = true
                    }
                    .accessibilityIdentifier("S3-03-C3-09-disable-after-gate-failure")
                }
            }
        }
    }

    private var testButtonTitle: String {
        model.loadState == .testing ? "Testing..." : "Test connection"
    }

    private var retryPrivacyGateTitle: String {
        switch privacyModel.pendingAction {
        case .enable: "Retry enable privacy gate"
        case .disable: "Retry disable privacy gate"
        case nil: "Retry privacy gate"
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

struct AIClassificationSuggestionPanel: View {
    @ObservedObject var model: AIClassificationSuggestionPanelModel
    var fileName: String
    var currentPath: String
    var onAccept: () -> Void = {}, onChange: () -> Void = {}, onReject: () -> Void = {}
    var onClassifyManually: () -> Void = {}, onViewCall: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI suggested a category")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            fileSummary
            Text(model.statusText)
                .foregroundStyle(statusTint)
                .accessibilityIdentifier("S3-04-C3-04-status")
            if let suggestion = model.suggestion {
                suggestionContent(suggestion)
            }
            if let failure = model.failure {
                failureContent(failure)
            }
            requestControls
        }
        .padding(16)
        .background(.background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File: \(fileName)")
            Text("Current path: \(currentPath)")
            Text("No files will be moved until you confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var requestControls: some View {
        HStack {
            Button("Ask AI for suggestion...") {
                Task { await model.askForSuggestion() }
            }
            .disabled(!model.canAskForSuggestion)
            .accessibilityIdentifier("S3-04-C3-04-ask-ai-suggestion")
            Button("Classify manually", action: onClassifyManually)
            Spacer()
        }
    }

    private var statusTint: Color {
        if model.failure != nil { return .red }
        if model.state.isLoading { return .secondary }
        return .primary
    }

    @ViewBuilder
    private func suggestionContent(_ suggestion: AIClassificationSuggestionState) -> some View {
        switch suggestion.status {
        case .suggested:
            suggestedCard(suggestion)
        case .noSuggestion, .skipped, .unavailable:
            skippedOrUnavailableCard(suggestion)
        }
    }

    private func suggestedCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Suggested category: \(suggestion.suggestedCategory ?? "Unknown")")
                    .font(.subheadline.weight(.semibold))
                AISuggestionConfidenceBadge(confidence: suggestion.confidence)
                if let route = suggestion.route {
                    Text(route.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Current category: \(suggestion.currentCategory ?? "None")")
            Text("Reason: \(suggestion.reason ?? "No reason provided.")")
            Text("Used: \(usedContextText(for: suggestion))")
                .foregroundStyle(.secondary)
            Text("Target category: \(suggestion.suggestedCategory ?? "Unknown")")
            HStack {
                Button("Accept", action: onAccept)
                    .disabled(model.acceptDisabledReason != nil || model.state.isLoading)
                Button("Change...", action: onChange)
                    .disabled(model.state.isLoading)
                Button("Reject", action: onReject)
                    .disabled(model.state.isLoading)
            }
            if let acceptDisabledReason = model.acceptDisabledReason {
                Text(acceptDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if suggestion.callLogID != nil {
                Button("View AI call", action: onViewCall)
                    .buttonStyle(.link)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S3-04-C3-04-suggestion-card")
    }

    private func skippedOrUnavailableCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = suggestion.skippedReason {
                Text("Reason: \(skipReasonText(reason))")
            }
            if let ruleID = suggestion.privacyRuleID {
                Text("Privacy rule: \(ruleID)")
                    .foregroundStyle(.secondary)
            }
            if suggestion.callLogID != nil {
                Button("View AI call", action: onViewCall)
                    .buttonStyle(.link)
            }
        }
        .accessibilityIdentifier("S3-04-C3-04-skipped-card")
    }

    private func failureContent(_ failure: AISettingsError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.message)
            Text(failure.detail)
                .foregroundStyle(.secondary)
            Text(failure.recovery)
                .font(.caption)
        }
        .accessibilityIdentifier("S3-04-C3-04-error")
    }

    private func usedContextText(for suggestion: AIClassificationSuggestionState) -> String {
        suggestion.usedContext.isEmpty ? "none" : suggestion.usedContext.map(\.label).joined(separator: ", ")
    }

    private func skipReasonText(_ reason: AIClassificationSuggestionSkipReasonState) -> String {
        switch reason {
        case .aiDisabled: "AI classification suggestions are off"
        case .featureDisabled: "AI classification feature is off"
        case .ruleResultConfident: "rule classification is already confident"
        case .noEligibleContext: "no eligible context"
        case .privacyRule: "skipped by privacy rule"
        case .providerUnavailable: "provider unavailable"
        }
    }
}

struct AISuggestionConfidenceBadge: View {
    var confidence: Float

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(lowConfidence ? Color.orange.opacity(0.14) : Color.green.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(label)
    }

    private var label: String { lowConfidence ? "Low confidence \(percent)%" : "Confidence \(percent)%" }
    private var percent: Int { Int((min(max(confidence, 0), 1) * 100).rounded()) }
    private var lowConfidence: Bool { confidence < 0.6 }
}
