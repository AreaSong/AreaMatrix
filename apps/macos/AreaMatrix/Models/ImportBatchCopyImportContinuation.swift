import Foundation

@MainActor
extension ImportBatchCopyImportModel {
    func continueImportProgressQueue(
        afterRetried context: ImportProgressRetryContext,
        entry: FileEntrySnapshot,
        controlState: ImportProgressControlState,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchImportResult? {
        guard let request else { return nil }
        let retryRowIndex = rows.firstIndex { $0.sourcePath == context.sourcePath }
        if let retryRowIndex {
            setStatus(.imported, for: rows[retryRowIndex].id)
        }
        let retryPath = retryRowIndex.map { targetRelativePath(for: rows[$0], destination: selectedDestination) }
            ?? entry.path
        reportProgress(progressSnapshotAfterRetry(entry: entry, retryPath: retryPath))
        return await importRemainingFiles(
            request: request,
            retryEntry: entry,
            retryRowIndex: retryRowIndex,
            retryPath: retryPath,
            controlState: controlState,
            reportProgress: reportProgress
        )
    }

    func stoppedProgressSnapshot(currentPath: String) -> ImportBatchProgressSnapshot {
        let importedCount = rows.filter { if case .imported = $0.status { return true }; return false }.count
        let failedCount = rows.filter { if case .error = $0.status { return true }; return false }.count
        let skippedCount = importableRows.count
        return ImportBatchProgressSnapshot(
            completed: importedCount,
            failed: failedCount,
            total: importedCount + failedCount + skippedCount,
            remaining: 0,
            currentPath: currentPath,
            skipped: skippedCount,
            pending: pendingICloudCount,
            items: progressItems()
        )
    }

    func retryContext(
        for row: ImportBatchCopyImportRow,
        request: ImportEntryRequest
    ) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: request.repoPath,
            sourcePath: row.sourcePath,
            storageMode: selectedStorageMode,
            overrideCategory: row.resolvedCategory(for: selectedDestination) ?? "inbox",
            overrideFilename: row.resolvedIncomingName,
            duplicateStrategy: ImportProgressDuplicateStrategy(coreStrategy: duplicateStrategy(for: row))
        )
    }

    func shouldClearCategoryOverride(_ category: String, for row: ImportBatchCopyImportRow) -> Bool {
        category.isEmpty
            || category == row.defaultCategory(for: selectedDestination)
            || category == "repo root"
    }

    var pendingICloudCount: Int {
        rows.filter { row in
            if case .iCloudPlaceholder = row.status { return true }
            if case .skippedICloud = row.status { return true }
            return false
        }.count
    }

    func mapPreviewRows(
        _ previewRows: [ImportBatchPreviewRow],
        request: ImportEntryRequest?
    ) -> [ImportBatchCopyImportRow] {
        guard let request else { return [] }

        return previewRows.compactMap { row in
            guard let sourceURL = sourceURL(for: row, request: request) else { return nil }
            return ImportBatchCopyImportRow(
                originalName: row.originalName,
                sourcePath: row.sourcePath,
                sourceURL: sourceURL,
                sizeBytes: row.sizeBytes,
                predictedCategory: row.predictedCategory,
                categoryOverride: nil,
                suggestedName: row.suggestedName,
                status: copyStatus(from: row.status)
            )
        }
    }

    private func importRemainingFiles(
        request: ImportEntryRequest,
        retryEntry: FileEntrySnapshot,
        retryRowIndex: Int?,
        retryPath: String,
        controlState: ImportProgressControlState,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchImportResult {
        let total = importableRows.count + 1
        var completed = 1
        var failed = 0
        var succeededEntries = [retryEntry]
        var lastImportedPath = retryPath
        var didStopAfterCurrentFile = false
        clearLastFailureMapping()

        for index in rows.indices where rows[index].status.isReady {
            let cycle = await runImportCycle(
                at: index,
                request: request,
                selectedDestination: selectedDestination,
                completed: completed,
                failed: failed,
                total: total,
                reportProgress: reportProgress
            )
            completed = cycle.completed
            failed = cycle.failed
            lastImportedPath = cycle.lastImportedPath ?? lastImportedPath
            if let entry = cycle.entry {
                succeededEntries.append(entry)
            }
            reportProgress(cycle.progress.withItems(progressItems()))
            if cycle.stoppedForDuplicate {
                return continuedImportResult(
                    entries: succeededEntries,
                    failed: failed,
                    total: total,
                    lastImportedPath: lastImportedPath,
                    didStopAfterCurrentFile: false
                )
            }
            if controlState.isStopAfterCurrentFileRequested {
                controlState.markStoppedAfterCurrentFile()
                didStopAfterCurrentFile = true
                reportProgress(stoppedProgressSnapshot(currentPath: lastImportedPath))
                break
            }
        }

        markSkippedDuplicates(excluding: retryRowIndex)
        finishImportedStatus(successful: completed, failed: failed)
        return continuedImportResult(
            entries: succeededEntries,
            failed: failed,
            total: total,
            lastImportedPath: lastImportedPath,
            didStopAfterCurrentFile: didStopAfterCurrentFile
        )
    }

    private func progressSnapshotAfterRetry(
        entry: FileEntrySnapshot,
        retryPath: String
    ) -> ImportBatchProgressSnapshot {
        let remaining = rows.filter(\.status.isReady).count
        return ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 1 + remaining,
            remaining: remaining,
            currentPath: retryPath.isEmpty ? entry.path : retryPath,
            items: progressItems()
        )
    }

    private func continuedImportResult(
        entries: [FileEntrySnapshot],
        failed: Int,
        total: Int,
        lastImportedPath: String,
        didStopAfterCurrentFile: Bool
    ) -> ImportBatchImportResult {
        ImportBatchImportResult(
            succeededEntries: entries,
            failedCount: failed,
            previewErrorCount: 0,
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: unresolvedDuplicateCount,
            skippedDuplicateCount: skippedDuplicateCount,
            pendingICloudCount: pendingICloudCount,
            didStopAfterCurrentFile: didStopAfterCurrentFile
        )
    }

    private func sourceURL(
        for row: ImportBatchPreviewRow,
        request: ImportEntryRequest
    ) -> URL? {
        request.urls.first { url in
            (url.path as NSString).abbreviatingWithTildeInPath == row.sourcePath
        }
    }

    private func copyStatus(from previewStatus: ImportBatchPreviewRowStatus) -> ImportBatchCopyImportRowStatus {
        switch previewStatus {
        case .loading:
            return .loading
        case .ready(let reasonLabel):
            return .ready(reasonLabel: reasonLabel)
        case .duplicate(let existingPath, _):
            return .duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false)
        case .nameConflict(let existingPath, _):
            return .nameConflict(existingPath: existingPath, resolution: .keepBoth)
        case .iCloudPlaceholder(let path, let message):
            return .iCloudPlaceholder(path: path, message: message)
        case .blocked(let message):
            return .blocked(message)
        case .error(let message):
            return .error(message)
        }
    }
}
