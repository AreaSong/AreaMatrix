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
            stoppedForQueue: false
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
            stoppedForQueue: stoppedForQueue
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
            stoppedForQueue: true
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
}

struct ImportFolderImportCycleInput {
    var rowIndex: Int
    var request: ImportEntryRequest
    var storageMode: ImportSingleFileStorageMode
    var completed: Int
    var failed: Int
    var total: Int
}

struct ImportBatchRetryContinuation {
    var request: ImportEntryRequest
    var retryEntry: FileEntrySnapshot
    var retryRowIndex: Int?
    var retryPath: String
}

struct ImportBatchCopyRunState {
    var completed = 0
    var failed = 0
    var succeededEntries: [FileEntrySnapshot] = []
    var lastImportedPath = ""
    var stoppedForDuplicate = false
    var didStopAfterCurrentFile = false
    var fatalRetryContext: ImportProgressRetryContext?
}

struct ImportBatchCopyRunInput {
    var readyRowIDs: Set<ImportBatchCopyImportRow.ID>
    var request: ImportEntryRequest
    var selectedDestination: ImportBatchDestinationOption
    var total: Int
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
}

extension ImportBatchCopyImportModel {
    func importRow(
        _ row: ImportBatchCopyImportRow,
        request: ImportEntryRequest,
        selectedDestination: ImportBatchDestinationOption
    ) async throws -> FileEntrySnapshot {
        try await importer.importBatchFile(request: CoreBatchImportRequest(
            repoPath: request.repoPath,
            sourceURL: row.sourceURL,
            storageMode: selectedStorageMode,
            destination: entryDestination(for: row, selectedDestination: selectedDestination),
            suggestedCategory: row.categoryOverride ?? row.predictedCategory,
            overrideFilename: row.resolvedIncomingName,
            duplicateStrategy: duplicateStrategy(for: row)
        ))
    }

    func saveImportSession(
        from result: ImportBatchCopyCycleResult,
        request: ImportEntryRequest
    ) async {
        await saveImportSession(
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
    ) async {
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
        await sessionStore.saveSession(session)
    }
}
