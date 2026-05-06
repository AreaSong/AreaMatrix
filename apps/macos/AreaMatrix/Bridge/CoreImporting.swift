import Foundation

protocol CoreFileImporting: Sendable {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot
}

extension CoreFileImporting {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importCopiedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importMovedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importIndexedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }
}

extension CoreBridge: CoreFileImporting {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            mode: .copied,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            mode: .moved,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            mode: .indexed,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    private func importFile(
        repoPath: String,
        sourceURL: URL,
        mode: StorageMode,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        let options = ImportOptions(
            mode: mode,
            destination: .autoClassify,
            targetDirectory: nil,
            overrideCategory: overrideCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
        let entry = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.importFile(repoPath: repoPath, sourcePath: sourceURL.path, options: options)
        }.value
        return FileEntrySnapshot(coreEntry: entry) { _, _ in .available }
    }
}
