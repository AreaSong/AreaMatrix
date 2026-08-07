import AreaMatrixCoreBridgeContract
import Foundation

/// Shared, low-level defaults used by more than one feature.
///
/// The App target owns the live composition. Feature code only sees protocol
/// values and can replace them through its initializer parameters in tests.
struct SharedFeatureDependencies {
    let errorMapper: any CoreErrorMapping
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    let repositoryWriteCoordinator: RepositoryWriteCoordinator
    let actionLogger: any AppUIActionLogging
}

struct AIFeatureDependencies {
    let aiCallLogLister: any CoreAICallLogListing
    let aiCallLogClearer: any CoreAICallLogClearing
    let aiClassificationSuggester: any CoreAIClassificationSuggesting
    let aiClassificationFallbackReader: any CoreAIClassificationFallbackStatusReading
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let aiPrivacyRulesManager: any CoreAIPrivacyRulesManaging
    let aiSettingsLoader: any CoreAISettingsLoading
    let aiSettingsUpdater: any CoreAISettingsUpdating
    let aiSummaryStore: any CoreAISummaryManaging
    let aiTagSuggestionStore: any CoreAITagSuggestionManaging
    let classifierRuleEditor: any CoreClassifierRuleEditing
    let localModelStatusReader: any CoreLocalModelStatusReading
    let localModelStorageLocationProvider: any LocalModelStorageLocationProviding
    let localModelInstallHelpOpener: any LocalModelInstallHelpOpening
    let localModelFolderOpener: any LocalModelFolderOpening
    let localModelDiagnosticsCopier: any LocalModelDiagnosticsCopying
    let remoteProviderConfigurer: any CoreRemoteProviderConfiguring
    let remoteProviderCredentialStore: any RemoteProviderCredentialStoring
    let contentLocaleSnapshotter: any RepositoryContentLocaleSnapshotting
    let searchFiltering: any CoreSearchFiltering
    let privacyRuleRegistryReader: any AIPrivacyRuleRegistryReading
}

struct OnboardingFeatureDependencies {
    let metadataRepairer: any CoreMetadataRepairing
    let repositoryReindexer: any CoreRepositoryReindexing
    let startupRecoverer: any CoreStartupRecovering
    let repositoryWriteCoordinator: RepositoryWriteCoordinator
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    let errorMapper: any CoreErrorMapping
}

struct FileActionsFeatureDependencies {
    let classifierImpactPreviewer: any CoreClassifierImpactPreviewing
    let classifierRuleSaver: any CoreClassifierRuleSaving
    let iCloudConflictReviewer: any CoreICloudConflictReviewing
    let repositoryPathValidator: any CoreRepositoryPathValidating
}

struct ImportFeatureDependencies {
    let actionLogger: any AppUIActionLogging
    let fileResourceAccess: any ImportFileResourceAccessing
    let categoryPredictor: any CoreCategoryPredicting
    let batchFileLoader: any ImportBatchCoreFileLoading
    let fileImporter: any CoreFileImporting
    let batchFileImporter: any CoreBatchCopyImporting
    let conflictBatcher: any CoreImportConflictBatching
    let fileLister: any CoreFileListing
    let undoActionStore: any CoreUndoActionLogging
    let batchSessionStore: any ImportBatchSessionPersisting
    let folderScanner: any ImportFolderScanning
    let sourcePreflightInspector: any SourcePreflightInspecting
    let placeholderDownloader: any ICloudPlaceholderDownloading
}

