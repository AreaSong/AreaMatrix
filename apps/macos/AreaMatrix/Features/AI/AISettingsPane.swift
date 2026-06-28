import SwiftUI

@MainActor
struct AISettingsPane: View {
    @StateObject fileprivate var model: AISettingsModel
    @State fileprivate var isLocalModelStatusPresented = false
    @State fileprivate var isRemoteConfigPresented = false
    @State fileprivate var isCallLogPresented = false
    @State fileprivate var returnsToPrivacyRulesAfterRemoteConfig = false
    @State fileprivate var privacyRulesRoute: AIPrivacyRulesRoute?

    init(repoPath: String) {
        _model = StateObject(wrappedValue: AISettingsModel(repoPath: repoPath))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { bodyContent }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 34)
                    .padding(.vertical, 28)
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $isLocalModelStatusPresented) {
            LocalModelStatusView(model: LocalModelStatusModel(repoPath: model.repoPath)) {
                isLocalModelStatusPresented = false
            }
        }
        .sheet(isPresented: $isRemoteConfigPresented) {
            RemoteModelConfigSheet(
                model: RemoteProviderConfigModel(repoPath: model.repoPath),
                onOpenPrivacyRules: openPrivacyRules
            ) {
                isRemoteConfigPresented = false
                Task {
                    await model.load()
                    if returnsToPrivacyRulesAfterRemoteConfig { openPrivacyRules() }
                }
            }
        }
        .sheet(item: $privacyRulesRoute) { route in
            AIPrivacyRulesRouteView(
                route: route,
                model: model,
                onConfigureRemoteAI: configureRemoteAIFromPrivacyRules,
                onClose: closePrivacyRules
            )
        }
        .sheet(isPresented: $isCallLogPresented) {
            AICallLogView(repoPath: model.repoPath) { isCallLogPresented = false }
        }
    }

    private var header: some View {
        SettingsPageHeader(title: "AI", subtitle: model.repoPath) {
            if model.isSaving {
                SettingsHeaderProgressIndicator(label: "Saving AI settings")
            }
        }
    }
}

private extension AISettingsPane {
    @ViewBuilder
    var bodyContent: some View {
        switch model.loadState {
        case .loading:
            AISettingsLoadingView()
        case let .failed(error):
            AISettingsLoadFailureView(error: error, retry: retryLoad, openLog: model.openCallLogEntry)
        case .loaded:
            loadedContent
        }
    }

    var loadedContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            feedbackBanner
            statusSection
            providerSection
            featureSection
            privacySection
            logSection
            safetySection
        }
    }

    @ViewBuilder
    var feedbackBanner: some View {
        if let error = model.saveError {
            AISettingsInlineBanner(error: error, tint: .red) {
                if model.hasRetryablePause {
                    Button("Retry pause", action: retryPause)
                }
                if model.hasRetryableSave {
                    Button("Retry save", action: retrySave)
                    Button("Revert changes", action: model.revertChanges)
                }
            }
        } else if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case let .failed(error):
                AISettingsInlineBanner(error: error, tint: .orange) {
                    Button("Configure remote AI", action: openRemoteConfig)
                }
            }
        }
    }
}

