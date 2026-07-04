@testable import AreaMatrix
import Foundation

enum ICloudConflictMinimalOutOfScopeAction: Equatable {
    case rename
    case delete
    case removeIndex
    case previewMove
    case move
    case listChanges
    case syncExternalChanges
    case diagnostics
}

actor ICloudConflictMinimalRecordingMainCore: CoreFileListing,
    CoreFileDetailing,
    CoreFileRenaming,
    CoreFileDeleting,
    CoreFileCategoryMoving,
    CoreChangeLogListing,
    CoreExternalChangesSyncing,
    CoreDiagnosticsCollecting {
    private var filesByID: [Int64: FileEntrySnapshot]
    private var outOfScopeActions: [ICloudConflictMinimalOutOfScopeAction] = []

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        Array(filesByID.values).sorted { $0.id < $1.id }
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }
        return file
    }

    func renameFile(repoPath: String, fileID: Int64, newName _: String) async throws -> FileEntrySnapshot {
        outOfScopeActions.append(.rename)
        return try await getFile(repoPath: repoPath, fileID: fileID)
    }

    func deleteFile(repoPath _: String, fileID _: Int64) async throws {
        outOfScopeActions.append(.delete)
    }

    func removeIndexEntry(repoPath _: String, fileID _: Int64) async throws {
        outOfScopeActions.append(.removeIndex)
    }

    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        outOfScopeActions.append(.previewMove)
        let file = try await getFile(repoPath: repoPath, fileID: fileID)
        return MoveToCategoryPreviewSnapshot(
            fileID: file.id,
            fromCategory: file.category,
            toCategory: newCategory,
            currentPath: file.path,
            targetPath: "\(newCategory)/\(file.currentName)",
            targetName: file.currentName,
            storageMode: file.storageMode,
            indexOnly: false,
            nameConflictResolved: false,
            willMoveFile: false
        )
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory _: String) async throws -> FileEntrySnapshot {
        outOfScopeActions.append(.move)
        return try await getFile(repoPath: repoPath, fileID: fileID)
    }

    func listChanges(repoPath _: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        outOfScopeActions.append(.listChanges)
        return [.iCloudConflictMinimalConflictResolved(fileID: filter.fileID)]
    }

    func syncExternalCreated(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        outOfScopeActions.append(.syncExternalChanges)
        return .iCloudConflictMinimalEmptySyncResult()
    }

    func syncExternalRenamed(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        outOfScopeActions.append(.syncExternalChanges)
        return .iCloudConflictMinimalEmptySyncResult()
    }

    func syncExternalRemoved(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        outOfScopeActions.append(.syncExternalChanges)
        return .iCloudConflictMinimalEmptySyncResult()
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        nil
    }

    func setFSEventCursor(repoPath _: String, lastEventID _: Int64) async throws {}

    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        outOfScopeActions.append(.diagnostics)
        return DiagnosticsSnapshotSnapshot(snapshotPath: "", createdAt: 0, warnings: [])
    }

    func recordedOutOfScopeActions() -> [ICloudConflictMinimalOutOfScopeAction] {
        outOfScopeActions
    }
}

actor ICloudConflictResolver: ICloudConflictResolving {
    nonisolated let iCloudConflictResolutionCapability: ICloudConflictResolutionCapability
    private let result: Result<ICloudConflictResolutionResult, Error>
    private var requests: [ICloudConflictResolutionRequest] = []

    init(
        capability: ICloudConflictResolutionCapability = .supported,
        result: Result<ICloudConflictResolutionResult, Error>
    ) {
        iCloudConflictResolutionCapability = capability
        self.result = result
    }

    func resolveICloudConflict(_ request: ICloudConflictResolutionRequest) async throws
        -> ICloudConflictResolutionResult {
        requests.append(request)
        return try result.get()
    }

    func recordedRequests() -> [ICloudConflictResolutionRequest] {
        requests
    }
}

actor ICloudConflictReviewer: CoreICloudConflictReviewing {
    struct PreviewRequest: Equatable {
        var repoPath: String
        var conflictID: String
    }

    struct ResolveRequest: Equatable {
        var repoPath: String
        var conflictID: String
        var strategy: ICloudConflictResolutionStrategy
    }

    private let previewResult: Result<ICloudConflictPreviewSnapshot, Error>
    private let resolveResult: Result<ICloudConflictResolveReportSnapshot, Error>
    private var previewRequests: [PreviewRequest] = []
    private var resolveRequests: [ResolveRequest] = []

    init(
        previewResult: Result<ICloudConflictPreviewSnapshot, Error>,
        resolveResult: Result<ICloudConflictResolveReportSnapshot, Error>
    ) {
        self.previewResult = previewResult
        self.resolveResult = resolveResult
    }

    func previewICloudConflict(repoPath: String, conflictID: String) async throws
        -> ICloudConflictPreviewSnapshot {
        previewRequests.append(PreviewRequest(repoPath: repoPath, conflictID: conflictID))
        return try previewResult.get()
    }

    func resolvePreviewedICloudConflict(_ request: ICloudConflictResolutionRequest) async throws
        -> ICloudConflictResolutionResult {
        resolveRequests.append(ResolveRequest(
            repoPath: request.repoPath,
            conflictID: request.conflictID,
            strategy: request.strategy
        ))
        return try ICloudConflictResolutionResult(report: resolveResult.get())
    }

    func recordedPreviewRequests() -> [PreviewRequest] {
        previewRequests
    }

    func recordedResolveRequests() -> [ResolveRequest] {
        resolveRequests
    }
}