struct MainListFeatureDependencies {
    let fileResourceAccess: any ImportFileResourceAccessing
    let fileLister: any CoreFileListing
    let fileDetailer: any CoreFileDetailing
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let aiSettingsLoader: any CoreAISettingsLoading
    let aiTagSuggestionStore: any CoreAITagSuggestionManaging
    let batchCategoryChanger: any CoreBatchCategoryChanging
    let batchDeleter: any CoreBatchDeleting
    let categoryPredictor: any CoreCategoryPredicting
    let changeLogLister: any CoreChangeLogListing
    let commandIndexer: any CoreCommandIndexing
    let externalChangesSyncer: any CoreExternalChangesSyncing
    let fileCategoryMover: any CoreFileCategoryMoving
    let fileDeleter: any CoreFileDeleting
    let fileRenamer: any CoreFileRenaming
    let iCloudConflictResolver: any ICloudConflictResolving
    let missingFileRecoverer: any CoreMissingFileRecovering
    let missingFilePicker: any RepositoryMissingFilePicking
    let redoActionStore: any CoreRedoActionLogging
    let searchFiltering: any CoreSearchFiltering
    let searchQuerying: any CoreSearchQuerying
    let semanticFallbackReader: any CoreSemanticFallbackStatusReading
    let semanticSearching: any CoreSemanticSearching
    let tagStore: any CoreTagCRUD
    let undoActionStore: any CoreUndoActionLogging
    let repositoryWriteCoordinator: RepositoryWriteCoordinator
    let errorMapper: any CoreErrorMapping
    let diagnosticsCollector: any CoreDiagnosticsCollecting
}

struct SearchFeatureDependencies {
    let savedSearchStore: any CoreSavedSearchCRUD
    let searchQuerying: any CoreSearchQuerying
}

struct SettingsFeatureDependencies {
    let aiCallLogClearer: any CoreAICallLogClearing
    let aiCallLogLister: any CoreAICallLogListing
    let bindingContractInspector: any CoreBindingContractInspecting
    let categoryPredictor: any CoreCategoryPredicting
    let classifierRuleEditor: any CoreClassifierRuleEditing
    let interfaceLocaleIdentifier: @MainActor () -> String
    let configurationLoader: any CoreConfigurationLoading
    let configurationUpdater: any CoreConfigurationUpdating
    let coreVersionLoader: any CoreVersionLoading
    let coreVersionReader: any CoreVersionReading
    let emptyRepositoryOpener: any CoreEmptyRepositoryOpening
    let localModelStatusReader: any CoreLocalModelStatusReading
    let overviewRegenerator: any CoreOverviewRegenerating
    let overviewRegenerationCoordinator: OverviewRegenerationCoordinator
    let platformCapabilityLoader: any CorePlatformCapabilitiesLoading
    let scanSessionReader: any CoreScanSessionReading

    // Settings owns the feature contract; the App composition root supplies
    // platform effects explicitly so panes never resolve live adapters.
    let appVersionReader: any AppVersionReading
    let classifierFileOpener: any RepositoryFileOpening
    let classifierFileRevealer: any RepositoryFileRevealing
    let classifierFinderOpener: any RepositoryFinderOpening
    let classifierAccessibilityAnnouncer: any AccessibilityAnnouncing
    let existingRepositoryMetadataReader: any ExistingRepositoryMetadataReading
    let metadataPresenceChecker: any RepoMetadataPresenceChecking
    let finderOpener: any RepositoryFinderOpening
    let pathCopier: any RepositoryPathCopying
    let generatedOverviewRevealer: any RepositoryFileRevealing
    let accessibilityAnnouncer: any AccessibilityAnnouncing
    let rootOverviewInspector: any RootOverviewFileInspecting
    let rootOverviewRevealer: any RepositoryFileRevealing
    let ignoreRulesManager: any RepositoryIgnoreRulesManaging
    let iCloudStatusDetector: any ICloudStatusDetecting
    let iCloudHelpOpener: any ICloudHelpOpening
    let aboutExternalLinkOpener: any AboutExternalLinkOpening
    let aboutStringCopier: any AboutStringCopying
    let diagnosticSummaryCopier: any AdvancedSettingsDiagnosticSummaryCopying
}

struct SyncConflictsFeatureDependencies {
    let iCloudConflictLister: any CoreICloudConflictListing
    let iCloudConflictReviewer: any CoreICloudConflictReviewing
    let repositoryPathValidator: any CoreRepositoryPathValidating
    let repositoryFinderOpener: any RepositoryFinderOpening
    let fileRevealer: any RepositoryFileRevealing
    let systemCapabilityChecker: any OnboardingSystemCapabilityChecking
    let syncConflictDetector: any CoreSyncConflictDetecting
    let conflictResolver: any CoreSyncConflictResolving
}

struct DiagnosticsFeatureDependencies {
    let runtime: @MainActor () -> ObservabilityRuntimeAssembly
    let packagePreviewer: any DiagnosticsPackagePreviewing
    let packageHandler: any DiagnosticsPackageHandling
}
