import Combine
import Foundation

enum MainFileSelectionState: Equatable, Sendable {
    case none
    case single(Int64)
    case multiple(Set<Int64>)

    var singleFileID: Int64? {
        if case .single(let id) = self { return id }
        return nil
    }

    var isMultiple: Bool {
        if case .multiple = self { return true }
        return false
    }
}

enum MainFileActionDestination: Equatable, Sendable {
    case rename(fileID: Int64)
    case changeCategory(fileID: Int64)
    case delete(fileID: Int64)

    var pageID: String {
        switch self {
        case .rename:
            return "S1-33"
        case .changeCategory:
            return "S1-35"
        case .delete:
            return "S1-34"
        }
    }

    var pageTitle: String {
        switch self {
        case .rename:
            return "Rename File"
        case .changeCategory:
            return "Change Category"
        case .delete:
            return "Move File to Trash?"
        }
    }

    var fileID: Int64 {
        switch self {
        case .rename(let fileID), .changeCategory(let fileID), .delete(let fileID):
            return fileID
        }
    }
}

extension MainFileActionDestination: Identifiable {
    var id: String {
        "\(pageID)-\(fileID)"
    }
}

enum MainListStatusBanner: Equatable, Sendable {
    case renamedPreservedSelection(fileID: Int64)
    case removedSelectedFile(fileID: Int64)

    var message: String {
        switch self {
        case .renamedPreservedSelection:
            return "External rename detected. The same file remains selected."
        case .removedSelectedFile:
            return "Selected file is missing or was removed outside AreaMatrix."
        }
    }
}

enum MainFileWriteActionDisabledReason: String, Equatable, Sendable {
    case repoReadOnly = "Repository is read-only"
    case listLoading = "Current list is loading"
    case importLocked = "This file is locked by an import"
}

enum MainFileActionCategoryOptions {
    static func availableCategories(
        file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> [String] {
        let categories = categoryRows.compactMap(\.categoryForFileList)
        let current = file.map { [$0.category] } ?? []
        return Array(Set(categories + current)).sorted()
    }

    static func defaultTargetCategory(
        for file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        let categories = availableCategories(file: nil, categoryRows: categoryRows)
        return categories.first { $0 != file?.category } ?? file?.category ?? ""
    }
}

enum MainListDiagnosticsState: Equatable, Sendable {
    case idle
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

@MainActor
final class MainFileListModel: ObservableObject {
    @Published private(set) var files: [FileEntrySnapshot]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var selection: MainFileSelectionState = .none
    @Published private(set) var selectedFileDetail: FileEntrySnapshot?
    @Published private(set) var isDetailLoading = false
    @Published private(set) var detailErrorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var pendingActionDestination: MainFileActionDestination?
    @Published private(set) var statusBanner: MainListStatusBanner?
    @Published private(set) var diagnosticsState: MainListDiagnosticsState = .idle

    private let repoPath: String
    private let isReadOnly: Bool
    private let writeLockedFileIDs: Set<Int64>
    private let fileLister: any CoreFileListing
    private let fileDetailer: any CoreFileDetailing
    private let errorMapper: any CoreErrorMapping
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private var currentCategory: String?
    private var loadGeneration = 0
    private var detailGeneration = 0

    init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
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
        selectedFileDetail = nil
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: id)
    }

    func retrySelectedFileDetail() async {
        guard let selectedFileID = selection.singleFileID else { return }

        selectedFileDetail = nil
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: selectedFileID)
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
            detailErrorMapping = nil
            isDetailLoading = false
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailGeneration else { return }
            selectedFileDetail = nil
            detailErrorMapping = mappedError
            isDetailLoading = false
        }
    }

    private func clearDetail() {
        detailGeneration += 1
        selection = .none
        selectedFileDetail = nil
        detailErrorMapping = nil
        isDetailLoading = false
        pendingActionDestination = nil
    }

    private func mapListError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await mapCoreError(error)
    }

    private func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
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
