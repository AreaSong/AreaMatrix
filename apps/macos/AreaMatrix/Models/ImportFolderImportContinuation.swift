import Foundation

@MainActor
extension ImportFolderPreviewModel: ImportProgressQueueContinuing {
    func continueImportProgressQueue(
        afterRetried context: ImportProgressRetryContext,
        entry: FileEntrySnapshot,
        controlState: ImportProgressControlState,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchImportResult? {
        guard let request else { return nil }
        let retryRowIndex = rows.firstIndex { $0.fileURL.path == context.sourcePath }
        if let retryRowIndex {
            updateRowStatus(at: retryRowIndex, status: .imported(context.storageMode))
        }
        let retryPath = retryRowIndex.map { targetRelativePath(for: rows[$0]) } ?? entry.path
        reportProgress(progressSnapshotAfterRetry(entry: entry, retryPath: retryPath))
        return await importRemainingFiles(
            request: request,
            retryEntry: entry,
            retryPath: retryPath,
            controlState: controlState,
            reportProgress: reportProgress
        )
    }

    private func importRemainingFiles(
        request: ImportEntryRequest,
        retryEntry: FileEntrySnapshot,
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

        for index in rows.indices where rows[index].status.importsIncomingFile {
            let cycle = await runFolderImportCycle(
                input: ImportFolderImportCycleInput(
                    rowIndex: index,
                    request: request,
                    storageMode: selectedStorageMode,
                    completed: completed,
                    failed: failed,
                    total: total
                )
            )
            completed = cycle.completed
            failed = cycle.failed
            lastImportedPath = cycle.lastImportedPath ?? lastImportedPath
            if let entry = cycle.entry {
                succeededEntries.append(entry)
            }
            reportProgress(cycle.progress.withItems(progressItems()))
            if controlState.isStopAfterCurrentFileRequested {
                controlState.markStoppedAfterCurrentFile()
                didStopAfterCurrentFile = true
                break
            }
            if cycle.stoppedForQueue {
                return continuedImportResult(
                    entries: succeededEntries,
                    failed: failed,
                    total: total,
                    lastImportedPath: lastImportedPath,
                    didStopAfterCurrentFile: didStopAfterCurrentFile
                )
            }
        }

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
        let remaining = rows.filter(\.status.importsIncomingFile).count
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
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: 0,
            skippedDuplicateCount: skippedDuplicateCount,
            pendingICloudCount: pendingICloudCount,
            didStopAfterCurrentFile: didStopAfterCurrentFile
        )
    }
}
