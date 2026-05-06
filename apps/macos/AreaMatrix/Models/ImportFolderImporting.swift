import Foundation

@MainActor
extension ImportFolderPreviewModel {
    func importReadyFiles(
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void = { _ in }
    ) async -> ImportBatchImportResult? {
        guard let request, importDisabledReason == nil else { return nil }

        let readyRowIDs = Set(importableRows.map(\.id))
        let total = importableRows.count
        let initialPreviewErrorCount = failedCount
        let storageMode = selectedStorageMode
        var completed = 0
        var failed = 0
        var succeededEntries: [FileEntrySnapshot] = []
        var lastImportedPath = ""
        clearLastFailureMapping()

        for index in rows.indices where readyRowIDs.contains(rows[index].id) {
            let cycle = await runFolderImportCycle(
                at: index,
                request: request,
                storageMode: storageMode,
                completed: completed,
                failed: failed,
                total: total
            )
            completed = cycle.completed
            failed = cycle.failed
            lastImportedPath = cycle.lastImportedPath ?? lastImportedPath
            if let entry = cycle.entry {
                succeededEntries.append(entry)
            }
            reportProgress(cycle.progress)
        }

        return ImportBatchImportResult(
            succeededEntries: succeededEntries,
            failedCount: failed,
            previewErrorCount: initialPreviewErrorCount,
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: 0,
            skippedDuplicateCount: 0,
            pendingICloudCount: iCloudPlaceholderCount
        )
    }

    private func runFolderImportCycle(
        at rowIndex: Int,
        request: ImportEntryRequest,
        storageMode: ImportSingleFileStorageMode,
        completed: Int,
        failed: Int,
        total: Int
    ) async -> ImportBatchCopyCycleResult {
        let row = rows[rowIndex]
        let currentPath = targetRelativePath(for: row)
        updateRowStatus(at: rowIndex, status: .importing(storageMode))

        do {
            let entry = try await importer.importBatchFile(
                repoPath: request.repoPath,
                sourceURL: row.fileURL,
                storageMode: storageMode,
                destination: request.destination,
                suggestedCategory: suggestedCategory(for: row, request: request),
                overrideFilename: row.suggestedName,
                duplicateStrategy: .ask
            )
            updateRowStatus(at: rowIndex, status: .imported(storageMode))
            return .success(
                entry: entry,
                completed: completed + 1,
                failed: failed,
                total: total,
                currentPath: currentPath
            )
        } catch {
            let mapping = await mapImportError(error)
            recordLastFailureMapping(mapping)
            updateRowStatus(at: rowIndex, status: .error(mapping.userMessage))
            return .failure(
                completed: completed,
                failed: failed + 1,
                total: total,
                currentPath: currentPath
            )
        }
    }

    private func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func suggestedCategory(for row: ImportFolderPreviewRow, request: ImportEntryRequest) -> String? {
        switch request.destination {
        case .autoClassify:
            return row.predictedCategory
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return nil
        }
    }
}
