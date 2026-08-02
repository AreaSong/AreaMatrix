import Foundation

/// Feature-scoped dependency values composed by the App target.
///
/// Each scope contains only the protocols used by that feature. The live
/// values are assembled once by the application; tests can construct a scope
/// with focused doubles through the memberwise initializers.
struct AppFeatureDependencyContainer {
    let shared: SharedFeatureDependencies
    let onboarding: OnboardingFeatureDependencies
    let ai: AIFeatureDependencies
    let fileActions: FileActionsFeatureDependencies
    let `import`: ImportFeatureDependencies
    let mainList: MainListFeatureDependencies
    let search: SearchFeatureDependencies
    let settings: SettingsFeatureDependencies
    let syncConflicts: SyncConflictsFeatureDependencies

    static let live = AppFeatureDependencyContainer(
        shared: SharedFeatureDependencies(
            errorMapper: AppCoreServices.errorMapper,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector,
            repositoryWriteCoordinator: AppCoreServices.repositoryWriteCoordinator
        ),
        onboarding: OnboardingFeatureDependencies(
            metadataRepairer: CoreBridgeRuntime.shared,
            repositoryReindexer: CoreBridgeRuntime.shared,
            startupRecoverer: AppCoreServices.startupRecoverer,
            repositoryWriteCoordinator: AppCoreServices.repositoryWriteCoordinator,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector,
            errorMapper: AppCoreServices.errorMapper
        ),
        ai: AIFeatureDependencies(
            aiCallLogLister: AppCoreServices.aiCallLogLister,
            aiCallLogClearer: AppCoreServices.aiCallLogClearer,
            aiClassificationSuggester: AppCoreServices.aiClassificationSuggester,
            aiClassificationFallbackReader: AppCoreServices.aiClassificationFallbackReader,
            aiPrivacyRules: AppCoreServices.aiPrivacyRules,
            aiPrivacyRulesManager: AppCoreServices.aiPrivacyRulesManager,
            aiSettingsLoader: AppCoreServices.aiSettingsLoader,
            aiSettingsUpdater: AppCoreServices.aiSettingsUpdater,
            aiSummaryStore: AppCoreServices.aiSummaryStore,
            aiTagSuggestionStore: AppCoreServices.aiTagSuggestionStore,
            classifierRuleEditor: AppCoreServices.classifierRuleEditor,
            localModelStatusReader: AppCoreServices.localModelStatusReader,
            remoteProviderConfigurer: AppCoreServices.remoteProviderConfigurer,
            contentLocaleSnapshotter: AppCoreServices.repositoryContentLocaleSnapshotter,
            searchFiltering: AppCoreServices.searchFiltering,
            privacyRuleRegistryReader: CoreAIPrivacyRuleRegistryReader(
                classifierReader: AppCoreServices.classifierRuleEditor,
                facetReader: AppCoreServices.searchFiltering
            )
        ),
        fileActions: FileActionsFeatureDependencies(
            classifierImpactPreviewer: AppCoreServices.classifierImpactPreviewer,
            classifierRuleSaver: AppCoreServices.classifierRuleSaver,
            iCloudConflictReviewer: AppCoreServices.iCloudConflictReviewer,
            repositoryPathValidator: AppCoreServices.repositoryPathValidator
        ),
        import: ImportFeatureDependencies(
            categoryPredictor: AppCoreServices.categoryPredictor,
            batchFileLoader: CoreBridgeBatchFileLoader(fileLister: AppCoreServices.fileLister),
            fileImporter: AppCoreServices.importProgressImporter,
            batchFileImporter: CoreBridgeRuntime.shared,
            conflictBatcher: CoreBridgeRuntime.shared,
            fileLister: AppCoreServices.fileLister,
            undoActionStore: AppCoreServices.undoActionStore,
            batchSessionStore: AppPlatformServices.importBatchSessionStore
        ),
        mainList: MainListFeatureDependencies(
            fileLister: AppCoreServices.fileLister,
            fileDetailer: AppCoreServices.fileDetailer,
            aiPrivacyRules: AppCoreServices.aiPrivacyRules,
            aiSettingsLoader: AppCoreServices.aiSettingsLoader,
            aiTagSuggestionStore: AppCoreServices.aiTagSuggestionStore,
            batchCategoryChanger: AppCoreServices.batchCategoryChanger,
            batchDeleter: AppCoreServices.batchDeleter,
            categoryPredictor: AppCoreServices.categoryPredictor,
            changeLogLister: AppCoreServices.changeLogLister,
            commandIndexer: AppCoreServices.commandIndexer,
            externalChangesSyncer: AppCoreServices.externalChangesSyncer,
            fileCategoryMover: AppCoreServices.fileCategoryMover,
            fileDeleter: AppCoreServices.fileDeleter,
            fileRenamer: AppCoreServices.fileRenamer,
            iCloudConflictResolver: AppCoreServices.iCloudConflictResolver,
            missingFileRecoverer: AppCoreServices.missingFileRecoverer,
            missingFilePicker: AppPlatformServices.missingFilePicker,
            redoActionStore: AppCoreServices.redoActionStore,
            searchFiltering: AppCoreServices.searchFiltering,
            searchQuerying: AppCoreServices.searchQuerying,
            semanticFallbackReader: AppCoreServices.semanticFallbackReader,
            semanticSearching: AppCoreServices.semanticSearching,
            tagStore: AppCoreServices.tagStore,
            undoActionStore: AppCoreServices.undoActionStore,
            repositoryWriteCoordinator: AppCoreServices.repositoryWriteCoordinator,
            errorMapper: AppCoreServices.errorMapper,
            diagnosticsCollector: AppCoreServices.diagnosticsCollector
        ),
        search: SearchFeatureDependencies(
            savedSearchStore: AppCoreServices.savedSearchStore,
            searchQuerying: AppCoreServices.searchQuerying
        ),
        settings: SettingsFeatureDependencies(
            aiCallLogClearer: AppCoreServices.aiCallLogClearer,
            aiCallLogLister: AppCoreServices.aiCallLogLister,
            bindingContractInspector: AppCoreServices.bindingContractInspector,
            categoryPredictor: AppCoreServices.categoryPredictor,
            classifierRuleEditor: AppCoreServices.classifierRuleEditor,
            configurationLoader: AppCoreServices.configurationLoader,
            configurationUpdater: AppCoreServices.configurationUpdater,
            coreVersionLoader: AppCoreServices.coreVersionLoader,
            coreVersionReader: AppCoreServices.coreVersionReader,
            emptyRepositoryOpener: AppCoreServices.emptyRepositoryOpener,
            localModelStatusReader: AppCoreServices.localModelStatusReader,
            overviewRegenerator: AppCoreServices.overviewRegenerator,
            platformCapabilityLoader: AppCoreServices.platformCapabilityLoader,
            scanSessionReader: AppCoreServices.scanSessionReader
        ),
        syncConflicts: SyncConflictsFeatureDependencies(
            iCloudConflictLister: AppCoreServices.iCloudConflictLister,
            iCloudConflictReviewer: AppCoreServices.iCloudConflictReviewer,
            repositoryPathValidator: AppCoreServices.repositoryPathValidator,
            systemCapabilityChecker: AppPlatformServices.systemCapabilityChecker,
            syncConflictDetector: AppCoreServices.syncConflictDetector,
            conflictResolver: CoreBridgeRuntime.shared
        )
    )
}
