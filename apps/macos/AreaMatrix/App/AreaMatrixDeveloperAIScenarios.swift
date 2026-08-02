import SwiftUI

#if DEBUG
@MainActor
struct DeveloperAIScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .aiCallLog:
            DeveloperAICallLogScenario()
        case .aiClassificationSuggestion:
            DeveloperAIClassificationScenario()
        case .aiPrivacyRules:
            DeveloperAIPrivacyRulesScenario()
        case .aiSettings:
            DeveloperAISettingsScenario()
        case .aiSummaryEditor:
            DeveloperAISummaryScenario()
        case .aiTagSuggestions:
            DeveloperAITagSuggestionsScenario()
        case .aiLocalModelStatus:
            DeveloperAILocalModelScenario()
        case .aiRemoteModelConfig:
            DeveloperAIRemoteModelScenario()
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperAICallLogScenario: View {
    private let core = DeveloperAICallLogFixture()

    var body: some View {
        AICallLogView(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            lister: core,
            clearer: core,
            errorMapper: CoreErrorSnapshotMapper()
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperAIClassificationScenario: View {
    private let model: AIClassificationSuggestionPanelModel

    init() {
        let core = DeveloperAIClassificationFixture()
        model = AIClassificationSuggestionPanelModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            request: AIClassificationSuggestionRequestState(
                fileID: DeveloperAIScenarioFixture.fileID,
                contextPolicy: .limitedTextSummary
            ),
            suggester: core,
            fallbackReader: core,
            errorMapper: CoreErrorSnapshotMapper()
        )
    }

    var body: some View {
        AIClassificationSuggestionPanel(
            model: model,
            fileName: DeveloperAIScenarioFixture.file.currentName,
            currentPath: DeveloperAIScenarioFixture.file.path
        )
        .frame(maxWidth: 680, alignment: .topLeading)
        .padding(24)
        .task { await model.askForSuggestion() }
    }
}

@MainActor
private struct DeveloperAIPrivacyRulesScenario: View {
    private let model: AISettingsModel
    private let providerModel: AIPrivacyRemoteProviderStateModel
    private let privacyModel: AIPrivacyRulesModel

    init() {
        let settingsStore = DeveloperAISettingsStore()
        let provider = DeveloperRemoteProviderFixture()
        let privacy = DeveloperAIPrivacyFixture()
        let errorMapper = CoreErrorSnapshotMapper()
        let model = AISettingsModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            loader: settingsStore,
            updater: settingsStore,
            errorMapper: errorMapper
        )
        self.model = model
        providerModel = AIPrivacyRemoteProviderStateModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            providerReader: provider,
            errorMapper: errorMapper
        )
        privacyModel = AIPrivacyRulesModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            rulesManager: privacy,
            evaluator: privacy,
            errorMapper: errorMapper,
            settingsSync: model
        )
    }

    var body: some View {
        AIPrivacyRulesRouteView(
            route: AIPrivacyRulesRoute(
                repoPath: DeveloperAIScenarioFixture.repoPath,
                focus: .rule(ruleID: "rule-confidential")
            ),
            model: model,
            registryReader: DeveloperAIPrivacyRegistryReader(),
            providerModel: providerModel,
            privacyModel: privacyModel,
            onConfigureRemoteAI: {},
            onClose: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperAISettingsScenario: View {
    private let model: AISettingsModel
    private let dependencies: AISettingsPaneDependencies

    init() {
        let assembly = DeveloperAISettingsScenarioAssembly()
        model = assembly.makeModel()
        dependencies = assembly.makeDependencies(settingsModel: model)
    }

    var body: some View {
        AISettingsPane(model: model, dependencies: dependencies)
            .background(.background)
    }
}

@MainActor
private struct DeveloperAISettingsScenarioAssembly {
    private let settingsStore = DeveloperAISettingsStore()
    private let provider = DeveloperRemoteProviderFixture()
    private let privacy = DeveloperAIPrivacyFixture()
    private let callLog = DeveloperAICallLogFixture()
    private let localModel = DeveloperLocalModelFixture()
    private let localActions = DeveloperLocalModelPlatformActions()
    private let credentialStore = DeveloperRemoteCredentialStore()
    private let errorMapper = CoreErrorSnapshotMapper()

    func makeModel() -> AISettingsModel {
        AISettingsModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            loader: settingsStore,
            updater: settingsStore,
            errorMapper: errorMapper
        )
    }

    func makeDependencies(settingsModel: AISettingsModel) -> AISettingsPaneDependencies {
        AISettingsPaneDependencies(
            makeLocalModelStatus: { repoPath in
                LocalModelStatusModel(
                    repoPath: repoPath,
                    storageLocationProvider: localActions,
                    statusReader: localModel,
                    installHelpOpener: localActions,
                    folderOpener: localActions,
                    diagnosticsCopier: localActions,
                    errorMapper: errorMapper
                )
            },
            makeRemoteProviderConfig: { repoPath in
                RemoteProviderConfigModel(
                    repoPath: repoPath,
                    bridge: provider,
                    credentialStore: credentialStore,
                    errorMapper: errorMapper
                )
            },
            makeRemotePrivacyGate: { repoPath in
                RemotePrivacyGateModel(repoPath: repoPath, bridge: privacy, errorMapper: errorMapper)
            },
            makePrivacyProviderState: { repoPath in
                AIPrivacyRemoteProviderStateModel(
                    repoPath: repoPath,
                    providerReader: provider,
                    errorMapper: errorMapper
                )
            },
            makePrivacyRules: { repoPath, settingsModel in
                AIPrivacyRulesModel(
                    repoPath: repoPath,
                    rulesManager: privacy,
                    evaluator: privacy,
                    errorMapper: errorMapper,
                    settingsSync: settingsModel
                )
            },
            privacyRegistryReader: DeveloperAIPrivacyRegistryReader(),
            callLogLister: callLog,
            callLogClearer: callLog,
            errorMapper: errorMapper
        )
    }
}

@MainActor
private struct DeveloperAISummaryScenario: View {
    private let model = AISummaryEditorModel(
        repoPath: DeveloperAIScenarioFixture.repoPath,
        fileID: DeveloperAIScenarioFixture.fileID,
        summaryStore: DeveloperAISummaryFixture(),
        contentLocaleSnapshotter: DeveloperContentLocaleSnapshotter(),
        privacyRules: DeveloperAIPrivacyFixture(),
        errorMapper: CoreErrorSnapshotMapper()
    )

    var body: some View {
        AISummaryEditor(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            fileID: DeveloperAIScenarioFixture.fileID,
            aiDependencies: AppDependencyContainer.live.feature.ai,
            errorMapper: CoreErrorSnapshotMapper(),
            model: model
        )
        .frame(maxWidth: 720, alignment: .topLeading)
        .padding(24)
    }
}

@MainActor
private struct DeveloperAITagSuggestionsScenario: View {
    private let report = DeveloperAIScenarioFixture.tagReport

    var body: some View {
        AITagSuggestionsPanel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            aiDependencies: AppDependencyContainer.live.feature.ai,
            errorMapper: CoreErrorSnapshotMapper(),
            file: DeveloperAIScenarioFixture.file,
            existingTags: DeveloperAIScenarioFixture.existingTags,
            state: .loaded(
                fileID: DeveloperAIScenarioFixture.fileID,
                report,
                Set(report.suggestions.filter(\.selectedByDefault).map(\.suggestionId))
            ),
            disabledReason: nil,
            onRetry: {},
            onToggleSuggestion: { _ in },
            onApplySingleSuggestion: { _ in },
            onSelectHighConfidence: {},
            onClearSelection: {},
            onStartEditing: {},
            onCancelEditing: {},
            onEditDisplayName: { _, _ in },
            onEditSlug: { _, _ in },
            onRegenerateSlug: { _ in },
            onApplySelected: {},
            onApplyEdited: {},
            onRetryFailed: {},
            onOpenAISettings: {},
            onClose: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperAILocalModelScenario: View {
    private let model: LocalModelStatusModel

    init() {
        let actions = DeveloperLocalModelPlatformActions()
        model = LocalModelStatusModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            storageLocationProvider: actions,
            statusReader: DeveloperLocalModelFixture(),
            installHelpOpener: actions,
            folderOpener: actions,
            diagnosticsCopier: actions,
            errorMapper: CoreErrorSnapshotMapper()
        )
    }

    var body: some View {
        LocalModelStatusView(model: model)
            .background(.background)
            .task {
                if model.snapshot == nil {
                    await model.checkStatus()
                }
            }
    }
}

@MainActor
private struct DeveloperAIRemoteModelScenario: View {
    private let model: RemoteProviderConfigModel
    private let privacyModel: RemotePrivacyGateModel

    init() {
        let provider = DeveloperRemoteProviderFixture()
        let privacy = DeveloperAIPrivacyFixture()
        let errorMapper = CoreErrorSnapshotMapper()
        model = RemoteProviderConfigModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            bridge: provider,
            credentialStore: DeveloperRemoteCredentialStore(),
            errorMapper: errorMapper
        )
        privacyModel = RemotePrivacyGateModel(
            repoPath: DeveloperAIScenarioFixture.repoPath,
            bridge: privacy,
            errorMapper: errorMapper
        )
    }

    var body: some View {
        RemoteModelConfigSheet(model: model, privacyModel: privacyModel)
            .background(.background)
    }
}
#endif
