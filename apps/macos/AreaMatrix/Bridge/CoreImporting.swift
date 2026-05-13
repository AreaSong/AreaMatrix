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
    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot
}

struct CoreBatchImportRequest {
    var repoPath: String
    var sourceURL: URL
    var storageMode: ImportSingleFileStorageMode
    var destination: ImportEntryDestination
    var suggestedCategory: String?
    var overrideFilename: String
    var duplicateStrategy: DuplicateStrategy
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
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        destination: ImportEntryDestination,
        suggestedCategory: String?,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        try await importCopiedFile(request: CoreBatchImportRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            storageMode: .copy,
            destination: destination,
            suggestedCategory: suggestedCategory,
            overrideFilename: overrideFilename,
            duplicateStrategy: .ask
        ))
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

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        try await importFile(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            options: ImportOptions(
                mode: .copied,
                destination: coreImportDestination(for: request.destination),
                targetDirectory: coreImportTargetDirectory(for: request.destination),
                overrideCategory: coreImportCategoryOverride(
                    for: request.destination,
                    suggestedCategory: request.suggestedCategory
                ),
                overrideFilename: request.overrideFilename,
                duplicateStrategy: request.duplicateStrategy
            )
        )
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        switch request.storageMode {
        case .copy:
            try await importCopiedFile(request: request)
        case .indexOnly:
            try await importFile(
                repoPath: request.repoPath,
                sourceURL: request.sourceURL,
                options: ImportOptions(
                    mode: .indexed,
                    destination: coreImportDestination(for: request.destination),
                    targetDirectory: coreImportTargetDirectory(for: request.destination),
                    overrideCategory: coreImportCategoryOverride(
                        for: request.destination,
                        suggestedCategory: request.suggestedCategory
                    ),
                    overrideFilename: request.overrideFilename,
                    duplicateStrategy: request.duplicateStrategy
                )
            )
        case .move:
            try await importFile(
                repoPath: request.repoPath,
                sourceURL: request.sourceURL,
                options: ImportOptions(
                    mode: .moved,
                    destination: coreImportDestination(for: request.destination),
                    targetDirectory: coreImportTargetDirectory(for: request.destination),
                    overrideCategory: coreImportCategoryOverride(
                        for: request.destination,
                        suggestedCategory: request.suggestedCategory
                    ),
                    overrideFilename: request.overrideFilename,
                    duplicateStrategy: request.duplicateStrategy
                )
            )
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
        .autoClassify
    case .category:
        .category
    case .repositoryRoot:
        .selectedDirectory
    }
}

private func coreImportTargetDirectory(for destination: ImportEntryDestination) -> String? {
    switch destination {
    case .autoClassify, .category:
        nil
    case .repositoryRoot:
        ""
    }
}

private func coreImportCategoryOverride(
    for destination: ImportEntryDestination,
    suggestedCategory: String?
) -> String? {
    switch destination {
    case .autoClassify:
        suggestedCategory
    case let .category(slug):
        slug
    case .repositoryRoot:
        nil
    }
}
