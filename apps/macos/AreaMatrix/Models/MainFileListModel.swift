import Combine
import Foundation

@MainActor
final class MainFileListModel: ObservableObject {
    @Published private(set) var files: [FileEntrySnapshot]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var selection: MainFileSelectionState = .none
    @Published private(set) var selectedFileDetail: FileEntrySnapshot?
    @Published private(set) var isDetailLoading = false
    @Published private(set) var detailErrorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var detailLogState: MainDetailLogState = .notLoaded
    @Published private(set) var detailLogDiagnosticsState: MainDetailLogDiagnosticsState = .idle
    @Published private(set) var detailExternalCreateSyncState: MainDetailExternalCreateSyncState = .idle
    @Published private(set) var pendingActionDestination: MainFileActionDestination?
    @Published private(set) var statusBanner: MainListStatusBanner?
    @Published private(set) var diagnosticsState: MainListDiagnosticsState = .idle

    private let repoPath: String
    private let isReadOnly: Bool
    private let writeLockedFileIDs: Set<Int64>
    private let fileLister: any CoreFileListing
    private let fileDetailer: any CoreFileDetailing
    private let changeLogLister: any CoreChangeLogListing
    private let externalChangesSyncer: any CoreExternalChangesSyncing
    private let errorMapper: any CoreErrorMapping
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private var currentCategory: String?
    private var loadGeneration = 0
    private var detailGeneration = 0
    private var detailLogGeneration = 0

