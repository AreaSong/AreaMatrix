import Foundation

struct ImportBatchCopyCycleResult {
    var entry: FileEntrySnapshot?
    var completed: Int
    var failed: Int
    var total: Int
    var currentPath: String
    var lastImportedPath: String?
    var stoppedForDuplicate: Bool
    var stoppedForQueue: Bool
    var sessionPersistenceFailure: ImportBatchSessionStoreError?

    var progress: ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: total - completed - failed,
            currentPath: currentPath
        )
    }

    static func success(
        entry: FileEntrySnapshot,
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String
    ) -> ImportBatchCopyCycleResult {
        ImportBatchCopyCycleResult(
            entry: entry,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            lastImportedPath: entry.path,
            stoppedForDuplicate: false,
            stoppedForQueue: false,
            sessionPersistenceFailure: nil
        )
    }

    static func failure(
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String,
        stoppedForQueue: Bool = false
    ) -> ImportBatchCopyCycleResult {
        ImportBatchCopyCycleResult(
            entry: nil,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            lastImportedPath: nil,
            stoppedForDuplicate: false,
            stoppedForQueue: stoppedForQueue,
            sessionPersistenceFailure: nil
        )
    }

    static func duplicate(
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String
    ) -> ImportBatchCopyCycleResult {
        ImportBatchCopyCycleResult(
            entry: nil,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            lastImportedPath: nil,
            stoppedForDuplicate: true,
            stoppedForQueue: true,
            sessionPersistenceFailure: nil
        )
    }
}

struct ImportBatchCopyCycleInput {
    var rowIndex: Int
    var request: ImportEntryRequest
    var selectedDestination: ImportBatchDestinationOption
    var completed: Int
    var failed: Int
    var total: Int
    var traceContext: CoreImportTraceContext
}

struct ImportFolderImportCycleInput {
    var rowIndex: Int
    var request: ImportEntryRequest
    var storageMode: ImportSingleFileStorageMode
    var completed: Int
    var failed: Int
    var total: Int
    var traceContext: CoreImportTraceContext
}

struct ImportBatchRetryContinuation {
    var request: ImportEntryRequest
    var retryEntry: FileEntrySnapshot
    var retryRowIndex: Int?
    var retryPath: String
    var traceID: String
}

struct ImportBatchCopyRunState {
    var completed = 0
    var failed = 0
    var succeededEntries: [FileEntrySnapshot] = []
    var lastImportedPath = ""
    var stoppedForDuplicate = false
    var didStopAfterCurrentFile = false
    var fatalRetryContext: ImportProgressRetryContext?
    var sessionPersistenceFailure: ImportBatchSessionStoreError?
}

struct ImportBatchCopyRunInput {
    var readyRowIDs: Set<ImportBatchCopyImportRow.ID>
    var request: ImportEntryRequest
    var selectedDestination: ImportBatchDestinationOption
    var total: Int
    var traceID: String
}

struct ImportFolderImportRunState {
    var completed = 0
    var failed = 0
    var succeededEntries: [FileEntrySnapshot] = []
    var lastImportedPath = ""
    var didStopAfterCurrentFile = false
    var fatalRetryContext: ImportProgressRetryContext?
}

struct ImportFolderImportRunInput {
    var readyRowIDs: Set<ImportFolderPreviewRow.ID>
    var request: ImportEntryRequest
    var storageMode: ImportSingleFileStorageMode
    var total: Int
    var traceID: String
}

extension ImportBatchCopyImportModel {
    func importRow(
        _ row: ImportBatchCopyImportRow,
        request: ImportEntryRequest,
        selectedDestination: ImportBatchDestinationOption,
        traceContext: CoreImportTraceContext
    ) async throws -> FileEntrySnapshot {
        try await importer.importBatchFile(request: CoreBatchImportRequest(
            repoPath: request.repoPath,
            sourceURL: row.sourceURL,
            storageMode: selectedStorageMode,
            destination: entryDestination(for: row, selectedDestination: selectedDestination),
            suggestedCategory: row.categoryOverride ?? row.predictedCategory,
            overrideFilename: row.resolvedIncomingName,
            duplicateStrategy: duplicateStrategy(for: row),
            traceContext: traceContext
        ))
    }

    func saveImportSession(
        from result: ImportBatchCopyCycleResult,
        request: ImportEntryRequest
    ) async throws {
        try await saveImportSession(
            request: request,
            completed: result.completed,
            failed: result.failed,
            total: result.total,
            currentPath: result.currentPath
        )
    }

    func saveImportSession(
        request: ImportEntryRequest,
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String
    ) async throws {
        guard selectedStorageMode == .copy else { return }
        let session = ImportBatchSessionSnapshot(
            repoPath: request.repoPath,
            storageMode: selectedStorageMode,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            items: progressItems()
        )
        try await sessionStore.saveSession(session)
    }

    func initialImportSessionFailure(
        request: ImportEntryRequest,
        total: Int,
        currentPath: String
    ) async -> ImportBatchSessionStoreError? {
        do {
            try await saveImportSession(
                request: request,
                completed: 0,
                failed: 0,
                total: total,
                currentPath: currentPath
            )
            return nil
        } catch {
            return normalizedImportSessionError(error, operation: .save)
        }
    }

    func clearImportSessionFailure(
        shouldClear: Bool,
        repoPath: String
    ) async -> ImportBatchSessionStoreError? {
        guard shouldClear else { return nil }
        do {
            try await sessionStore.clearSession(repoPath: repoPath)
            return nil
        } catch {
            return normalizedImportSessionError(error, operation: .clear)
        }
    }

    private func normalizedImportSessionError(
        _ error: Error,
        operation: ImportBatchSessionStoreError.Operation
    ) -> ImportBatchSessionStoreError {
        (error as? ImportBatchSessionStoreError) ?? .io(operation: operation, code: 0)
    }
}
