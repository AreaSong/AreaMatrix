import AreaMatrixFeatureIngestion
import SwiftUI

#if DEBUG
@MainActor
struct DeveloperMainListScenarioView: View {
    private let opening = DeveloperMainListScenarioFixture.opening
    private let session: RepositorySession
    private let assembly: MainRepositoryContentAssembly

    init() {
        let core = DeveloperMainListCoreFixture()
        let search = DeveloperSearchCoreFixture()
        let actions = DeveloperFileActionCoreFixture()
        let errorMapper = CoreErrorSnapshotMapper()
        let dependencies = AppDependencyContainer.live(coreServices: AppCoreServices())
        let supporting = Self.makeSupporting(core: core, search: search, actions: actions, errorMapper: errorMapper)
        let list = Self.makeList(
            core: core,
            search: search,
            actions: actions,
            errorMapper: errorMapper,
            dependencies: dependencies
        )
        let features = Self.makeFeatures(dependencies: dependencies)
        session = DeveloperMainListScenarioFixture.opening.makeRepositorySession()
        assembly = MainRepositoryContentAssembly.make(
            session: session,
            opening: DeveloperMainListScenarioFixture.opening,
            supporting: supporting,
            list: list,
            features: features
        )
    }

    private static func makeSupporting(
        core: DeveloperMainListCoreFixture,
        search: DeveloperSearchCoreFixture,
        actions: DeveloperFileActionCoreFixture,
        errorMapper: CoreErrorSnapshotMapper
    ) -> MainRepositoryContentSupportDeps {
        MainRepositoryContentSupportDeps(
            treeLister: core,
            savedSearchStore: search,
            batchRenamer: actions,
            systemCapabilityChecker: DeveloperMainListSystemCapabilityChecker(),
            errorMapper: errorMapper,
            syncConflictDetector: core,
            noteStore: DeveloperDetailNoteStore(),
            inFlightFileChangeTracker: InFlightFileChangeTracker(),
            dropCategoryPredictor: core
        )
    }

    private static func makeList(
        core: DeveloperMainListCoreFixture,
        search: DeveloperSearchCoreFixture,
        actions: DeveloperFileActionCoreFixture,
        errorMapper: CoreErrorSnapshotMapper,
        dependencies: AppDependencyContainer
    ) -> MainRepositoryContentListDependencies {
        MainRepositoryContentListDependencies(
            fileLister: core,
            fileDetailer: core,
            missingFileRecoverer: core,
            missingFilePicker: DeveloperMainListMissingFilePicker(),
            searchQuerying: search,
            semanticSearching: core,
            semanticFallbackReader: core,
            searchFiltering: core,
            commandIndexer: core,
            fileRenamer: core,
            fileDeleter: core,
            fileCategoryMover: core,
            categoryPredictor: core,
            batchDeleter: actions,
            batchCategoryChanger: actions,
            iCloudConflictResolver: DeveloperMainListICloudConflictResolver(),
            tagStore: actions,
            aiSettingsLoader: DeveloperAISettingsStore(),
            aiTagSuggestionStore: DeveloperMainListAITagFixture(),
            aiPrivacyRules: DeveloperAIPrivacyFixture(),
            undoActionStore: actions,
            redoActionStore: actions,
            changeLogLister: core,
            externalChangesSyncer: core,
            repositoryWriteCoordinator: RepositoryWriteCoordinator(),
            errorMapper: errorMapper,
            diagnosticsCollector: core,
            fileResourceAccess: dependencies.feature.import.fileResourceAccess
        )
    }

    private static func makeFeatures(
        dependencies: AppDependencyContainer
    ) -> MainRepositoryContentFeatureDependencies {
        MainRepositoryContentFeatureDependencies(
            aiFeature: dependencies.feature.aiFeature,
            fileActions: dependencies.feature.fileActions,
            settings: dependencies.feature.settings,
            syncConflicts: dependencies.feature.syncConflicts
        )
    }

    var body: some View {
        MainRepositoryContentView(
            session: session,
            opening: opening,
            state: .list,
            assembly: assembly,
            commandRouter: .shared,
            onImport: {},
            onDropImport: { _, _ in }
        )
        .frame(minWidth: 980, minHeight: 620)
        .background(.background)
    }
}
#endif
