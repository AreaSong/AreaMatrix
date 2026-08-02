import Foundation

enum AppCoreServices {
    static let repositoryWriteCoordinator = RepositoryWriteCoordinator.shared
    @MainActor static var overviewRegenerationCoordinator: OverviewRegenerationCoordinator {
        .shared
    }

    static var treeLister: any CoreRepositoryTreeListing {
        coreBridge()
    }

    static var savedSearchStore: any CoreSavedSearchCRUD {
        coreBridge()
    }

    static var configurationLoader: any CoreConfigurationLoading {
        coreBridge()
    }

    static var configurationUpdater: any CoreConfigurationUpdating {
        coreBridge()
    }

    static var emptyRepositoryOpener: any CoreEmptyRepositoryOpening {
        coreBridge()
    }

    static var repositoryPathValidator: any CoreRepositoryPathValidating {
        coreBridge()
    }

    static var initializedRepositoryPathValidator: any CoreInitializedRepositoryPathValidating {
        coreBridge()
    }

    static var repositoryInitializer: any CoreRepositoryInitializing {
        coreBridge()
    }

    static var importProgressImporter: any CoreFileImporting {
        coreBridge()
    }

    static var startupRecoverer: any CoreStartupRecovering {
        coreBridge()
    }

    static var scanSessionReader: any CoreScanSessionReading {
        coreBridge()
    }

    static var fileLister: any CoreFileListing {
        coreBridge()
    }

    static var fileDetailer: any CoreFileDetailing {
        coreBridge()
    }

    static var missingFileRecoverer: any CoreMissingFileRecovering {
        coreBridge()
    }

    static var searchQuerying: any CoreSearchQuerying {
        coreBridge()
    }

    static var semanticSearching: any CoreSemanticSearching {
        coreBridge()
    }

    static var semanticFallbackReader: any CoreSemanticFallbackStatusReading {
        coreBridge()
    }

    static var searchFiltering: any CoreSearchFiltering {
        coreBridge()
    }

    static var commandIndexer: any CoreCommandIndexing {
        coreBridge()
    }

    static var bindingContractInspector: any CoreBindingContractInspecting {
        coreBridge()
    }

    static var fileRenamer: any CoreFileRenaming {
        coreBridge()
    }

    static var fileDeleter: any CoreFileDeleting {
        coreBridge()
    }

    static var fileCategoryMover: any CoreFileCategoryMoving {
        coreBridge()
    }

    static var categoryPredictor: any CoreCategoryPredicting {
        coreBridge()
    }

    static var classifierRuleSaver: any CoreClassifierRuleSaving {
        coreBridge()
    }

    static var classifierImpactPreviewer: any CoreClassifierImpactPreviewing {
        coreBridge()
    }

    static var classifierRuleEditor: any CoreClassifierRuleEditing {
        coreBridge()
    }

    static var platformCapabilityLoader: any CorePlatformCapabilitiesLoading {
        coreBridge()
    }

    static var batchDeleter: any CoreBatchDeleting {
        coreBridge()
    }

    static var batchCategoryChanger: any CoreBatchCategoryChanging {
        coreBridge()
    }

    static var batchRenamer: any CoreBatchRenaming {
        coreBridge()
    }

    static var syncConflictDetector: any CoreSyncConflictDetecting {
        coreBridge()
    }

    static var iCloudConflictLister: any CoreICloudConflictListing {
        coreBridge()
    }

    static var iCloudConflictReviewer: any CoreICloudConflictReviewing {
        coreBridge()
    }

    static var iCloudConflictResolver: any ICloudConflictResolving {
        coreBridge()
    }

    static var tagStore: any CoreTagCRUD {
        coreBridge()
    }

    static var aiSettingsLoader: any CoreAISettingsLoading {
        coreBridge()
    }

    static var aiSettingsUpdater: any CoreAISettingsUpdating {
        coreBridge()
    }

    static var aiTagSuggestionStore: any CoreAITagSuggestionManaging {
        coreBridge()
    }

    static var aiClassificationSuggester: any CoreAIClassificationSuggesting {
        coreBridge()
    }

    static var aiClassificationFallbackReader: any CoreAIClassificationFallbackStatusReading {
        coreBridge()
    }

    static var remoteProviderConfigurer: any CoreRemoteProviderConfiguring {
        coreBridge()
    }

    static var aiCallLogLister: any CoreAICallLogListing {
        coreBridge()
    }

    static var aiCallLogClearer: any CoreAICallLogClearing {
        coreBridge()
    }

    static var aiSummaryStore: any CoreAISummaryManaging {
        coreBridge()
    }

    static var repositoryContentLocaleSnapshotter: any RepositoryContentLocaleSnapshotting {
        coreBridge()
    }

    static var overviewRegenerator: any CoreOverviewRegenerating {
        coreBridge()
    }

    static var localModelStatusReader: any CoreLocalModelStatusReading {
        coreBridge()
    }

    static var aiPrivacyRules: any CoreAIPrivacyEvaluating {
        coreBridge()
    }

    static var aiPrivacyRulesManager: any CoreAIPrivacyRulesManaging {
        coreBridge()
    }

    static var undoActionStore: any CoreUndoActionLogging {
        coreBridge()
    }

    static var redoActionStore: any CoreRedoActionLogging {
        coreBridge()
    }

    static var changeLogLister: any CoreChangeLogListing {
        coreBridge()
    }

    static var externalChangesSyncer: any CoreExternalChangesSyncing {
        coreBridge()
    }

    static var coreVersionLoader: any CoreVersionLoading {
        coreBridge()
    }

    static var coreVersionReader: any CoreVersionReading {
        coreBridge()
    }

    static var noteStore: any CoreNoteReadingWriting {
        coreBridge()
    }

    static var errorMapper: any CoreErrorMapping {
        coreBridge()
    }

    static var diagnosticsCollector: any CoreDiagnosticsCollecting {
        coreBridge()
    }

    static var observabilityController: any CoreObservabilityControlling {
        coreBridge()
    }

    private static func coreBridge() -> CoreBridge {
        CoreBridgeRuntime.shared
    }
}
