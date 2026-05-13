import Foundation

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
