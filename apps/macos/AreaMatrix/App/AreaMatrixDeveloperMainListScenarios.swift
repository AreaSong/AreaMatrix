import SwiftUI

#if DEBUG
@MainActor
struct DeveloperMainListScenarioView: View {
    private let opening = DeveloperMainListScenarioFixture.opening
    private let assembly: MainRepositoryContentAssembly

    init() {
        let core = DeveloperMainListCoreFixture()
        let search = DeveloperSearchCoreFixture()
        let actions = DeveloperFileActionCoreFixture()
        assembly = MainRepositoryContentAssembly.make(
            opening: DeveloperMainListScenarioFixture.opening,
            treeLister: core,
            savedSearchStore: search,
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
            fileListCategoryPredictor: core,
            batchDeleter: actions,
            batchCategoryChanger: actions,
            batchRenamer: actions,
            systemCapabilityChecker: DeveloperMainListSystemCapabilityChecker(),
            syncConflictDetector: core,
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
            noteStore: DeveloperDetailNoteStore(),
            dropCategoryPredictor: core,
            errorMapper: CoreErrorSnapshotMapper(),
            diagnosticsCollector: core,
            aiDependencies: AppDependencyContainer.live.feature.ai,
            fileActionsDependencies: AppDependencyContainer.live.feature.fileActions,
            settingsDependencies: AppDependencyContainer.live.feature.settings,
            syncConflictsDependencies: AppDependencyContainer.live.feature.syncConflicts
        )
    }

    var body: some View {
        MainRepositoryContentView(
            opening: opening,
            state: .list,
            assembly: assembly,
            onImport: {},
            onDropImport: { _, _ in }
        )
        .frame(minWidth: 980, minHeight: 620)
        .background(.background)
    }
}
#endif
