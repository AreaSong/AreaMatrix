import SwiftUI

@MainActor
struct AISettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject fileprivate var model: AISettingsModel
    private let dependencies: AISettingsPaneDependencies
    @State fileprivate var isLocalModelStatusPresented = false
    @State fileprivate var isRemoteConfigPresented = false
    @State fileprivate var isCallLogPresented = false
    @State fileprivate var returnsToPrivacyRulesAfterRemoteConfig = false
    @State fileprivate var privacyRulesRoute: AIPrivacyRulesRoute?

    init(
        repoPath: String,
        featureDependencies: AIFeatureDependencies,
        sharedDependencies: SharedFeatureDependencies
    ) {
        let model = AISettingsModel(
            repoPath: repoPath,
            loader: featureDependencies.aiSettingsLoader,
            updater: featureDependencies.aiSettingsUpdater,
            errorMapper: sharedDependencies.errorMapper
        )
        _model = StateObject(wrappedValue: model)
        dependencies = AISettingsPaneDependencies(
            makeLocalModelStatus: { path in
                LocalModelStatusModel(
                    repoPath: path,
                    statusReader: featureDependencies.localModelStatusReader,
                    errorMapper: sharedDependencies.errorMapper
                )
            },
            makeRemoteProviderConfig: { path in
                RemoteProviderConfigModel(
                    repoPath: path,
                    bridge: featureDependencies.remoteProviderConfigurer,
                    errorMapper: sharedDependencies.errorMapper
                )
            },
            makeRemotePrivacyGate: { path in
                RemotePrivacyGateModel(
                    repoPath: path,
                    bridge: featureDependencies.aiPrivacyRulesManager,
                    errorMapper: sharedDependencies.errorMapper
                )
            },
            makePrivacyProviderState: { path in
                AIPrivacyRemoteProviderStateModel(
                    repoPath: path,
                    providerReader: featureDependencies.remoteProviderConfigurer,
                    errorMapper: sharedDependencies.errorMapper
                )
            },
            makePrivacyRules: { path, settingsModel in
                AIPrivacyRulesModel(
                    repoPath: path,
                    rulesManager: featureDependencies.aiPrivacyRulesManager,
                    evaluator: featureDependencies.aiPrivacyRules,
                    errorMapper: sharedDependencies.errorMapper,
                    settingsSync: settingsModel
                )
            },
            privacyRegistryReader: featureDependencies.privacyRuleRegistryReader,
            callLogLister: featureDependencies.aiCallLogLister,
            callLogClearer: featureDependencies.aiCallLogClearer,
            errorMapper: sharedDependencies.errorMapper
        )
    }

    init(model: AISettingsModel, dependencies: AISettingsPaneDependencies) {
        _model = StateObject(wrappedValue: model)
        self.dependencies = dependencies
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
            LocalModelStatusView(model: dependencies.makeLocalModelStatus(model.repoPath)) {
                isLocalModelStatusPresented = false
            }
        }
        .sheet(isPresented: $isRemoteConfigPresented) {
            RemoteModelConfigSheet(
                model: dependencies.makeRemoteProviderConfig(model.repoPath),
                privacyModel: dependencies.makeRemotePrivacyGate(model.repoPath),
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
                registryReader: dependencies.privacyRegistryReader,
                providerModel: dependencies.makePrivacyProviderState(model.repoPath),
                privacyModel: dependencies.makePrivacyRules(model.repoPath, model),
                onConfigureRemoteAI: configureRemoteAIFromPrivacyRules,
                onClose: closePrivacyRules
            )
        }
        .sheet(isPresented: $isCallLogPresented) {
            AICallLogView(
                repoPath: model.repoPath,
                lister: dependencies.callLogLister,
                clearer: dependencies.callLogClearer,
                errorMapper: dependencies.errorMapper
            ) {
                isCallLogPresented = false
            }
        }
    }

    private var header: some View {
        SettingsPageHeader(title: L10n.string("settings.page.ai"), subtitle: model.repoPath) {
            if model.isSaving {
                SettingsHeaderProgressIndicator(label: L10n.string("Saving AI settings"))
            }
        }
    }
}

@MainActor
struct AISettingsPaneDependencies {
    var makeLocalModelStatus: (String) -> LocalModelStatusModel
    var makeRemoteProviderConfig: (String) -> RemoteProviderConfigModel
    var makeRemotePrivacyGate: (String) -> RemotePrivacyGateModel
    var makePrivacyProviderState: (String) -> AIPrivacyRemoteProviderStateModel
    var makePrivacyRules: (String, AISettingsModel) -> AIPrivacyRulesModel
    var privacyRegistryReader: any AIPrivacyRuleRegistryReading
    var callLogLister: any CoreAICallLogListing
    var callLogClearer: any CoreAICallLogClearing
    var errorMapper: any CoreErrorMapping
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
                    Button(L10n.string("Retry pause"), action: retryPause)
                }
                if model.hasRetryableSave {
                    Button(L10n.string("Retry save"), action: retrySave)
                    Button(L10n.string("Revert changes"), action: model.revertChanges)
                }
            }
        } else if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                Text(localizer.resolve(message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case let .failed(error):
                AISettingsInlineBanner(error: error, tint: .orange) {
                    Button(L10n.string("Configure remote AI"), action: openRemoteConfig)
                }
            }
        }
    }
}

