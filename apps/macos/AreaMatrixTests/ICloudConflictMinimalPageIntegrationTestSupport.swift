@testable import AreaMatrix
import Foundation

enum S125OutOfScopeAction: Equatable {
    case rename
    case delete
    case removeIndex
    case previewMove
    case move
    case listChanges
    case syncExternalChanges
    case diagnostics
}

actor S125RecordingMainCore: CoreFileListing,
    CoreFileDetailing,
    CoreFileRenaming,
    CoreFileDeleting,
    CoreFileCategoryMoving,
    CoreChangeLogListing,
    CoreExternalChangesSyncing,
    CoreDiagnosticsCollecting {
    private var filesByID: [Int64: FileEntrySnapshot]
    private var outOfScopeActions: [S125OutOfScopeAction] = []

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
        return [.s125ConflictResolved(fileID: filter.fileID)]
    }

    func syncExternalCreated(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        outOfScopeActions.append(.syncExternalChanges)
        return .s125NoopSyncResult()
    }

    func syncExternalRenamed(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        outOfScopeActions.append(.syncExternalChanges)
        return .s125NoopSyncResult()
    }

    func syncExternalRemoved(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        outOfScopeActions.append(.syncExternalChanges)
        return .s125NoopSyncResult()
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        nil
    }

    func setFSEventCursor(repoPath _: String, lastEventID _: Int64) async throws {}

    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        outOfScopeActions.append(.diagnostics)
        return DiagnosticsSnapshotSnapshot(snapshotPath: "", createdAt: 0, warnings: [])
    }

    func recordedOutOfScopeActions() -> [S125OutOfScopeAction] {
        outOfScopeActions
    }
}

actor S125RecordingICloudConflictResolver: ICloudConflictResolving {
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

actor S220RecordingConflictReviewer: CoreICloudConflictReviewing {
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
        return ICloudConflictResolutionResult(report: try resolveResult.get())
    }

    func recordedPreviewRequests() -> [PreviewRequest] {
        previewRequests
    }

    func recordedResolveRequests() -> [ResolveRequest] {
        resolveRequests
    }
}

actor S125RecordingPathValidator: CoreRepositoryPathValidating {
    private let result: Result<RepoPathValidationSnapshot, Error>
    private var repoPaths: [String] = []

    init(result: Result<RepoPathValidationSnapshot, Error>) {
        self.result = result
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        repoPaths.append(repoPath)
        return try result.get()
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

actor S125RecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

actor S125NoopNoteStore: CoreNoteReadingWriting {
    func readNote(repoPath _: String, fileID _: Int64) async throws -> String? {
        nil
    }

    func writeNote(repoPath _: String, fileID _: Int64, contentMarkdown _: String) async throws {}
}

extension SyncResultSnapshot {
    static func s125NoopSyncResult() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: []
        )
    }
}

extension MainDetailLogState {
    var s125LoadedFileID: Int64? {
        guard case let .loaded(fileID, _) = self else { return nil }
        return fileID
    }
}

extension ChangeLogEntrySnapshot {
    static func s125ConflictResolved(fileID: Int64?) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: 1,
            fileID: fileID,
            filename: "report (Conflicted Copy).pdf",
            category: "docs",
            action: "conflict_resolved_keep_both",
            detailJSON: #"{"conflict_id":"s125","kept_paths":["docs/report.pdf","docs/report (Conflicted Copy).pdf"]}"#,
            occurredAt: 1_775_020_900
        )
    }
}

extension RepositoryOpeningResult {
    static func s125Fixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: Int64(files.count),
                children: [
                    RepositoryTreeNodeSnapshot(
                        slug: "docs",
                        displayName: "docs",
                        fileCount: Int64(files.count),
                        children: []
                    )
                ]
            ),
            currentCategoryFiles: files
        )
    }
}

extension FileEntrySnapshot {
    static func s125ConflictFixture(id: Int64) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/report (Conflicted Copy).pdf",
            originalName: "report (Conflicted Copy).pdf",
            currentName: "report (Conflicted Copy).pdf",
            category: "docs",
            sizeBytes: 512,
            hashSha256: "s125-conflict-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_775_020_860
        )
    }
}

