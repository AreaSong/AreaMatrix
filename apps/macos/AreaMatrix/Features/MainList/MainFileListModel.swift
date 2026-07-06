import Combine
import Foundation

@MainActor
final class MainFileListModel: ObservableObject {
    @Published var files: [FileEntrySnapshot]
    @Published var isLoading = false
    @Published var errorMapping: CoreErrorMappingSnapshot?
    @Published var selection = MainFileSelectionState.none {
        didSet {
            clearStaleDetailTagUndoToast()
            clearStaleDetailTagSuggestions()
        }
    }

    @Published var selectedFileDetail: FileEntrySnapshot?
    @Published var isDetailLoading = false
    @Published var detailErrorMapping: CoreErrorMappingSnapshot?
    @Published var detailLogState = MainDetailLogState.notLoaded
    @Published var detailLogDiagnosticsState = MainDetailLogDiagnosticsState.idle
    @Published var detailExternalCreateSyncState = MainDetailExternalCreateSyncState.idle
    @Published var detailTagEditorState = DetailTagEditorState.notLoaded
    @Published var detailTagSuggestionState = DetailTagSuggestionState.idle
    @Published var aiTagSuggestionState = AITagSuggestionState.idle
    @Published var aiTagBatchSuggestionState = AITagBatchSuggestionState.idle
    @Published var tagSuggestionPresentationRequest: TagSuggestionPresentationRequest?
    @Published var detailTagUndoToast: DetailTagUndoToast?
    @Published var searchState = MainSearchState.idle {
        didSet {
            if !semanticPrivacyGateState.isCurrent(for: searchState.request) {
                semanticPrivacyGateState = .idle
            }
            if !semanticFallbackState.isCurrent(for: searchState.request) { semanticFallbackState = .idle }
            if !semanticIndexControlState.isCurrent(for: searchState.request) { semanticIndexControlState = .idle }
        }
    }

    @Published var semanticIndexBuildState = SemanticIndexBuildState.idle
    @Published var semanticPrivacyGateState = SemanticPrivacyGateState.idle
    @Published var semanticFallbackState = SemanticFallbackState.idle
    @Published var semanticIndexControlState = SemanticIndexBuildControlState.idle
    @Published var semanticPagingState = SemanticSearchPagingState.idle
    @Published var showFoldedSemanticDuplicates = false
    @Published var searchFacetsState = MainSearchFacetsState.idle
    @Published var tagFilterRegistryState = TagFilterRegistryState.idle
    @Published var selectedFileNoteWriteBlock: MainDetailNoteWriteBlock?
    @Published var detailTabRequest: MainDetailTabRequest?
    @Published var pendingActionDestination: MainFileActionDestination?
    @Published var statusBanner: MainListStatusBanner?
    @Published var diagnosticsState = MainListDiagnosticsState.idle
    @Published var renameState = MainFileRenameState.idle
    @Published var deleteState = MainFileDeleteState.idle
    @Published var changeCategoryState = MainFileCategoryMoveState.idle
    @Published var classifierCorrectionContextState = ClassifierCorrectionContextState.idle
    @Published var classifierCorrectionResult: ClassifierCorrectionResultSnapshot?
    @Published var iCloudConflictResolutionState = ICloudConflictResolutionState.idle
    @Published var pendingSearchDestination: MainSearchDestination?
    @Published var commandPaletteState = CommandPaletteLoadState.idle
    @Published var commandPaletteQuery = ""
    @Published var lastSearchExitContext: MainSearchExitContext?
    @Published var smartListFilterDraft: SmartListFilterDraft?
    var activeSmartListSearch: SavedSearchSnapshot?

    let repoPath: String
    let isReadOnly: Bool
    let writeLockedFileIDs: Set<Int64>
    let fileLister: any CoreFileListing
    let fileDetailer: any CoreFileDetailing
    let fileRenamer: any CoreFileRenaming
    let fileDeleter: any CoreFileDeleting
    let fileCategoryMover: any CoreFileCategoryMoving
    let categoryPredictor: any CoreCategoryPredicting
    let batchDeleter: any CoreBatchDeleting
    let batchCategoryChanger: any CoreBatchCategoryChanging
    let iCloudConflictResolver: any ICloudConflictResolving
    let tagStore: any CoreTagCRUD
    let aiSettingsLoader: any CoreAISettingsLoading
    let aiTagSuggestionStore: any CoreAITagSuggestionManaging
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let undoActionStore: any CoreUndoActionLogging
    let redoActionStore: any CoreRedoActionLogging
    let changeLogLister: any CoreChangeLogListing
    let externalChangesSyncer: any CoreExternalChangesSyncing
    let errorMapper: any CoreErrorMapping
    let searchQuerying: any CoreSearchQuerying
    let semanticSearching: any CoreSemanticSearching
    let semanticFallbackReader: any CoreSemanticFallbackStatusReading
    let searchFiltering: any CoreSearchFiltering
    let commandIndexer: any CoreCommandIndexing
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    var currentCategory: String?
    var loadGeneration = 0
    var detailGeneration = 0
    var detailLogGeneration = 0
    var tagSuggestionPresentationSequence = 0
    var tagFilterRegistryGeneration = 0
    var searchGeneration = 0
    var searchFacetsGeneration = 0
    var semanticIndexBuildGeneration = 0
    var semanticIndexBuildTask: Task<SemanticIndexBuildReportSnapshot, Error>?