    init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
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
        self.changeLogLister = changeLogLister
        self.externalChangesSyncer = externalChangesSyncer
        self.errorMapper = errorMapper
        self.diagnosticsCollector = diagnosticsCollector
    }

    func loadCurrentCategory(_ category: String?) async {
        currentCategory = category
        await reloadCurrentCategory()
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
            detailErrorMapping = nil
            isDetailLoading = false
            resetDetailLog()
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
        detailErrorMapping = nil
        isDetailLoading = true
        resetDetailLog()
        await loadDetail(id: id)
    }

    func retrySelectedFileDetail() async {
        guard let selectedFileID = selection.singleFileID else { return }

        selectedFileDetail = selectedFileDetail ?? cachedFile(id: selectedFileID)
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

    func syncExternalCreated(_ event: MainExternalCreatedFileEvent) async {
        detailExternalCreateSyncState = .syncing(event: event)
        do {
            let result = try await externalChangesSyncer.syncExternalCreated(
                repoPath: repoPath,
                relativePath: event.relativePath,
                fsEventID: event.fsEventID
            )
            try validateExternalCreatedSyncResult(result, event: event)
            let createdFileID = try await refreshAfterExternalCreated(event)
            detailExternalCreateSyncState = .synced(event: event, fileID: createdFileID, result)
            await loadChangeLog(fileID: createdFileID)
        } catch {
            let mappedError = await mapCoreError(error)
            detailExternalCreateSyncState = .failed(event: event, mappedError)
        }
    }

    func requestDetailLogDiagnosticsPrivacyConfirmation() {
        guard case .failed(let fileID, _) = detailLogState,
              selection.singleFileID == fileID else { return }
        detailLogDiagnosticsState = .confirmingPrivacy(fileID: fileID)
    }

    func cancelDetailLogDiagnosticsPrivacyConfirmation() {
        guard case .confirmingPrivacy = detailLogDiagnosticsState else { return }
        detailLogDiagnosticsState = .idle
    }

    func collectDetailLogDiagnostics() async {
        guard case .confirmingPrivacy(let fileID) = detailLogDiagnosticsState,
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

    func beginRename(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID else { return }
        guard writeActionDisabledReason(fileID: fileID) == nil else { return }
        pendingActionDestination = .rename(fileID: fileID)
    }

    func beginChangeCategory(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID else { return }
        guard writeActionDisabledReason(fileID: fileID) == nil else { return }
        pendingActionDestination = .changeCategory(fileID: fileID)
    }

    func beginDelete(fileID: Int64? = nil) {
        guard let fileID = fileID ?? selection.singleFileID else { return }
        guard writeActionDisabledReason(fileID: fileID) == nil else { return }
        pendingActionDestination = .delete(fileID: fileID)
    }

    func clearPendingActionDestination() {
        pendingActionDestination = nil
    }

    func handleExternalRename(_ updatedFile: FileEntrySnapshot) {
        files = files.map { file in
            file.id == updatedFile.id ? updatedFile : file
        }
        if selection.singleFileID == updatedFile.id {
            selectedFileDetail = updatedFile
            statusBanner = .renamedPreservedSelection(fileID: updatedFile.id)
        }
    }

    func handleExternalRemoval(fileID: Int64) {
        files.removeAll { $0.id == fileID }
        guard selection.singleFileID == fileID || selectedFileDetail?.id == fileID else { return }

        selection = .single(fileID)
        selectedFileDetail = nil
        detailErrorMapping = CoreErrorMappingSnapshot.missingFromExternalChange(fileID: fileID)
        isDetailLoading = false
        statusBanner = .removedSelectedFile(fileID: fileID)
    }

    func clearStatusBanner() {
        statusBanner = nil
    }

    func writeActionDisabledReason(fileID: Int64) -> MainFileWriteActionDisabledReason? {
        if isReadOnly { return .repoReadOnly }
        if isLoading { return .listLoading }
        if writeLockedFileIDs.contains(fileID) { return .importLocked }
        return nil
    }

    var loadingStatusText: String? {
        guard isLoading else { return nil }
        return "正在加载 \(currentCategoryDisplayName)..."
    }

    var loadingAccessibilityText: String? {
        guard let loadingStatusText else { return nil }
        return "Loading files. \(loadingStatusText)"
    }

    func collectCurrentListDiagnostics() async {
        guard diagnosticsState != .collecting else { return }

        diagnosticsState = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            diagnosticsState = .collected(snapshot)
        } catch {
            diagnosticsState = .failed(await mapCoreError(error))
        }
    }

    func clearDiagnosticsState() {
        diagnosticsState = .idle
    }

    private func reloadCurrentCategory() async {
        loadGeneration += 1
        let generation = loadGeneration
        let filter = FileFilterSnapshot.currentCategory(currentCategory)

        isLoading = true
        errorMapping = nil
        statusBanner = nil
        diagnosticsState = .idle
        clearDetail()

        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            files = loadedFiles
            errorMapping = nil
            isLoading = false
        } catch {
            let mappedError = await mapListError(error)
            guard generation == loadGeneration else { return }
            files = []
            errorMapping = mappedError
            isLoading = false
        }
    }

    private func loadDetail(id: Int64) async {
        detailGeneration += 1
        let generation = detailGeneration

        do {
            let loadedFile = try await fileDetailer.getFile(repoPath: repoPath, fileID: id)
            guard generation == detailGeneration else { return }
            selection = .single(loadedFile.id)
            selectedFileDetail = loadedFile
            files = files.map { file in
                file.id == loadedFile.id ? loadedFile : file
            }
            detailErrorMapping = nil
            isDetailLoading = false
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailGeneration else { return }
            selectedFileDetail = selectedFileDetail ?? cachedFile(id: id)
            detailErrorMapping = mappedError
            isDetailLoading = false
        }
    }

    private func loadChangeLog(fileID: Int64) async {
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

    private func refreshAfterExternalCreated(_ event: MainExternalCreatedFileEvent) async throws -> Int64 {
        let loadedFiles = try await reloadFilesForExternalCreated()
        guard let createdFile = loadedFiles.first(where: { $0.path == event.relativePath }) else {
            throw CoreError.Internal(message: "created file was not visible after sync: \(event.relativePath)")
        }

        selection = .single(createdFile.id)
        selectedFileDetail = createdFile
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: createdFile.id)
        guard selectedFileDetail?.id == createdFile.id, detailErrorMapping == nil else {
            throw CoreError.Internal(message: "created file detail was not visible after sync: \(event.relativePath)")
        }
        return createdFile.id
    }

    private func reloadFilesForExternalCreated() async throws -> [FileEntrySnapshot] {
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
            errorMapping = await mapListError(error)
            isLoading = false
            throw error
        }
    }

    private func clearDetail() {
        detailGeneration += 1
        selection = .none
        selectedFileDetail = nil
        detailErrorMapping = nil
        isDetailLoading = false
        resetDetailLog()
        pendingActionDestination = nil
    }

    private func resetDetailLog() {
        detailLogGeneration += 1
        detailLogState = .notLoaded
        detailLogDiagnosticsState = .idle
        detailExternalCreateSyncState = .idle
    }

    private func mapListError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await mapCoreError(error)
    }

    private func canApplyDetailLogDiagnosticsResult(fileID: Int64) -> Bool {
        guard selection.singleFileID == fileID,
              case .failed(let failedFileID, _) = detailLogState else { return false }
        return failedFileID == fileID
    }

    private func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func validateExternalCreatedSyncResult(
        _ result: SyncResultSnapshot,
        event: MainExternalCreatedFileEvent
    ) throws {
        guard result.errors.isEmpty else {
            let message = result.errors.joined(separator: "; ")
            throw CoreError.Internal(message: "created event \(event.fsEventID) returned sync errors: \(message)")
        }
    }

    private var currentCategoryDisplayName: String {
        guard let currentCategory, !currentCategory.isEmpty else { return "files" }
        return currentCategory
    }

    private func cachedFile(id: Int64) -> FileEntrySnapshot? {
        files.first { $0.id == id }
    }
}

private extension CoreErrorMappingSnapshot {
    static func missingFromExternalChange(fileID: Int64) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "The selected file is missing.",
            severity: .medium,
            suggestedAction: "Refresh the current list or remove the stale index entry.",
            recoverability: .refreshRequired,
            rawContext: "file_id=\(fileID)"
        )
    }
}