private extension AISettingsPane {
    var statusSection: some View {
        AdvancedSettingsSection(title: L10n.string("AI features")) {
            Toggle(L10n.string("Enable AI features"), isOn: aiEnabledBinding)
                .disabled(writesDisabled)
            Text(statusText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var providerSection: some View {
        AdvancedSettingsSection(title: L10n.string("Providers")) {
            AdvancedSettingsKeyValueRow(label: L10n.string("Local model"), value: localModelLabel)
            AdvancedSettingsKeyValueRow(label: L10n.string("Remote model"), value: remoteModelLabel)
            Picker(L10n.string("Provider preference"), selection: providerPreferenceBinding) {
                ForEach(AISettingsProviderPreference.allCases) { preference in
                    Text(preference.label).tag(preference)
                }
            }
            .pickerStyle(.segmented)
            .disabled(writesDisabled)
            .frame(maxWidth: 360)
            HStack {
                Button(L10n.string("Local model status"), action: openLocalModelStatus)
                    .accessibilityIdentifier("local-model-status-local-model-status-core-open-local-model-status")
                Button(L10n.string("Configure remote AI"), action: openRemoteConfig)
                    .accessibilityIdentifier("remote-provider-config-remote-provider-config-core-configure-remote-ai")
            }
        }
    }

    var featureSection: some View {
        AdvancedSettingsSection(title: L10n.string("Feature toggles")) {
            ForEach(featureRows) { row in
                AISettingsFeatureRow(row: row, isOn: featureBinding(row.feature))
                    .disabled(writesDisabled || !isFeatureEditable(row))
            }
        }
    }

    var privacySection: some View {
        AdvancedSettingsSection(title: L10n.string("Privacy")) {
            AdvancedSettingsKeyValueRow(label: L10n.string("Privacy rules"), value: privacyRulesLabel)
            AdvancedSettingsKeyValueRow(label: L10n.string("Remote AI"), value: remoteScopeLabel)
            Button(L10n.string("Manage privacy rules"), action: openPrivacyRules)
                .accessibilityIdentifier("ai-privacy-rules-ai-settings-config-manage-privacy-rules")
        }
    }

    var logSection: some View {
        AdvancedSettingsSection(title: L10n.string("Log")) {
            Button(L10n.string("View AI call log")) { model.openCallLogEntry(); isCallLogPresented = true }
                .accessibilityIdentifier("ai-call-log-ai-call-log-core-open-ai-call-log")
            Text(L10n.string("See when AI was used and whether it was local or remote."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    var safetySection: some View {
        AdvancedSettingsSection(title: L10n.string("Safety")) {
            Button(L10n.string("Pause all AI"), action: pauseAllAI)
                .disabled(writesDisabled || !(model.snapshot?.config.aiEnabled ?? false))
            Button(L10n.string("Clear AI generated suggestions..."), action: model.openCallLogEntry)
                .disabled(true)
            Text(L10n.string("Clear generated suggestions from the AI call log after reviewing recent activity."))
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
            return L10n.string("Loading AI settings...")
        }
        if !config.aiEnabled {
            return L10n.string("AI is off. AreaMatrix will not call local or remote models.")
        }
        if config.remoteAIAllowed {
            return L10n.string("Remote AI is enabled for selected features.")
        }
        return L10n.string("Local AI is enabled. Files stay on this device.")
    }

    var localModelLabel: String {
        guard let config = model.snapshot?.config else { return L10n.string("Loading") }
        return config.localAIEnabled ? L10n.string("Ready") : L10n.string("Not installed")
    }

    var remoteModelLabel: String {
        guard let config = model.snapshot?.config else { return L10n.string("Loading") }
        return config.remoteAIAllowed ? L10n.string("Configured") : L10n.string("Off")
    }

    var privacyRulesLabel: String {
        guard let config = model.snapshot?.config else { return L10n.string("Loading") }
        guard config.privacyGateEnabled else { return L10n.string("Off") }
        return config.privacyPolicyRef ?? L10n.string("Default gate enabled")
    }

    var remoteScopeLabel: String {
        guard let config = model.snapshot?.config else { return L10n.string("Loading") }
        return config.remoteAIAllowed
            ? L10n.string("Allowed for selected features")
            : L10n.string("Remote AI is not configured")
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

    func isFeatureEditable(_: AISettingsFeatureRowSnapshot) -> Bool {
        model.snapshot?.config.aiEnabled == true
    }

    func remoteScopeText(_ capability: AISettingsCapabilitySnapshot) -> String {
        if capability.remoteAllowed { return L10n.string("Remote scope allowed") }
        return L10n.string("Remote scope blocked")
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
        AdvancedSettingsSection(title: L10n.string("AI features")) {
            ProgressView("Loading AI settings...")
            Text(L10n.string("AI controls are disabled until settings finish loading."))
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
            Button(L10n.string("Retry"), action: retry)
            Button(L10n.string("View AI call log"), action: openLog)
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
            row.enabled ? L10n.string("On") : L10n.string("Off"),
            row.providerLabel,
            row.remoteScope,
            row.disabledReason ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
