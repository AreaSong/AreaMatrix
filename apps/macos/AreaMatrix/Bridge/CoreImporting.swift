import AreaMatrixFeatureIngestion
import Foundation

enum ImportDuplicateStrategySnapshot: Equatable, Hashable {
    case skip, overwrite, keepBoth, ask

    fileprivate var coreValue: DuplicateStrategy {
        switch self {
        case .skip: .skip
        case .overwrite: .overwrite
        case .keepBoth: .keepBoth
        case .ask: .ask
        }
    }
}

protocol CoreFileImporting: Sendable {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: ImportDuplicateStrategySnapshot
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
    var duplicateStrategy: ImportDuplicateStrategySnapshot
    var traceContext: CoreImportTraceContext?
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

extension CoreBridge: CoreFileImporting, CoreObservedFileImporting, CoreBatchCopyImporting {
    func importCopiedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: repoPath)
        return try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            options: ImportOptions(
                mode: .copied,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy.coreValue,
                contentLocale: ContentLocale(snapshotValue: contentLocale)
            ),
            traceContext: nil
        )
    }

    func importCopiedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot {
        try await importObservedFile(request, mode: .copied)
    }

    func importCopiedFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: request.repoPath)
        return try await importFile(
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
                duplicateStrategy: request.duplicateStrategy.coreValue,
                contentLocale: ContentLocale(snapshotValue: contentLocale)
            ),
            traceContext: request.traceContext
        )
    }

    func importBatchFile(request: CoreBatchImportRequest) async throws -> FileEntrySnapshot {
        switch request.storageMode {
        case .copy:
            return try await importCopiedFile(request: request)
        case .indexOnly:
            let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: request.repoPath)
            return try await importFile(
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
                    duplicateStrategy: request.duplicateStrategy.coreValue,
                    contentLocale: ContentLocale(snapshotValue: contentLocale)
                ),
                traceContext: request.traceContext
            )
        case .move:
            let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: request.repoPath)
            return try await importFile(
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
                    duplicateStrategy: request.duplicateStrategy.coreValue,
                    contentLocale: ContentLocale(snapshotValue: contentLocale)
                ),
                traceContext: request.traceContext
            )
        }
    }

    func importMovedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: repoPath)
        return try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            options: ImportOptions(
                mode: .moved,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy.coreValue,
                contentLocale: ContentLocale(snapshotValue: contentLocale)
            ),
            traceContext: nil
        )
    }

    func importMovedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot {
        try await importObservedFile(request, mode: .moved)
    }

    func importIndexedFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String,
        duplicateStrategy: ImportDuplicateStrategySnapshot
    ) async throws -> FileEntrySnapshot {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: repoPath)
        return try await importFile(
            repoPath: repoPath,
            sourceURL: sourceURL,
            options: ImportOptions(
                mode: .indexed,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy.coreValue,
                contentLocale: ContentLocale(snapshotValue: contentLocale)
            ),
            traceContext: nil
        )
    }

    func importIndexedFile(request: CoreObservedImportRequest) async throws -> FileEntrySnapshot {
        try await importObservedFile(request, mode: .indexed)
    }

    private func importObservedFile(
        _ request: CoreObservedImportRequest,
        mode: StorageMode
    ) async throws -> FileEntrySnapshot {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: request.repoPath)
        return try await importFile(
            repoPath: request.repoPath,
            sourceURL: request.sourceURL,
            options: ImportOptions(
                mode: mode,
                destination: .autoClassify,
                targetDirectory: nil,
                overrideCategory: request.overrideCategory,
                overrideFilename: request.overrideFilename,
                duplicateStrategy: request.duplicateStrategy.coreValue,
                contentLocale: ContentLocale(snapshotValue: contentLocale)
            ),
            traceContext: request.traceContext
        )
    }

    private func importFile(
        repoPath: String,
        sourceURL: URL,
        options: ImportOptions,
        traceContext: CoreImportTraceContext? = nil
    ) async throws -> FileEntrySnapshot {
        let appTraceContext = traceContext ?? CoreImportTraceContext(
            traceID: UUID().uuidString.lowercased(),
            spanID: UUID().uuidString.lowercased(),
            operationID: UUID().uuidString.lowercased(),
            retryOfOperationID: nil,
            actionID: "repository.import.confirmed",
            componentID: "macos.import.bridge"
        )
        let coreTraceContext = await importObservability.traceContextProvider.make(.init(
            traceID: appTraceContext.traceID,
            parentSpanID: appTraceContext.spanID,
            operationID: appTraceContext.operationID,
            actionID: appTraceContext.actionID,
            componentID: "core.repository.import",
            incidentID: nil,
            retryOfOperationID: appTraceContext.retryOfOperationID,
            sourceURL: sourceURL,
            storageMode: options.mode
        ))
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try AreaMatrix.importFileWithResultObserved(
                    repoPath: repoPath,
                    sourcePath: sourceURL.path,
                    options: options,
                    traceContext: coreTraceContext
                )
            }.value
            var entry = FileEntrySnapshot(coreEntry: result.entry) { _, _ in .available }
            entry.importCommitState = CoreImportCommitState(result.sourceRemovalStatus)
            await importObservability.recordTerminal(
                appTraceContext,
                coreTraceContext: coreTraceContext,
                outcome: entry.importCommitState.isDegraded ? "degraded" : "succeeded"
            )
            return entry
        } catch {
            await importObservability.recordTerminal(
                appTraceContext,
                coreTraceContext: coreTraceContext,
                outcome: "failed",
                error: error
            )
            throw error
        }
    }
}

private extension CoreImportCommitState {
    init(_ status: ImportSourceRemovalStatus) {
        self = status == .retained ? .sourceRetained : .committed
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