    init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
        searchQuerying: any CoreSearchQuerying = AppCoreServices.searchQuerying,
        semanticSearching: any CoreSemanticSearching = AppCoreServices.semanticSearching,
        semanticFallbackReader: any CoreSemanticFallbackStatusReading = AppCoreServices.semanticFallbackReader,
        searchFiltering: any CoreSearchFiltering = AppCoreServices.searchFiltering,
        commandIndexer: any CoreCommandIndexing = AppCoreServices.commandIndexer,
        fileRenamer: any CoreFileRenaming = AppCoreServices.fileRenamer,
        fileDeleter: any CoreFileDeleting = AppCoreServices.fileDeleter,
        fileCategoryMover: any CoreFileCategoryMoving = AppCoreServices.fileCategoryMover,
        categoryPredictor: any CoreCategoryPredicting = AppCoreServices.categoryPredictor,
        batchDeleter: any CoreBatchDeleting = AppCoreServices.batchDeleter,
        batchCategoryChanger: any CoreBatchCategoryChanging = AppCoreServices.batchCategoryChanger,
        iCloudConflictResolver: any ICloudConflictResolving = AppCoreServices.iCloudConflictResolver,
        tagStore: any CoreTagCRUD = AppCoreServices.tagStore,
        aiSettingsLoader: any CoreAISettingsLoading = AppCoreServices.aiSettingsLoader,
        aiTagSuggestionStore: any CoreAITagSuggestionManaging = AppCoreServices.aiTagSuggestionStore,
        aiPrivacyRules: any CoreAIPrivacyEvaluating = AppCoreServices.aiPrivacyRules,
        undoActionStore: any CoreUndoActionLogging = AppCoreServices.undoActionStore,
        redoActionStore: any CoreRedoActionLogging = AppCoreServices.redoActionStore,
        changeLogLister: any CoreChangeLogListing = AppCoreServices.changeLogLister,
        externalChangesSyncer: any CoreExternalChangesSyncing = AppCoreServices.externalChangesSyncer,
        errorMapper: any CoreErrorMapping,
        diagnosticsCollector: any CoreDiagnosticsCollecting = AppCoreServices.diagnosticsCollector
    ) {
        repoPath = opening.config.repoPath
        isReadOnly = opening.isReadOnly
        writeLockedFileIDs = opening.writeLockedFileIDs
        files = opening.currentCategoryFiles
        errorMapping = opening.currentCategoryListError
        self.fileLister = fileLister
        self.fileDetailer = fileDetailer
        self.searchQuerying = searchQuerying
        self.semanticSearching = semanticSearching
        self.semanticFallbackReader = semanticFallbackReader
        self.searchFiltering = searchFiltering
        self.commandIndexer = commandIndexer
        self.fileRenamer = fileRenamer
        self.fileDeleter = fileDeleter
        self.fileCategoryMover = fileCategoryMover
        self.categoryPredictor = categoryPredictor
        self.batchDeleter = batchDeleter
        self.batchCategoryChanger = batchCategoryChanger
        self.iCloudConflictResolver = iCloudConflictResolver
        self.tagStore = tagStore
        self.aiSettingsLoader = aiSettingsLoader
        self.aiTagSuggestionStore = aiTagSuggestionStore
        self.aiPrivacyRules = aiPrivacyRules
        self.undoActionStore = undoActionStore
        self.redoActionStore = redoActionStore
        self.changeLogLister = changeLogLister
        self.externalChangesSyncer = externalChangesSyncer
        self.errorMapper = errorMapper
        self.diagnosticsCollector = diagnosticsCollector
    }
}

extension MainFileListModel {
    func requestDetailLogDiagnosticsPrivacyConfirmation() {
        guard case let .failed(fileID, _) = detailLogState,
              selection.singleFileID == fileID else { return }
        detailLogDiagnosticsState = .confirmingPrivacy(fileID: fileID)
    }

    func cancelDetailLogDiagnosticsPrivacyConfirmation() {
        guard case .confirmingPrivacy = detailLogDiagnosticsState else { return }
        detailLogDiagnosticsState = .idle
    }

    func collectDetailLogDiagnostics() async {
        guard case let .confirmingPrivacy(fileID) = detailLogDiagnosticsState,
              selection.singleFileID == fileID else { return }

        detailLogDiagnosticsState = .collecting(fileID: fileID)
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            guard canApplyDetailLogDiagnosticsResult(fileID: fileID) else { return }
            detailLogDiagnosticsState = .collected(fileID: fileID, snapshot)
        } catch {
            let mappedError = await mapCoreError(error)
            guard canApplyDetailLogDiagnosticsResult(fileID: fileID) else { return }
            detailLogDiagnosticsState = .failed(fileID: fileID, mappedError)
        }
    }

    func handleExternalRename(_ updatedFile: FileEntrySnapshot) {
        files = files.map { file in
            file.id == updatedFile.id ? updatedFile : file
        }
        if selection.singleFileID == updatedFile.id {
            selectedFileDetail = updatedFile
            selectedFileNoteWriteBlock = noteWriteBlock(for: updatedFile)
            statusBanner = .renamedPreservedSelection(fileID: updatedFile.id)
        }
    }

    func handleExternalRemoval(fileID: Int64) {
        let removedSnapshot = missingSnapshot(fileID: fileID, fallbackPath: "\(fileID)")
        files.removeAll { $0.id == fileID }
        guard selection.singleFileID == fileID || selectedFileDetail?.id == fileID else { return }

        selection = .single(fileID)
        selectedFileDetail = removedSnapshot
        selectedFileNoteWriteBlock = removedSnapshot.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = CoreErrorMappingSnapshot.missingFromExternalChange(fileID: fileID)
        isDetailLoading = false
        statusBanner = .removedSelectedFile(fileID: fileID)
    }
}