extension RepoPathValidationSnapshot {
    static func s125ICloudConflictFixture() -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/s125-repo",
            isEmpty: false,
            isInitialized: true,
            isICloudPath: true,
            issues: [.alreadyInitialized, .iCloudPath],
            recommendedMode: nil
        )
    }
}

extension ICloudConflictVersionSnapshot {
    static func s125Original(repoPath: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .original,
            path: "\(repoPath)/docs/report.pdf",
            modifiedAt: 1_775_020_800,
            sizeBytes: 512
        )
    }

    static func s125ConflictedCopy(repoPath: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .conflictedCopy,
            path: "\(repoPath)/docs/report (Conflicted Copy).pdf",
            modifiedAt: 1_775_020_860,
            sizeBytes: 768
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func s125Mapping(
        kind: CoreErrorKindSnapshot = .iCloudPlaceholder,
        rawContext: String = "/tmp/s125-repo/docs/report.pdf.icloud"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "AreaMatrix cannot inspect this conflict source.",
            severity: .high,
            suggestedAction: "Refresh the source page or download the iCloud item in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}

extension ICloudConflictPreviewSnapshot {
    static func s220Preview(
        conflictID: String,
        metadataComplete: Bool = true,
        trashAvailable: Bool = true
    ) -> ICloudConflictPreviewSnapshot {
        ICloudConflictPreviewSnapshot(
            conflictID: conflictID,
            versions: [
                ICloudConflictVersionMetadataSnapshot(
                    versionID: "original",
                    role: .original,
                    path: "docs/report.pdf",
                    modifiedAt: 1_775_020_800,
                    sizeBytes: 512,
                    hashSha256: "aaaaaaaaaaaabbbb",
                    previewSummary: "Original preview",
                    previewStatus: .available
                ),
                ICloudConflictVersionMetadataSnapshot(
                    versionID: "conflicted-copy",
                    role: .conflictedCopy,
                    path: "docs/report (copy).pdf",
                    modifiedAt: 1_775_020_860,
                    sizeBytes: 768,
                    hashSha256: "bbbbbbbbbbbbaaaa",
                    previewSummary: "Conflicted preview",
                    previewStatus: .available
                )
            ],
            defaultResolution: .keepBoth,
            resolutionOptions: [
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepBoth,
                    destructive: false,
                    requiresTrash: false,
                    enabled: true,
                    disabledReason: nil
                ),
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepOriginalOnly,
                    destructive: true,
                    requiresTrash: true,
                    enabled: metadataComplete && trashAvailable,
                    disabledReason: metadataComplete && trashAvailable ? nil : "Trash unavailable"
                ),
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepConflictedCopyOnly,
                    destructive: true,
                    requiresTrash: true,
                    enabled: metadataComplete && trashAvailable,
                    disabledReason: metadataComplete && trashAvailable ? nil : "Trash unavailable"
                )
            ],
            metadataComplete: metadataComplete,
            trashAvailable: trashAvailable,
            canKeepBoth: true,
            canResolveDestructive: metadataComplete && trashAvailable,
            blockedReason: metadataComplete && trashAvailable ? nil : "Trash unavailable"
        )
    }
}

extension ICloudConflictResolveReportSnapshot {
    static func s220ResolvedReport(conflictID: String) -> ICloudConflictResolveReportSnapshot {
        ICloudConflictResolveReportSnapshot(
            conflictID: conflictID,
            resolution: .keepBoth,
            status: .resolved,
            keptPaths: [
                "docs/report.pdf",
                "docs/report (copy).pdf"
            ],
            trashedPaths: [],
            undoToken: nil,
            changeLogAction: "external_modified"
        )
    }
}

func s125IntegrationMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS125IntegrationMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS125IntegrationMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS125IntegrationMirrorDescription(of: child.value, to: &lines)
    }
}
