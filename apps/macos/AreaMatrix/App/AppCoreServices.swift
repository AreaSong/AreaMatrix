import AreaMatrixCoreBridgeContract
import AreaMatrixFeatureAI
import Foundation

struct AppCoreServices {
    let repositoryWriteCoordinator: RepositoryWriteCoordinator
    let overviewRegenerationCoordinator: OverviewRegenerationCoordinator
    private let bridge: CoreBridge

    init(
        bridge: CoreBridge = CoreBridgeRuntime.shared,
        repositoryWriteCoordinator: RepositoryWriteCoordinator = RepositoryWriteCoordinator(),
        overviewRegenerationCoordinator: OverviewRegenerationCoordinator = OverviewRegenerationCoordinator()
    ) {
        self.bridge = bridge
        self.repositoryWriteCoordinator = repositoryWriteCoordinator
        self.overviewRegenerationCoordinator = overviewRegenerationCoordinator
    }

    var treeLister: any CoreRepositoryTreeListing {
        coreBridge()
    }

    var savedSearchStore: any CoreSavedSearchCRUD {
        coreBridge()
    }

    var configurationLoader: any CoreConfigurationLoading {
        coreBridge()
    }

    var configurationUpdater: any CoreConfigurationUpdating {
        coreBridge()
    }

    var emptyRepositoryOpener: any CoreEmptyRepositoryOpening {
        coreBridge()
    }

    var repositoryPathValidator: any CoreRepositoryPathValidating {
        coreBridge()
    }

    var initializedRepositoryPathValidator: any CoreInitializedRepositoryPathValidating {
        coreBridge()
    }

    var repositoryInitializer: any CoreRepositoryInitializing {
        coreBridge()
    }

    var importProgressImporter: any CoreFileImporting {
        coreBridge()
    }

    var batchFileImporter: any CoreBatchCopyImporting {
        coreBridge()
    }

    var conflictBatcher: any CoreImportConflictBatching {
        coreBridge()
    }

    var startupRecoverer: any CoreStartupRecovering {
        coreBridge()
    }

    var metadataRepairer: any CoreMetadataRepairing {
        coreBridge()
    }

    var repositoryReindexer: any CoreRepositoryReindexing {
        coreBridge()
    }

    var scanSessionReader: any CoreScanSessionReading {
        coreBridge()
    }

    var fileLister: any CoreFileListing {
        coreBridge()
    }

    var fileDetailer: any CoreFileDetailing {
        coreBridge()
    }

    var missingFileRecoverer: any CoreMissingFileRecovering {
        coreBridge()
    }

    var searchQuerying: any CoreSearchQuerying {
        coreBridge()
    }

    var semanticSearching: any CoreSemanticSearching {
        coreBridge()
    }

    var semanticFallbackReader: any CoreSemanticFallbackStatusReading {
        coreBridge()
    }

    var searchFiltering: any CoreSearchFiltering {
        coreBridge()
    }

    var commandIndexer: any CoreCommandIndexing {
        coreBridge()
    }

    var bindingContractInspector: any CoreBindingContractInspecting {
        coreBridge()
    }

    var fileRenamer: any CoreFileRenaming {
        coreBridge()
    }

    var fileDeleter: any CoreFileDeleting {
        coreBridge()
    }

    var fileCategoryMover: any CoreFileCategoryMoving {
        coreBridge()
    }

    var categoryPredictor: any CoreCategoryPredicting {
        coreBridge()
    }

    var classifierRuleSaver: any CoreClassifierRuleSaving {
        coreBridge()
    }

    var classifierImpactPreviewer: any CoreClassifierImpactPreviewing {
        coreBridge()
    }

    var classifierRuleEditor: any CoreClassifierRuleEditing {
        coreBridge()
    }

    var platformCapabilityLoader: any CorePlatformCapabilitiesLoading {
        coreBridge()
    }

    var batchDeleter: any CoreBatchDeleting {
        coreBridge()
    }

    var batchCategoryChanger: any CoreBatchCategoryChanging {
        coreBridge()
    }

    var batchRenamer: any CoreBatchRenaming {
        coreBridge()
    }

    var syncConflictDetector: any CoreSyncConflictDetecting {
        coreBridge()
    }

    var syncConflictResolver: any CoreSyncConflictResolving {
        coreBridge()
    }

    var iCloudConflictLister: any CoreICloudConflictListing {
        coreBridge()
    }

    var iCloudConflictReviewer: any CoreICloudConflictReviewing {
        coreBridge()
    }

    var iCloudConflictResolver: any ICloudConflictResolving {
        coreBridge()
    }

    var tagStore: any CoreTagCRUD {
        coreBridge()
    }

    var aiSettingsLoader: any CoreAISettingsLoading {
        coreBridge()
    }

    var aiSettingsUpdater: any CoreAISettingsUpdating {
        coreBridge()
    }

    var aiTagSuggestionStore: any CoreAITagSuggestionManaging {
        coreBridge()
    }

    var aiClassificationSuggester: any CoreAIClassificationSuggesting {
        coreBridge()
    }

    var aiClassificationFallbackReader: any CoreAIClassificationFallbackStatusReading {
        coreBridge()
    }

    var remoteProviderConfigurer: any CoreRemoteProviderConfiguring {
        coreBridge()
    }

    var aiCallLogLister: any CoreAICallLogListing {
        coreBridge()
    }

    var aiCallLogClearer: any CoreAICallLogClearing {
        coreBridge()
    }

    var aiSummaryStore: any CoreAISummaryManaging {
        coreBridge()
    }

    var repositoryContentLocaleSnapshotter: any RepositoryContentLocaleSnapshotting {
        coreBridge()
    }

    var overviewRegenerator: any CoreOverviewRegenerating {
        coreBridge()
    }

    var localModelStatusReader: any CoreLocalModelStatusReading {
        coreBridge()
    }

    var aiPrivacyRules: any CoreAIPrivacyEvaluating {
        coreBridge()
    }

    var aiPrivacyRulesManager: any CoreAIPrivacyRulesManaging {
        coreBridge()
    }

    var undoActionStore: any CoreUndoActionLogging {
        coreBridge()
    }

    var redoActionStore: any CoreRedoActionLogging {
        coreBridge()
    }

    var changeLogLister: any CoreChangeLogListing {
        coreBridge()
    }

    var externalChangesSyncer: any CoreExternalChangesSyncing {
        coreBridge()
    }

    var coreVersionLoader: any CoreVersionLoading {
        coreBridge()
    }

    var coreVersionReader: any CoreVersionReading {
        coreBridge()
    }

    var noteStore: any CoreNoteReadingWriting {
        coreBridge()
    }

    var errorMapper: any CoreErrorMapping {
        coreBridge()
    }

    var diagnosticsCollector: any CoreDiagnosticsCollecting {
        coreBridge()
    }

    var observabilityController: any CoreObservabilityControlling {
        coreBridge()
    }

    private func coreBridge() -> CoreBridge {
        bridge
    }
}
