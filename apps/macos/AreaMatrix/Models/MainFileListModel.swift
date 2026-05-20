import Combine
import Foundation

@MainActor
final class MainFileListModel: ObservableObject {
    @Published var files: [FileEntrySnapshot]
    @Published var isLoading = false
    @Published var errorMapping: CoreErrorMappingSnapshot?
    @Published var selection: MainFileSelectionState = .none
    @Published var selectedFileDetail: FileEntrySnapshot?
    @Published var isDetailLoading = false
    @Published var detailErrorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var detailLogState: MainDetailLogState = .notLoaded
    @Published private(set) var detailLogDiagnosticsState: MainDetailLogDiagnosticsState = .idle
    @Published private(set) var detailExternalCreateSyncState: MainDetailExternalCreateSyncState = .idle
    @Published var searchState: MainSearchState = .idle
    @Published var searchFacetsState: MainSearchFacetsState = .idle
    @Published var selectedFileNoteWriteBlock: MainDetailNoteWriteBlock?
    @Published var detailTabRequest: MainDetailTabRequest?
    @Published var pendingActionDestination: MainFileActionDestination?
    @Published var statusBanner: MainListStatusBanner?
    @Published var diagnosticsState: MainListDiagnosticsState = .idle
    @Published var renameState: MainFileRenameState = .idle
    @Published var deleteState: MainFileDeleteState = .idle
    @Published var changeCategoryState: MainFileCategoryMoveState = .idle
    @Published var iCloudConflictResolutionState: ICloudConflictResolutionState = .idle
    @Published var pendingSearchDestination: MainSearchDestination?
    @Published var lastSearchExitContext: MainSearchExitContext?
    @Published var smartListFilterDraft: SmartListFilterDraft?
    var activeSmartListSearch: SavedSearchSnapshot?

    let repoPath: String
    let isReadOnly: Bool
    let writeLockedFileIDs: Set<Int64>
    private let fileLister: any CoreFileListing
    let fileDetailer: any CoreFileDetailing
    let fileRenamer: any CoreFileRenaming
    let fileDeleter: any CoreFileDeleting
    let fileCategoryMover: any CoreFileCategoryMoving
    let iCloudConflictResolver: any ICloudConflictResolving
    private let changeLogLister: any CoreChangeLogListing
    private let externalChangesSyncer: any CoreExternalChangesSyncing
    let errorMapper: any CoreErrorMapping
    let searchQuerying: any CoreSearchQuerying
    let searchFiltering: any CoreSearchFiltering
    let diagnosticsCollector: any CoreDiagnosticsCollecting
    var currentCategory: String?
    private var loadGeneration = 0
    private var detailGeneration = 0
    private var detailLogGeneration = 0
    var searchGeneration = 0
    var searchFacetsGeneration = 0

    init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
        searchQuerying: any CoreSearchQuerying = CoreBridge(),
        searchFiltering: any CoreSearchFiltering = CoreBridge(),
        fileRenamer: any CoreFileRenaming = CoreBridge(),
        fileDeleter: any CoreFileDeleting = CoreBridge(),
        fileCategoryMover: any CoreFileCategoryMoving = CoreBridge(),
        iCloudConflictResolver: any ICloudConflictResolving = CoreBridge(),
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
        self.fileRenamer = fileRenamer
        self.fileDeleter = fileDeleter
        self.fileCategoryMover = fileCategoryMover
        self.iCloudConflictResolver = iCloudConflictResolver
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
        if ids.isEmpty {
            clearDetail()
            return
        }

        guard ids.count == 1, let id = ids.first else {
            selection = .multiple(ids)
            selectedFileDetail = nil
            selectedFileNoteWriteBlock = nil
            detailErrorMapping = nil
            isDetailLoading = true
            resetDetailLog()
            await loadMultiSelectionDetails(ids: ids)
            return
        }

