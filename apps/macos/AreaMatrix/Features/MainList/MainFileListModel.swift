import AreaMatrixCoreBridgeContract
import AreaMatrixFeatureIngestion
import AreaMatrixFeatureLibrary
import Combine
import Foundation

@MainActor
final class MainFileListModel: ObservableObject {
    @Published var files: [FileEntrySnapshot]
    @Published var loadingState = MainListLoadingState()
    @Published var loadMoreErrorMapping: CoreErrorMappingSnapshot?
    @Published var errorMapping: CoreErrorMappingSnapshot?
    @Published var selection = MainFileSelectionState.none {
        didSet {
            detailTagModel.clearStaleDetailTagUndoToast()
            detailTagModel.clearStaleDetailTagSuggestions()
            let selectedBatchFileIDs = selection.multipleFileIDs
            if selectedBatchFileIDs.isEmpty || aiTagBatchSuggestionState.fileIDs != selectedBatchFileIDs {
                aiTagBatchSuggestionState = .idle
            }
        }
    }

    @Published var selectedFileDetail: FileEntrySnapshot?
    @Published var isDetailLoading = false
    @Published var detailErrorMapping: CoreErrorMappingSnapshot?
    @Published var missingFileRelinkState = MainMissingFileRelinkState.idle
    @Published var detailLogState = MainDetailLogState.notLoaded
    @Published var detailLogDiagnosticsState = MainDetailLogDiagnosticsState.idle
    @Published var detailExternalCreateSyncState = MainDetailExternalCreateSyncState.idle
    @Published private(set) var externalSyncAttemptRevision: UInt64 = 0
    @Published private(set) var externalSyncErrorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var isExternalSyncPlaceholderDownloading = false
    @Published private(set) var externalSyncRecoveryMessage: LocalizedMessage?
    @Published private(set) var pendingExternalSelectionUpdate: MainExternalSelectionUpdate?
    @Published var aiTagBatchSuggestionState = AITagBatchSuggestionState.idle
    @Published var selectedFileNoteWriteBlock: MainDetailNoteWriteBlock?
    @Published var detailTabRequest: MainDetailTabRequest?
    @Published var statusBanner: MainListStatusBanner?

    let repositorySession: RepositorySession
    let currentListDiagnostics: MainListDiagnosticsModel
    let searchModel: SearchModel
    let detailTagModel: DetailTagModel
    let syncConflictCoordinator: SyncConflictCoordinator
    let fileActionCoordinator: FileActionCoordinator

    var operationContext: RepositoryOperationContext {
        repositorySession.makeOperationContext()
    }

    var repoPath: String {
        operationContext.repoPath
    }

    var isReadOnly: Bool {
        operationContext.access.isReadOnly
    }

    var writeLockedFileIDs: Set<Int64> {
        operationContext.access.writeLockedFileIDs
    }

    let fileResourceAccess: any ImportFileResourceAccessing
    let fileLister: any CoreFileListing
    let fileDetailer: any CoreFileDetailing
    let missingFileRecoverer: any CoreMissingFileRecovering
    let missingFilePicker: any RepositoryMissingFilePicking
    let batchDeleter: any CoreBatchDeleting
    let batchCategoryChanger: any CoreBatchCategoryChanging
    let tagStore: any CoreTagCRUD
    let aiSettingsLoader: any CoreAISettingsLoading
    let aiTagSuggestionStore: any CoreAITagSuggestionManaging
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let undoActionStore: any CoreUndoActionLogging
    let redoActionStore: any CoreRedoActionLogging
    let changeLogLister: any CoreChangeLogListing
    let externalChangesSyncer: any CoreExternalChangesSyncing
    let repositoryWriteCoordinator: RepositoryWriteCoordinator
    let errorMapper: any CoreErrorMapping
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    var currentCategory: String?
    var loadGeneration = 0
    var currentListDiagnosticsObservation: AnyCancellable?
    var fileActionCoordinatorObservation: AnyCancellable?
    var detailTagModelObservation: AnyCancellable?
    var detailGeneration = 0
    var detailLogGeneration = 0
    var tagSuggestionPresentationSequence = 0
    var externalSyncDrainTask: Task<Void, Never>?
    var failedExternalSyncWindowID: String?
    var failedExternalSyncRelativePath: String?
    var isLoading: Bool {
        get { loadingState.isLoading }
        set { loadingState.isLoading = newValue }
    }

    var hasMore: Bool {
        get { loadingState.hasMore }
        set { loadingState.hasMore = newValue }
    }

    var isLoadingMore: Bool {
        get { loadingState.isLoadingMore }
        set { loadingState.isLoadingMore = newValue }
    }

    var nextFilePageOffset: Int64 {
        get { loadingState.nextOffset }
        set { loadingState.nextOffset = newValue }
    }

