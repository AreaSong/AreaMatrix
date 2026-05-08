import Foundation

protocol CoreFileCategoryMoving: Sendable {
    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot
}

struct MoveToCategoryPreviewSnapshot: Equatable, Sendable {
    var fileID: Int64
    var fromCategory: String
    var toCategory: String
    var currentPath: String
    var targetPath: String
    var targetName: String
    var storageMode: String
    var indexOnly: Bool
    var nameConflictResolved: Bool
    var willMoveFile: Bool
}

extension MoveToCategoryPreviewSnapshot {
    init(corePreview: MoveToCategoryPreview) {
        fileID = corePreview.fileId
        fromCategory = corePreview.fromCategory
        toCategory = corePreview.toCategory
        currentPath = corePreview.currentPath
        targetPath = corePreview.targetPath
        targetName = corePreview.targetName
        storageMode = corePreview.storageMode.moveToCategoryDisplayName
        indexOnly = corePreview.indexOnly
        nameConflictResolved = corePreview.nameConflictResolved
        willMoveFile = corePreview.willMoveFile
    }
}

extension CoreBridge: CoreFileCategoryMoving {
    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        try await Task.detached(priority: .userInitiated) {
            MoveToCategoryPreviewSnapshot(corePreview: try previewCoreMoveToCategory(
                repoPath: repoPath,
                fileID: fileID,
                newCategory: newCategory
            ))
        }.value
    }

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot {
        let entry = try await Task.detached(priority: .userInitiated) {
            try moveCoreToCategory(repoPath: repoPath, fileID: fileID, newCategory: newCategory)
        }.value
        return await makeFileEntrySnapshot(from: entry, repoPath: repoPath)
    }
}

private func previewCoreMoveToCategory(
    repoPath: String,
    fileID: Int64,
    newCategory: String
) throws -> MoveToCategoryPreview {
    try previewMoveToCategory(repoPath: repoPath, fileId: fileID, newCategory: newCategory)
}

private func moveCoreToCategory(repoPath: String, fileID: Int64, newCategory: String) throws -> FileEntry {
    try moveToCategory(repoPath: repoPath, fileId: fileID, newCategory: newCategory)
}

private extension StorageMode {
    var moveToCategoryDisplayName: String {
        switch self {
        case .moved:
            return "Moved"
        case .copied:
            return "Copied"
        case .indexed:
            return "Indexed"
        }
    }
}
