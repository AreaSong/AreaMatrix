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
    @Published var searchState = MainSearchState.idle
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
    let aiTagSuggestionStore: any CoreAITagSuggestionManaging
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let undoActionStore: any CoreUndoActionLogging
    let redoActionStore: any CoreRedoActionLogging
    let changeLogLister: any CoreChangeLogListing
    let externalChangesSyncer: any CoreExternalChangesSyncing
    let errorMapper: any CoreErrorMapping
    let searchQuerying: any CoreSearchQuerying
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

    init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
        searchQuerying: any CoreSearchQuerying = CoreBridge(),
        searchFiltering: any CoreSearchFiltering = CoreBridge(),
        commandIndexer: any CoreCommandIndexing = CoreBridge(),
        fileRenamer: any CoreFileRenaming = CoreBridge(),
        fileDeleter: any CoreFileDeleting = CoreBridge(),
        fileCategoryMover: any CoreFileCategoryMoving = CoreBridge(),
        categoryPredictor: any CoreCategoryPredicting = CoreBridge(),
        batchDeleter: any CoreBatchDeleting = CoreBridge(),
        batchCategoryChanger: any CoreBatchCategoryChanging = CoreBridge(),
        iCloudConflictResolver: any ICloudConflictResolving = CoreBridge(),
        tagStore: any CoreTagCRUD = CoreBridge(),
        aiTagSuggestionStore: any CoreAITagSuggestionManaging = CoreBridge(),
        aiPrivacyRules: any CoreAIPrivacyEvaluating = CoreBridge(),
        undoActionStore: any CoreUndoActionLogging = CoreBridge(),
        redoActionStore: any CoreRedoActionLogging = CoreBridge(),
        changeLogLister: any CoreChangeLogListing = CoreBridge(),
        externalChangesSyncer: any CoreExternalChangesSyncing = CoreBridge(),
        errorMapper: any CoreErrorMapping,
        diagnosticsCollector: any CoreDiagnosticsCollecting = CoreBridge()
    ) {
        repoPath = opening.config.repoPath
        isReadOnly = opening.isReadOnly
        writeLockedFileIDs = opening.writeLockedFileIDs
        files = opening.currentCategoryFiles
        errorMapping = opening.currentCategoryListError
        self.fileLister = fileLister
        self.fileDetailer = fileDetailer
        self.searchQuerying = searchQuerying
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
    func loadCurrentCategory(_ category: String?, focusingOn fileID: Int64? = nil) async {
        currentCategory = category
        await reloadCurrentCategory(focusingOn: fileID)
    }

    func retryCurrentCategory() async {
        await reloadCurrentCategory()
    }

    func selectFiles(_ ids: Set<Int64>) async {
        if ids.isEmpty { clearDetail(); return }

        guard ids.count == 1, let id = ids.first else {
            selection = .multiple(ids)
            selectedFileDetail = nil; selectedFileNoteWriteBlock = nil; detailErrorMapping = nil
            detailTagEditorState = .notLoaded
            detailTagSuggestionState = .idle
            isDetailLoading = true
            resetDetailLog()
            await loadMultiSelectionDetails(ids: ids)
            return
        }

        await selectFile(id: id)
    }

    func selectFile(id: Int64?) async {
        guard let id else { clearDetail(); return }

        selection = .single(id); selectedFileDetail = cachedFile(id: id)
        selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = nil
        isDetailLoading = true
        resetDetailLog()
        await loadDetail(id: id)
    }

    func retrySelectedFileDetail() async {
        if selection.isMultiple {
            detailErrorMapping = nil
            isDetailLoading = true
            await loadMultiSelectionDetails(ids: selection.multipleFileIDs)
            return
        }

        guard let selectedFileID = selection.singleFileID else { return }

        selectedFileDetail = selectedFileDetail ?? cachedFile(id: selectedFileID)
        selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: selectedFileID)
    }

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

    func clearStatusBanner() {
        statusBanner = nil
    }

    func showUnsavedNoteDraftPreserved(fileID: Int64) {
        statusBanner = .unsavedNoteDraftPreserved(fileID: fileID)
    }

    func writeActionDisabledReason(fileID: Int64) -> MainFileWriteActionDisabledReason? {
        if isReadOnly { return .repoReadOnly }
        if isLoading { return .listLoading }
        if writeLockedFileIDs.contains(fileID) { return .importLocked }
        return nil
    }

    func beginAIClassificationSuggestion(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID,
              writeActionDisabledReason(fileID: fileID) == nil else { return }
        pendingActionDestination = .aiClassificationSuggestion(fileID: fileID)
    }

    func beginAIClassificationChange(fileID: Int64, targetCategory: String?) {
        guard writeActionDisabledReason(fileID: fileID) == nil else { return }
        changeCategoryState = .idle
        classifierCorrectionContextState = .idle
        classifierCorrectionResult = nil
        pendingActionDestination = .changeCategory(
            fileID: fileID,
            initialTargetCategory: targetCategory,
            mode: .classifierCorrection
        )
    }

    func reloadCurrentCategory(focusingOn fileID: Int64? = nil) async {
        loadGeneration += 1
        let generation = loadGeneration
        let filter = FileFilterSnapshot.currentCategory(currentCategory)

        isLoading = true
        errorMapping = nil
        diagnosticsState = .idle
        if fileID == nil {
            statusBanner = nil
            clearDetail()
        }

        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            files = loadedFiles
            errorMapping = nil
            isLoading = false
            focusLoadedFile(fileID: fileID)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == loadGeneration else { return }
            files = []
            errorMapping = mappedError
            statusBanner = nil
            isLoading = false
        }
    }

    private func focusLoadedFile(fileID: Int64?) {
        guard let fileID, let file = files.first(where: { $0.id == fileID }) else { return }
        selection = .single(file.id)
        selectedFileDetail = file
        selectedFileNoteWriteBlock = noteWriteBlock(for: file)
        detailErrorMapping = nil
        isDetailLoading = false
    }

    func loadDetail(id: Int64) async {
        detailGeneration += 1
        let generation = detailGeneration

        do {
            let loadedFile = try await fileDetailer.getFile(repoPath: repoPath, fileID: id)
            guard generation == detailGeneration else { return }
            selection = .single(loadedFile.id)
            selectedFileDetail = loadedFile
            selectedFileNoteWriteBlock = noteWriteBlock(for: loadedFile)
            files = files.map { $0.id == loadedFile.id ? loadedFile : $0 }
            detailErrorMapping = nil
            isDetailLoading = false
            detailTagEditorState = .notLoaded
            detailTagSuggestionState = .idle
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailGeneration else { return }
            selectedFileDetail = missingDetailSnapshotIfNeeded(error, fileID: id) ??
                selectedFileDetail ??
                cachedFile(id: id)
            selectedFileNoteWriteBlock = selectedFileDetail.flatMap { noteWriteBlock(for: $0) }
            detailErrorMapping = mappedError
            isDetailLoading = false
        }
    }

    private func loadMultiSelectionDetails(ids: Set<Int64>) async {
        detailGeneration += 1
        let generation = detailGeneration
        guard let result = await MultiSelectionDetailLoader.refresh(
            request: MultiSelectionDetailRefreshRequest(
                ids: ids,
                repoPath: repoPath,
                currentFiles: files,
                detailer: fileDetailer,
                errorMapper: errorMapper
            ),
            shouldContinue: { [weak self] in
                self?.canApplyMultiSelectionDetailResult(generation: generation, ids: ids) == true
            }
        ) else { return }

        guard canApplyMultiSelectionDetailResult(generation: generation, ids: ids) else { return }
        files = result.files
        selectedFileDetail = nil
        selectedFileNoteWriteBlock = nil
        detailErrorMapping = result.errorMapping
        isDetailLoading = false
    }

    func clearDetail() {
        detailGeneration += 1
        selection = .none
        selectedFileDetail = nil; selectedFileNoteWriteBlock = nil; detailErrorMapping = nil
        detailTagEditorState = .notLoaded
        detailTagSuggestionState = .idle
        clearTagFilterRegistry()
        isDetailLoading = false
        resetDetailLog()
        pendingActionDestination = nil; renameState = .idle; deleteState = .idle; changeCategoryState = .idle
    }

    func resetDetailLog() {
        detailLogGeneration += 1
        detailLogState = .notLoaded
        detailLogDiagnosticsState = .idle
        detailExternalCreateSyncState = .idle
        detailTabRequest = nil
        iCloudConflictResolutionState = .idle
    }
}
