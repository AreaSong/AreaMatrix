import Foundation

protocol CoreFileCategoryMoving: Sendable {
    func previewMoveToCategory(
        repoPath: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot

    func moveToCategory(repoPath: String, fileID: Int64, newCategory: String) async throws -> FileEntrySnapshot

    func correctFileCategory(
        repoPath: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot
}

extension CoreFileCategoryMoving {
    func correctFileCategory(
        repoPath _: String,
        fileID _: Int64,
        targetCategory _: String,
        moveFile _: Bool,
        remember _: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        throw CoreError.Internal(message: "correct_file_category is unavailable")
    }
}

struct MoveToCategoryPreviewSnapshot: Equatable {
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

struct ClassifierRuleDraftSnapshot: Equatable {
    var sourceFileID: Int64
    var targetCategory: String
    var keywordCandidates: [String]
    var extensionCandidates: [String]
    var priority: Int64
}

struct ClassifierCorrectionResultSnapshot: Equatable {
    var updatedFile: FileEntrySnapshot
    var ruleDraft: ClassifierRuleDraftSnapshot?
    var moveFileRequested: Bool
    var rememberRequested: Bool
    var ruleConfirmationRequired: Bool
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
            try MoveToCategoryPreviewSnapshot(corePreview: previewCoreMoveToCategory(
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

    func correctFileCategory(
        repoPath: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        let result = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.correctFileCategory(
                repoPath: repoPath,
                fileId: fileID,
                category: targetCategory,
                moveFile: moveFile,
                remember: remember
            )
        }.value
        let updatedFile = await makeFileEntrySnapshot(from: result.updatedFile, repoPath: repoPath)
        return ClassifierCorrectionResultSnapshot(coreResult: result, updatedFile: updatedFile)
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
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

private extension ClassifierCorrectionResultSnapshot {
    init(coreResult: ClassifierCorrectionResult, updatedFile: FileEntrySnapshot) {
        self.updatedFile = updatedFile
        ruleDraft = coreResult.ruleDraft.map(ClassifierRuleDraftSnapshot.init(coreDraft:))
        moveFileRequested = coreResult.moveFileRequested
        rememberRequested = coreResult.rememberRequested
        ruleConfirmationRequired = coreResult.ruleConfirmationRequired
    }
}

private extension ClassifierRuleDraftSnapshot {
    init(coreDraft: ClassifierRuleDraft) {
        sourceFileID = coreDraft.sourceFileId
        targetCategory = coreDraft.targetCategory
        keywordCandidates = coreDraft.keywordCandidates
        extensionCandidates = coreDraft.extensionCandidates
        priority = coreDraft.priority
    }
}
