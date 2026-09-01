import SwiftUI

#if DEBUG
@MainActor
struct DeveloperSettingsScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .settingsAbout:
            DeveloperAboutSettingsScenario()
        case .settingsAdvanced:
            DeveloperAdvancedSettingsScenario()
        case .settingsClassifier:
            DeveloperClassifierSettingsScenario()
        case .settingsGeneral:
            DeveloperGeneralSettingsScenario()
        case .settingsIntegrations:
            DeveloperIntegrationsScenario()
        case .settingsLanguage:
            DeveloperLanguageSettingsScenario()
        case .settingsPlatformDifferences:
            DeveloperPlatformScenario()
        case .settingsRepository:
            DeveloperRepositorySettingsScenario()
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperAboutSettingsScenario: View {
    private let actions = DeveloperSettingsPlatformActions()
    private let errorMapper = CoreErrorSnapshotMapper()
    private let metadataReader = DeveloperSettingsMetadataReader()
    private let versionReader = DeveloperSettingsVersionReader()
    private let platformModel: PlatformDifferencesModel

    init() {
        platformModel = PlatformDifferencesModel(
            appVersion: DeveloperSettingsScenarioFixture.appVersion,
            appVersionReader: versionReader,
            repositoryText: AreaMatrixPreviewFixtures.repositoryPath,
            contractInspector: DeveloperBindingContractInspector(),
            capabilityLoader: DeveloperCapabilityLoader(),
            errorMapper: CoreErrorSnapshotMapper()
        )
    }

    var body: some View {
        AboutSettingsPane(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            appVersionReader: versionReader,
            coreVersionReader: versionReader,
            metadataReader: metadataReader,
            externalLinkOpener: actions,
            stringCopier: actions,
            errorMapper: errorMapper,
            accessibilityAnnouncer: actions,
            platformDifferencesModel: platformModel
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperAdvancedSettingsScenario: View {
    private let actions = DeveloperSettingsPlatformActions()
    private let actionLogger = DeveloperSettingsActionLogger()
    private let configStore = DeveloperConfigurationStore(config: DeveloperSettingsScenarioFixture.config())
    private let diagnosticsCollector = DeveloperSettingsDiagnosticsCollector()
    private let errorMapper = CoreErrorSnapshotMapper()
    private let metadataReader = DeveloperSettingsMetadataReader()
    private let versionReader = DeveloperSettingsVersionReader()

    var body: some View {
        AdvancedSettingsPane(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            loader: configStore,
            updater: configStore,
            rootOverviewInspector: actions,
            diagnosticsCollector: diagnosticsCollector,
            actionLogger: actionLogger,
            appVersionReader: versionReader,
            coreVersionReader: versionReader,
            metadataReader: metadataReader,
            summaryCopier: actions,
            errorMapper: errorMapper
        )
        .background(.background)
    }
}

private struct DeveloperSettingsActionLogger: AppUIActionLogging {
    func logUIAction(_: String, context _: AppUIActionContext) {}

    func recordUIAction(actionID _: String, context _: AppUIActionContext) async {}

    func recordUIAction(traceContext _: CoreImportTraceContext) async {}

    func recordSemanticEvent(_: ObservabilitySemanticEventInput) async {}
}

@MainActor
private struct DeveloperClassifierSettingsScenario: View {
    private let model: ClassifierSettingsModel

    init() {
        let actions = DeveloperSettingsPlatformActions()
        let configStore = DeveloperConfigurationStore(config: DeveloperSettingsScenarioFixture.config())
        model = ClassifierSettingsModel(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            loader: configStore,
            updater: configStore,
            predictor: DeveloperCategoryPredictor(),
            ruleEditor: DeveloperClassifierRuleEditor(),
            errorMapper: CoreErrorSnapshotMapper(),
            fileOpener: actions,
            fileRevealer: actions,
            finderOpener: actions,
            accessibilityAnnouncer: actions
        )
    }

    var body: some View {
        ClassifierSettingsPane(model: model)
            .background(.background)
    }
}

@MainActor
private struct DeveloperGeneralSettingsScenario: View {
    private let actions = DeveloperSettingsPlatformActions()
    private let configStore = DeveloperConfigurationStore(config: DeveloperSettingsScenarioFixture.config())
    private let dependencies = AppDependencyContainer.live(coreServices: AppCoreServices())

    var body: some View {
        GeneralSettingsView(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            selectedTab: .constant("general"),
            onClose: {},
            featureDependencies: dependencies.feature.settings,
            aiDependencies: dependencies.feature.aiFeature,
            sharedDependencies: dependencies.feature.shared,
            syncConflictsDependencies: dependencies.feature.syncConflicts,
            diagnosticsDependencies: dependencies.feature.diagnostics,
            loader: configStore,
            updater: configStore,
            rootOverviewInspector: actions,
            rootOverviewRevealer: actions,
            ignoreRulesManager: actions,
            errorMapper: CoreErrorSnapshotMapper()
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperIntegrationsScenario: View {
    private let actions = DeveloperSettingsPlatformActions()
    private let configStore = DeveloperConfigurationStore(config: DeveloperSettingsScenarioFixture.config())
    private let dependencies = AppDependencyContainer.live(coreServices: AppCoreServices())

    var body: some View {
        IntegrationsSettingsPane(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            loader: configStore,
            updater: configStore,
            errorMapper: CoreErrorSnapshotMapper(),
            syncConflictsDependencies: dependencies.feature.syncConflicts,
            statusDetector: DeveloperICloudStatusDetector(),
            finderOpener: actions,
            helpOpener: actions
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperLanguageSettingsScenario: View {
    private let configStore = DeveloperConfigurationStore(config: DeveloperSettingsScenarioFixture.config())
    private let capabilityLoader = DeveloperCapabilityLoader()
    private let overviewRegenerator = DeveloperOverviewRegenerator()
    private let overviewRegenerationCoordinator = OverviewRegenerationCoordinator()

    var body: some View {
        LanguageSettingsPane(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            loader: configStore,
            updater: configStore,
            capabilityLoader: capabilityLoader,
            overviewRegenerator: overviewRegenerator,
            overviewRegenerationCoordinator: overviewRegenerationCoordinator,
            appVersion: DeveloperSettingsScenarioFixture.appVersion,
            appVersionReader: DeveloperSettingsVersionReader(),
            errorMapper: CoreErrorSnapshotMapper(),
            accessibilityAnnouncer: DeveloperSettingsPlatformActions()
        )
        .background(.background)
        .accessibilityIdentifier("developer.languageSettings")
    }
}

@MainActor
private struct DeveloperPlatformScenario: View {
    private let model = PlatformDifferencesModel(
        appVersion: DeveloperSettingsScenarioFixture.appVersion,
        appVersionReader: DeveloperSettingsVersionReader(),
        repositoryText: AreaMatrixPreviewFixtures.repositoryPath,
        contractInspector: DeveloperBindingContractInspector(),
        capabilityLoader: DeveloperCapabilityLoader(),
        errorMapper: CoreErrorSnapshotMapper()
    )

    var body: some View {
        SettingsPageScrollContent {
            PlatformDifferencesView(model: model)
        }
        .background(.background)
    }
}

@MainActor
private struct DeveloperRepositorySettingsScenario: View {
    private let dependencies = AppDependencyContainer.live(coreServices: AppCoreServices())

    var body: some View {
        RepositorySettingsPane(
            repoPath: "",
            featureDependencies: dependencies.feature.settings,
            sharedDependencies: dependencies.feature.shared
        )
        .background(.background)
    }
}

#endif
