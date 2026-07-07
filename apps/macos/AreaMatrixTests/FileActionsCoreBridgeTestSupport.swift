@testable import AreaMatrix

enum FileActionsCoreCall: Equatable {
    case rename(fileID: Int64, newName: String)
    case previewMove(fileID: Int64, targetCategory: String)
    case move(fileID: Int64, targetCategory: String)
    case removeIndex(fileID: Int64)
    case delete(fileID: Int64)

    var isDeclaredFileActionCapability: Bool {
        switch self {
        case .rename, .delete, .removeIndex, .previewMove, .move:
            true
        }
    }
}

actor FileActionsRecordingCore: CoreFileListing,
    CoreFileDetailing,
    CoreFileRenaming,
    CoreFileDeleting,
    CoreFileCategoryMoving,
    CoreChangeLogListing,
    CoreErrorMapping {
    private var filesByID: [Int64: FileEntrySnapshot]
    private var calls: [FileActionsCoreCall] = []

    init(files: [FileEntrySnapshot]) {
        filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
    }

    func listFiles(repoPath _: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        filesByID.values
            .filter { filter.category == nil || $0.category == filter.category }
            .sorted { $0.id < $1.id }
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = filesByID[fileID] else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }
        return file
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        calls.append(.rename(fileID: fileID, newName: newName))
        var file = try await getFile(repoPath: repoPath, fileID: fileID)
        file.currentName = newName
        file.path = "\(file.path.split(separator: "/").dropLast().joined(separator: "/"))/\(newName)"
        filesByID[fileID] = file
        return file
    }

    func deleteFile(repoPath _: String, fileID: Int64) async throws {
        calls.append(.delete(fileID: fileID))
        filesByID.removeValue(forKey: fileID)
    }

    func removeIndexEntry(repoPath _: String, fileID: Int64) async throws {
        calls.append(.removeIndex(fileID: fileID))
        filesByID.removeValue(forKey: fileID)
    }

    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        calls.append(.previewMove(fileID: fileID, targetCategory: newCategory))
        let file = try await getFile(repoPath: repoPath, fileID: fileID)
        return MoveToCategoryPreviewSnapshot.testFixture(
            fileID: file.id,
            fromCategory: file.category,
            toCategory: newCategory,
            targetName: file.currentName
        ) {
            $0.currentPath = file.path
            $0.targetPath = "\(newCategory)/\(file.currentName)"
            $0.storageMode = file.storageMode
            $0.indexOnly = file.storageMode == "Indexed"
            $0.nameConflictResolved = false
            $0.willMoveFile = file.storageMode != "Indexed"
        }
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot {
        calls.append(.move(fileID: fileID, targetCategory: newCategory))
        var file = try await getFile(repoPath: repoPath, fileID: fileID)
        file.category = newCategory
        file.path = "\(newCategory)/\(file.currentName)"
        filesByID[fileID] = file
        return file
    }

    func listChanges(repoPath _: String, filter _: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        []
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .internal,
            userMessage: "\(error)",
            severity: .high,
            suggestedAction: "Retry the file action.",
            recoverability: .retryable,
            rawContext: "file-actions integration verify"
        )
    }

    func recordedActionCalls() -> [FileActionsCoreCall] {
        calls
    }
}