private extension AISettingsPane {
    var statusSection: some View {
        AdvancedSettingsSection(title: "AI features") {
            Toggle("Enable AI features", isOn: aiEnabledBinding)
                .disabled(writesDisabled)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var providerSection: some View {
        AdvancedSettingsSection(title: "Providers") {
            AdvancedSettingsKeyValueRow(label: "Local model", value: localModelLabel)
            AdvancedSettingsKeyValueRow(label: "Remote model", value: remoteModelLabel)
            Picker("Provider preference", selection: providerPreferenceBinding) {
                ForEach(AISettingsProviderPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .disabled(writesDisabled)
            .frame(maxWidth: 360)
            HStack {
                Button("Local model status", action: openLocalModelStatus)
                    .accessibilityIdentifier("local-model-status-local-model-status-core-open-local-model-status")
                Button("Configure remote AI", action: openRemoteConfig)
                    .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-configure-remote-ai")
            }
        }
    }

    var featureSection: some View {
        AdvancedSettingsSection(title: "Feature toggles") {
            ForEach(featureRows) { row in
                AISettingsFeatureRow(row: row, isOn: featureBinding(row.feature))
                    .disabled(writesDisabled || !isFeatureEditable(row))
            }
        }
    }

    var privacySection: some View {
        AdvancedSettingsSection(title: "Privacy") {
            AdvancedSettingsKeyValueRow(label: "Privacy rules", value: privacyRulesLabel)
            AdvancedSettingsKeyValueRow(label: "Remote AI", value: remoteScopeLabel)
            Button("Manage privacy rules", action: openPrivacyRules)
                .accessibilityIdentifier("ai-privacy-rules-ai-settings-config-manage-privacy-rules")
        }
    }

    var logSection: some View {
        AdvancedSettingsSection(title: "Log") {
            Button("View AI call log") { model.openCallLogEntry(); isCallLogPresented = true }
                .accessibilityIdentifier("ai-call-log-ai-call-log-core-open-ai-call-log")
            Text("See when AI was used and whether it was local or remote.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    var safetySection: some View {
        AdvancedSettingsSection(title: "Safety") {
            Button("Pause all AI", action: pauseAllAI)
                .disabled(writesDisabled || !(model.snapshot?.config.aiEnabled ?? false))
            Button("Clear AI generated suggestions...", action: model.openCallLogEntry)
                .disabled(true)
            Text("Clear generated suggestions from the AI call log after reviewing recent activity.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private extension AISettingsPane {
    var writesDisabled: Bool {
        model.isSaving || !model.isLoaded
    }

    var statusText: String {
        guard let config = model.snapshot?.config else {
            return "Loading AI settings..."
        }
        if !config.aiEnabled {
            return "AI is off. AreaMatrix will not call local or remote models."
        }
        if config.remoteAIAllowed {
            return "Remote AI is enabled for selected features."
        }
        return "Local AI is enabled. Files stay on this device."
    }

    var localModelLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        return config.localAIEnabled ? "Ready" : "Not installed"
    }

    var remoteModelLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        return config.remoteAIAllowed ? "Configured" : "Off"
    }

    var privacyRulesLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        guard config.privacyGateEnabled else { return "Off" }
        return config.privacyPolicyRef ?? "Default gate enabled"
    }

    var remoteScopeLabel: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        return config.remoteAIAllowed ? "Allowed for selected features" : "Remote AI is not configured"
    }

    var featureRows: [AISettingsFeatureRowSnapshot] {
        guard let snapshot = model.snapshot else { return [] }
        let toggles = Dictionary(uniqueKeysWithValues: snapshot.config.featureToggles.map { ($0.feature, $0) })
        return snapshot.capabilities.map { capability in
            AISettingsFeatureRowSnapshot(
                feature: capability.feature,
                enabled: toggles[capability.feature]?.enabled ?? capability.enabled,
                providerLabel: capability.feature.providerLabel,
                remoteScope: remoteScopeText(capability),
                disabledReason: capability.disabledReason
            )
        }
    }
}

private extension AISettingsPane {
    var aiEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.snapshot?.config.aiEnabled ?? false },
            set: { enabled in Task { await model.setAIEnabled(enabled) } }
        )
    }

    var providerPreferenceBinding: Binding<AISettingsProviderPreference> {
        Binding(
            get: { model.snapshot?.config.providerPreference ?? .localFirst },
            set: { preference in Task { await model.setProviderPreference(preference) } }
        )
    }

    func featureBinding(_ feature: AISettingsFeatureKind) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot?.config.featureToggles.first { $0.feature == feature }?.enabled ?? false
            },
            set: { enabled in Task { await model.setFeature(feature, enabled: enabled) } }
        )
    }

    func isFeatureEditable(_ row: AISettingsFeatureRowSnapshot) -> Bool {
        model.snapshot?.config.aiEnabled == true && row.disabledReason != "AI is off"
    }

    func remoteScopeText(_ capability: AISettingsCapabilitySnapshot) -> String {
        if capability.remoteAllowed { return "Remote scope allowed" }
        return "Remote scope blocked"
    }
}

private extension AISettingsPane {
    func retryLoad() {
        Task { await model.load() }
    }

    func retrySave() {
        Task { await model.retrySave() }
    }

    func retryPause() {
        Task { await model.retryPause() }
    }

    func pauseAllAI() {
        Task { await model.pauseAllAI() }
    }

    func openLocalModelStatus() {
        model.openLocalModelStatusEntry()
        isLocalModelStatusPresented = true
    }

    func openRemoteConfig() {
        model.openRemoteConfigurationEntry()
        isRemoteConfigPresented = true
    }

    func openPrivacyRules() {
        model.openPrivacyRulesEntry()
        isRemoteConfigPresented = false
        privacyRulesRoute = AIPrivacyRulesRoute(repoPath: model.repoPath)
    }

    func closePrivacyRules() {
        privacyRulesRoute = nil
        Task { await model.load() }
    }

    func configureRemoteAIFromPrivacyRules() {
        returnsToPrivacyRulesAfterRemoteConfig = true
        privacyRulesRoute = nil
        openRemoteConfig()
    }
}

private struct AISettingsLoadingView: View {
    var body: some View {
        AdvancedSettingsSection(title: "AI features") {
            ProgressView("Loading AI settings...")
            Text("AI controls are disabled until settings finish loading.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AISettingsLoadFailureView: View {
    let error: AISettingsError
    let retry: () -> Void
    let openLog: () -> Void

    var body: some View {
        AISettingsInlineBanner(error: error, tint: .red) {
            Button("Retry", action: retry)
            Button("View AI call log", action: openLog)
        }
    }
}

private struct AISettingsFeatureRow: View {
    let row: AISettingsFeatureRowSnapshot
    var isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle(row.feature.title, isOn: isOn)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                Text(row.feature.title)
                    .font(.callout.weight(.medium))
                Text("\(row.providerLabel) - \(row.remoteScope)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let reason = row.disabledReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            row.feature.title,
            row.enabled ? "on" : "off",
            row.providerLabel,
            row.remoteScope,
            row.disabledReason ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