    init(
        session: RepositorySession,
        opening: RepositoryOpeningResult,
        dependencies: MainListFeatureDependencies
    ) {
        repositorySession = session
        let ownedModels = MainFileListOwnedModels(repoPath: session.repoPath, dependencies: dependencies)
        currentListDiagnostics = ownedModels.diagnostics
        searchModel = ownedModels.search
        detailTagModel = ownedModels.detailTag
        syncConflictCoordinator = ownedModels.syncConflict
        fileActionCoordinator = ownedModels.fileAction
        fileResourceAccess = dependencies.fileResourceAccess
        files = opening.currentCategoryFiles
        let pagination = MainListPagination(initialCount: opening.currentCategoryFiles.count)
        loadingState = MainListLoadingState(
            hasMore: pagination.hasMore,
            nextOffset: pagination.nextOffset
        )
        errorMapping = opening.currentCategoryListError
        fileLister = dependencies.fileLister
        fileDetailer = dependencies.fileDetailer
        missingFileRecoverer = dependencies.missingFileRecoverer
        missingFilePicker = dependencies.missingFilePicker
        batchDeleter = dependencies.batchDeleter
        batchCategoryChanger = dependencies.batchCategoryChanger
        tagStore = dependencies.tagStore
        aiSettingsLoader = dependencies.aiSettingsLoader
        aiTagSuggestionStore = dependencies.aiTagSuggestionStore
        aiPrivacyRules = dependencies.aiPrivacyRules
        undoActionStore = dependencies.undoActionStore
        redoActionStore = dependencies.redoActionStore
        changeLogLister = dependencies.changeLogLister
        externalChangesSyncer = dependencies.externalChangesSyncer
        repositoryWriteCoordinator = dependencies.repositoryWriteCoordinator
        errorMapper = dependencies.errorMapper
        diagnosticsCollector = dependencies.diagnosticsCollector
        configureOwnedModels()
    }

    private func configureOwnedModels() {
        currentListDiagnosticsObservation = currentListDiagnostics.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        fileActionCoordinatorObservation = fileActionCoordinator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        detailTagModelObservation = detailTagModel.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        detailTagModel.setContext(.init(
            selectedFileID: { [weak self] in self?.selection.singleFileID },
            selectedFile: { [weak self] fileID in
                self?.selectedFileDetail.flatMap { $0.id == fileID ? $0 : nil } ?? self?.cachedFile(id: fileID)
            },
            writeDisabledMessage: { [weak self] message in
                guard let self else { return message }
                return selectedWriteActionDisabledMessage(noSelectionMessage: message)
            },
            writableFileID: { [weak self] fileID in self?.writableActionFileID(fileID) },
            loadChangeLog: { [weak self] fileID in await self?.loadChangeLog(fileID: fileID) },
            requestDetailTab: { [weak self] tab in self?.detailTabRequest = .automatic(tab) }
        ))
        searchModel.setResultHandler { [weak self] result in
            self?.applySearchResult(result)
        }
    }

    convenience init(
        opening: RepositoryOpeningResult,
        dependencies: MainListFeatureDependencies
    ) {
        self.init(session: opening.makeRepositorySession(), opening: opening, dependencies: dependencies)
    }
}

extension MainFileListModel {
    func noteWriteBlock(for file: FileEntrySnapshot) -> MainDetailNoteWriteBlock? {
        if isReadOnly { return .repoReadOnly }
        if file.availability == .missing { return .fileMissing }
        if writeLockedFileIDs.contains(file.id) { return .importLocked }
        if isLoading { return .listLoading }
        return nil
    }

    var loadingStatusText: String? {
        guard isLoading else { return nil }
        if searchModel.searchState.isActive { return L10n.string("Searching...") }
        return L10n.format("detail.log.loadingCategory", currentCategoryDisplayName)
    }

    var loadingAccessibilityText: String? {
        guard let loadingStatusText else { return nil }
        return L10n.format("detail.log.loadingFilesStatus", loadingStatusText)
    }

    func canApplyDetailLogDiagnosticsResult(fileID: Int64) -> Bool {
        guard selection.singleFileID == fileID,
              case let .failed(failedFileID, _) = detailLogState else { return false }
        return failedFileID == fileID
    }

    func canApplyMultiSelectionDetailResult(generation: Int, ids: Set<Int64>) -> Bool {
        generation == detailGeneration && selection.multipleFileIDs == ids
    }

    var hasRetryableExternalSyncFailure: Bool {
        failedExternalSyncWindowID != nil
    }

    var canDownloadExternalSyncPlaceholder: Bool {
        externalSyncErrorMapping?.kind == .iCloudPlaceholder && failedExternalSyncRelativePath != nil
    }

    func retryExternalSync() {
        guard hasRetryableExternalSyncFailure,
              externalSyncDrainTask == nil,
              !isExternalSyncPlaceholderDownloading else { return }
        externalSyncRecoveryMessage = nil
        externalSyncAttemptRevision &+= 1
    }

    func consumeExternalSelectionUpdate(_ update: MainExternalSelectionUpdate) {
        if pendingExternalSelectionUpdate == update { pendingExternalSelectionUpdate = nil }
    }

    func setExternalSyncErrorMapping(_ mapping: CoreErrorMappingSnapshot?) {
        externalSyncErrorMapping = mapping
    }

    func clearExternalSyncRecoveryMessage() {
        externalSyncRecoveryMessage = nil
    }

    func downloadExternalSyncPlaceholder(
        using download: @escaping (String) async throws -> Void
    ) async {
        guard externalSyncErrorMapping?.kind == .iCloudPlaceholder,
              let relativePath = failedExternalSyncRelativePath,
              !isExternalSyncPlaceholderDownloading,
              externalSyncDrainTask == nil else { return }

        isExternalSyncPlaceholderDownloading = true
        externalSyncRecoveryMessage = nil
        do {
            try await download(relativePath)
            isExternalSyncPlaceholderDownloading = false
            retryExternalSync()
        } catch {
            isExternalSyncPlaceholderDownloading = false
            externalSyncRecoveryMessage = L10n.message(
                "mainList.externalSync.iCloudDownloadStartError",
                arguments: [.string(error.localizedDescription)],
                technicalDetail: error.localizedDescription
            )
        }
    }

    func setPendingExternalSelectionUpdate(_ update: MainExternalSelectionUpdate) {
        pendingExternalSelectionUpdate = update
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
}
