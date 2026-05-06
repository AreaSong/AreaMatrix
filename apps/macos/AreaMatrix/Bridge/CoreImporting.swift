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

protocol CoreBatchCopyImporting: Sendable {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot

    func importBatchFile(
        repoPath: String,
        sourceURL: URL,
        storageMode: ImportSingleFileStorageMode,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
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

extension CoreBatchCopyImporting {
    func importBatchFile(
        repoPath: String,
        sourceURL: URL,
        storageMode: ImportSingleFileStorageMode,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        guard storageMode == .copy else {
            throw CoreError.Internal(message: "Batch \(storageMode.rawValue) import is unavailable.")
        }
        return try await importCopiedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            destination: destination,
            suggestedCategory: suggestedCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: duplicateStrategy
        )
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importCopiedFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            destination: destination,
            suggestedCategory: suggestedCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        )
    }
}

extension CoreBridge: CoreFileImporting, CoreBatchCopyImporting {
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
            options: ImportOptions(
                mode: .copied,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        )
    }

    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            options: ImportOptions(
                mode: .copied,
                destination: coreImportDestination(for: destination),
                targetDirectory: coreImportTargetDirectory(for: destination),
                overrideCategory: coreImportCategoryOverride(
                    for: destination,
                    suggestedCategory: suggestedCategory
                ),
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        )
    }

    func importBatchFile(
        repoPath: String,
        sourceURL: URL,
        storageMode: ImportSingleFileStorageMode,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String,
        duplicateStrategy: DuplicateStrategy
    ) async throws -> FileEntrySnapshot {
        switch storageMode {
        case .copy:
            return try await importCopiedFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                destination: destination,
                suggestedCategory: suggestedCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        case .indexOnly:
            return try await importFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                options: ImportOptions(
                    mode: .indexed,
                    destination: coreImportDestination(for: destination),
                    targetDirectory: coreImportTargetDirectory(for: destination),
                    overrideCategory: coreImportCategoryOverride(
                        for: destination,
                        suggestedCategory: suggestedCategory
                    ),
                    overrideFilename: overrideFilename,
                    duplicateStrategy: duplicateStrategy
                )
            )
        case .move:
            throw CoreError.Internal(message: "S1-19 folder import does not implement Move storage mode.")
        }
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
            options: ImportOptions(
                mode: .moved,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
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
            options: ImportOptions(
                mode: .indexed,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        )
    }

    private func importFile(
        repoPath: String,
        sourceURL: URL,
        options: ImportOptions
    ) async throws -> FileEntrySnapshot {
        let entry = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.importFile(repoPath: repoPath, sourcePath: sourceURL.path, options: options)
        }.value
        return FileEntrySnapshot(coreEntry: entry) { _, _ in .available }
    }
}

private func coreImportDestination(for destination: ImportEntryDestination) -> ImportDestination {
    switch destination {
    case .autoClassify:
        return .autoClassify
    case .category:
        return .category
    case .repositoryRoot:
        return .selectedDirectory
    }
}

private func coreImportTargetDirectory(for destination: ImportEntryDestination) -> String? {
    switch destination {
    case .autoClassify, .category:
        return nil
    case .repositoryRoot:
        return ""
    }
}

private func coreImportCategoryOverride(
    for destination: ImportEntryDestination,
    suggestedCategory: String?
) -> String? {
    switch destination {
    case .autoClassify:
        return suggestedCategory
    case .category(let slug):
        return slug
    case .repositoryRoot:
        return nil
    }
}
