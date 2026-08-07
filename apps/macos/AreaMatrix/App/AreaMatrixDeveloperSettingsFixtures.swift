import AreaMatrixCoreBridgeContract
import AreaMatrixCoreContracts
import Foundation

#if DEBUG
enum DeveloperSettingsScenarioFixture {
    static let appVersion = "Developer Scenario"

    static func config() -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot(
            repoPath: AreaMatrixPreviewFixtures.repositoryPath,
            revision: 7,
            defaultMode: "Copied",
            overviewOutput: "AreaMatrix",
            aiEnabled: false,
            locale: "en",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }

    static func classifierState() -> ClassifierRuleEditorSnapshotState {
        ClassifierRuleEditorSnapshotState(
            rules: [
                classifierRule(
                    id: "docs",
                    sampleDisplayName: "Documents",
                    extensions: ["md", "pdf"],
                    isDefault: true
                ),
                classifierRule(
                    id: "finance",
                    sampleDisplayName: "Finance",
                    extensions: ["xlsx", "csv"],
                    priority: 10
                )
            ],
            defaultRuleID: "docs",
            updatedRuleID: nil,
            repositoryLocalePolicy: "en",
            editingLocale: .en,
            health: .valid,
            recoveryActions: [],
            warning: nil
        )
    }

    private static func classifierRule(
        id: String,
        sampleDisplayName: String,
        extensions: [String],
        priority: Int64 = 0,
        isDefault: Bool = false
    ) -> ClassifierRuleRecordSnapshot {
        // Classifier maps are representative repository content, not application-owned interface copy.
        let sampleDescription = "Developer scenario rule"
        return ClassifierRuleRecordSnapshot(
            ruleID: id,
            slug: id,
            displayNames: ["en": sampleDisplayName, "zh-Hans": sampleDisplayName],
            descriptions: ["en": sampleDescription, "zh-Hans": sampleDescription],
            extensions: extensions,
            keywords: [id, "sample"],
            priority: priority,
            namingTemplate: nil,
            isDefault: isDefault
        )
    }
}

struct DeveloperSettingsVersionReader: AppVersionReading, CoreVersionReading {
    func appVersion() -> String {
        DeveloperSettingsScenarioFixture.appVersion
    }

    func coreVersion() async throws -> String {
        "0.1.0-developer"
    }
}

actor DeveloperSettingsMetadataReader: ExistingRepositoryMetadataReading {
    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(
            schemaVersion: 1,
            lastOpenedAt: 1_778_738_400,
            configuredRepoPath: AreaMatrixPreviewFixtures.repositoryPath
        )
    }
}

actor DeveloperSettingsDiagnosticsCollector: CoreDiagnosticsCollecting {
    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/developer-scenario.zip",
            createdAt: 1_778_738_400,
            warnings: []
        )
    }
}

actor DeveloperCategoryPredictor: CoreCategoryPredicting {
    func predictCategory(repoPath _: String, filename: String) async throws -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: "docs",
            suggestedName: filename,
            reason: .extension,
            confidence: 0.94
        )
    }
}

actor DeveloperClassifierRuleEditor: CoreClassifierRuleEditing {
    private var state = DeveloperSettingsScenarioFixture.classifierState()

    func listClassifierRules(
        repoPath _: String,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        state
    }

    func createClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        state
    }

    func updateClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        state
    }

    func deleteClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        state
    }

    func createDefaultClassifier(
        repoPath _: String,
        confirmed _: Bool,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        state
    }

    func restoreDefaultClassifier(
        repoPath _: String,
        confirmed _: Bool,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        state
    }

    func restoreLastValidClassifier(
        repoPath _: String,
        confirmed _: Bool,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        state
    }
}

struct DeveloperICloudStatusDetector: ICloudStatusDetecting {
    func snapshot(repoPath _: String, config _: AppRepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        IntegrationsICloudSnapshot(repositoryLocation: .iCloudDrive, iCloudStatus: .available)
    }
}

actor DeveloperBindingContractInspector: CoreBindingContractInspecting {
    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot {
        BindingContractReportSnapshot(
            targetPlatform: targetPlatform,
            bindingVersion: bindingVersion,
            coreVersion: "0.1.0-developer",
            supportedApis: [
                BindingApiContractSnapshot(
                    name: "inspect_binding_contract",
                    capability: "binding-contract",
                    status: .supported,
                    reason: nil
                )
            ],
            typeMappings: [],
            missingCapabilities: []
        )
    }
}

struct DeveloperSettingsPlatformActions: AboutExternalLinkOpening,
    AboutStringCopying,
    AccessibilityAnnouncing,
    AdvancedSettingsDiagnosticSummaryCopying,
    ICloudHelpOpening,
    RepositoryFileOpening,
    RepositoryFileRevealing,
    RepositoryFinderOpening,
    RepositoryIgnoreRulesManaging,
    RepositoryPathCopying,
    RootOverviewFileInspecting {
    func status(repoPath _: String) -> RootOverviewFileStatus {
        .missing
    }

    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        link.urlString
    }

    @MainActor
    func copy(_: String) throws {}

    @MainActor
    func announce(_: LocalizedMessage) {}

    @MainActor
    func copyDiagnosticSummary(_: String) throws {}

    @MainActor
    func openICloudHelp() throws {}

    @MainActor
    func openFile(repoPath _: String, relativePath _: String) throws {}

    @MainActor
    func revealFile(repoPath _: String, relativePath _: String) throws {}

    @MainActor
    func openRepositoryInFinder(repoPath _: String) throws {}

    @MainActor
    func openIgnoreRules(repoPath _: String) throws {}

    @MainActor
    func createDefaultIgnoreRules(repoPath _: String) throws {}

    @MainActor
    func copyPath(repoPath _: String, relativePath _: String) throws {}

    @MainActor
    func copyPaths(repoPath _: String, relativePaths _: [String]) throws {}
}
#endif