        await selectFile(id: id)
    }

    func selectFile(id: Int64?) async {
        guard let id else {
            clearDetail()
            return
        }

        selection = .single(id)
        selectedFileDetail = cachedFile(id: id)
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

    func loadSelectedFileChangeLog() async {
        guard let selectedFileID = selection.singleFileID else { return }
        await loadChangeLog(fileID: selectedFileID)
    }

    func retrySelectedFileChangeLog() async {
        guard let selectedFileID = selection.singleFileID else { return }
        await loadChangeLog(fileID: selectedFileID)
    }

    func consumeDetailTabRequest(_ request: MainDetailTabRequest) {
        guard detailTabRequest == request else { return }
        detailTabRequest = nil
    }

    func syncExternalCreated(_ event: MainExternalCreatedFileEvent) async {
        detailExternalCreateSyncState = .syncing(event: event)
        do {
            let result = try await syncExternalChange(event)
            try validateExternalSyncResult(result, event: event)
            let fileID = try await refreshAfterExternalSync(event, result: result)
            detailExternalCreateSyncState = .synced(event: event, fileID: fileID, result)
            if let fileID {
                await loadChangeLog(fileID: fileID)
                if case let .loaded(loadedFileID, _) = detailLogState, loadedFileID == fileID {
                    detailTabRequest = .automatic(.log)
                }
            }
        } catch {
            let mappedError = await mapCoreError(error)
            detailExternalCreateSyncState = .failed(event: event, mappedError)
        }
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

    var loadingStatusText: String? {
        guard isLoading else { return nil }
        if searchState.isActive { return "Searching..." }
        return "正在加载 \(currentCategoryDisplayName)..."
    }

    var loadingAccessibilityText: String? {
        guard let loadingStatusText else { return nil }
        return "Loading files. \(loadingStatusText)"
    }

    private func reloadCurrentCategory(focusingOn fileID: Int64? = nil) async {
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

    private func loadDetail(id: Int64) async {
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

    func loadChangeLog(fileID: Int64) async {
        detailLogGeneration += 1
        let generation = detailLogGeneration

        detailLogState = .loading(fileID: fileID)
        detailLogDiagnosticsState = .idle
        do {
            let entries = try await changeLogLister.listChanges(
                repoPath: repoPath,
                filter: .detailLog(fileID: fileID)
            )
            guard generation == detailLogGeneration, selection.singleFileID == fileID else { return }
            detailLogState = .loaded(fileID: fileID, entries: entries)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailLogGeneration, selection.singleFileID == fileID else { return }
            detailLogState = .failed(fileID: fileID, mappedError)
        }
    }

    private func syncExternalChange(_ event: MainExternalCreatedFileEvent) async throws -> SyncResultSnapshot {
        switch event.kind {
        case .created:
            try await externalChangesSyncer.syncExternalCreated(
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID
            )
        case .renamed:
            try await externalChangesSyncer.syncExternalRenamed(
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID
            )
        case .removed:
            try await externalChangesSyncer.syncExternalRemoved(
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID
            )
        }
    }

    private func refreshAfterExternalSync(
        _ event: MainExternalCreatedFileEvent,
        result: SyncResultSnapshot
    ) async throws -> Int64? {
        if event.kind == .removed {
            return try await refreshAfterExternalRemovedSync(event, result: result)
        }

        let loadedFiles = try await reloadFilesForExternalSync()
        guard let file = loadedFiles.first(where: { $0.path == event.relativePath }) else {
            throw CoreError.Internal(
                message: "\(event.kind.displayName) file was not visible after sync: \(event.relativePath)"
            )
        }

        selection = .single(file.id)
        selectedFileDetail = file
        selectedFileNoteWriteBlock = noteWriteBlock(for: file)
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: file.id)
        guard selectedFileDetail?.id == file.id, detailErrorMapping == nil else {
            throw CoreError.Internal(
                message: "\(event.kind.displayName) file detail was not visible after sync: \(event.relativePath)"
            )
        }
        if event.kind == .renamed { statusBanner = .renamedPreservedSelection(fileID: file.id) }
        return file.id
    }

    private func refreshAfterExternalRemovedSync(
        _ event: MainExternalCreatedFileEvent,
        result: SyncResultSnapshot
    ) async throws -> Int64? {
        let removedFileID = selectedFileIDForExternalRemoval(path: event.relativePath)
        let removedSnapshot = removedFileID.flatMap { missingSnapshot(fileID: $0, fallbackPath: event.relativePath) }
        let loadedFiles = try await reloadFilesForExternalSync()
        if removedFileID == nil {
            return nil
        }
        guard result.detectedDeletes > 0 else {
            throw CoreError.Internal(
                message: "removed event \(event.fsEventID) did not report a detected delete: \(event.relativePath)"
            )
        }
        guard let removedFileID else { return nil }

        files = loadedFiles.filter { $0.id != removedFileID }
        selection = .single(removedFileID)
        selectedFileDetail = removedSnapshot
        selectedFileNoteWriteBlock = removedSnapshot.flatMap { noteWriteBlock(for: $0) }
        detailErrorMapping = CoreErrorMappingSnapshot.missingFromExternalChange(fileID: removedFileID)
        isDetailLoading = false
        statusBanner = .removedSelectedFile(fileID: removedFileID)
        return removedFileID
    }

    private func reloadFilesForExternalSync() async throws -> [FileEntrySnapshot] {
        isLoading = true
        do {
            let loadedFiles = try await fileLister.listFiles(
                repoPath: repoPath,
                filter: .currentCategory(currentCategory)
            )
            files = loadedFiles
            errorMapping = nil
            isLoading = false
            return loadedFiles
        } catch {
            errorMapping = await mapCoreError(error)
            isLoading = false
            throw error
        }
    }

    func clearDetail() {
        detailGeneration += 1
        selection = .none
        selectedFileDetail = nil; selectedFileNoteWriteBlock = nil; detailErrorMapping = nil
        isDetailLoading = false
        resetDetailLog()
        pendingActionDestination = nil; renameState = .idle; deleteState = .idle; changeCategoryState = .idle
    }

    private func resetDetailLog() {
        detailLogGeneration += 1
        detailLogState = .notLoaded
        detailLogDiagnosticsState = .idle
        detailExternalCreateSyncState = .idle
        detailTabRequest = nil
        iCloudConflictResolutionState = .idle
    }

    private func canApplyDetailLogDiagnosticsResult(fileID: Int64) -> Bool {
        guard selection.singleFileID == fileID,
              case let .failed(failedFileID, _) = detailLogState else { return false }
        return failedFileID == fileID
    }

    private func canApplyMultiSelectionDetailResult(generation: Int, ids: Set<Int64>) -> Bool {
        generation == detailGeneration && selection.multipleFileIDs == ids
    }
}
