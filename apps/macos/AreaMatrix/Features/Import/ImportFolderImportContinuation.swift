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
            updateRowCommitState(at: retryRowIndex, commitState: entry.importCommitState)
        }
        let retryPath = retryRowIndex.map { targetRelativePath(for: rows[$0]) } ?? entry.path
        reportProgress(progressSnapshotAfterRetry(entry: entry, retryPath: retryPath))
        return await importRemainingFiles(
            input: ImportFolderContinuationInput(
                request: request,
                retryEntry: entry,
                retryPath: retryPath,
                traceID: context.traceID ?? UUID().uuidString.lowercased(),
                controlState: controlState
            ),
            reportProgress: reportProgress
        )
    }

    private func importRemainingFiles(
        input: ImportFolderContinuationInput,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchImportResult {
        let total = importableRows.count + 1
        var state = ImportFolderContinuationRunState(
            retryEntry: input.retryEntry,
            retryPath: input.retryPath
        )
        clearLastFailureMapping()

        for index in rows.indices where rows[index].status.importsIncomingFile {
            let cycleInput = continuationCycleInput(index: index, input: input, state: state, total: total)
            let cycle = await runFolderImportCycle(input: cycleInput)
            state.absorb(cycle)
            reportProgress(cycle.progress.withItems(progressItems()))
            if input.controlState.isStopAfterCurrentFileRequested {
                input.controlState.markStoppedAfterCurrentFile()
                state.didStopAfterCurrentFile = true
                break
            }
            if cycle.stoppedForQueue {
                return continuedImportResult(
                    entries: state.succeededEntries,
                    failed: state.failed,
                    total: total,
                    lastImportedPath: state.lastImportedPath,
                    didStopAfterCurrentFile: state.didStopAfterCurrentFile,
                    fatalRetryContext: retryContext(
                        for: rows[index],
                        request: input.request,
                        storageMode: selectedStorageMode,
                        traceContext: cycleInput.traceContext
                    )
                )
            }
        }

        return continuedImportResult(
            entries: state.succeededEntries,
            failed: state.failed,
            total: total,
            lastImportedPath: state.lastImportedPath,
            didStopAfterCurrentFile: state.didStopAfterCurrentFile
        )
    }

    private func continuationCycleInput(
        index: Int,
        input: ImportFolderContinuationInput,
        state: ImportFolderContinuationRunState,
        total: Int
    ) -> ImportFolderImportCycleInput {
        ImportFolderImportCycleInput(
            rowIndex: index,
            request: input.request,
            storageMode: selectedStorageMode,
            completed: state.completed,
            failed: state.failed,
            total: total,
            traceContext: CoreImportTraceContext.operation(
                traceID: input.traceID,
                actionID: "repository.import.confirmed",
                componentID: "macos.import.folder"
            )
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
        didStopAfterCurrentFile: Bool,
        fatalRetryContext: ImportProgressRetryContext? = nil
    ) -> ImportBatchImportResult {
        ImportBatchImportResult(
            succeededEntries: entries,
            failedCount: failed,
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: 0,
            skippedDuplicateCount: skippedDuplicateCount,
            pendingICloudCount: pendingICloudCount,
            didStopAfterCurrentFile: didStopAfterCurrentFile,
            fatalRetryContext: fatalRetryContext
        )
    }
}

private struct ImportFolderContinuationInput {
    let request: ImportEntryRequest
    let retryEntry: FileEntrySnapshot
    let retryPath: String
    let traceID: String
    let controlState: ImportProgressControlState
}

private struct ImportFolderContinuationRunState {
    var completed = 1
    var failed = 0
    var succeededEntries: [FileEntrySnapshot]
    var lastImportedPath: String
    var didStopAfterCurrentFile = false

    init(retryEntry: FileEntrySnapshot, retryPath: String) {
        succeededEntries = [retryEntry]
        lastImportedPath = retryPath
    }

    mutating func absorb(_ cycle: ImportBatchCopyCycleResult) {
        completed = cycle.completed
        failed = cycle.failed
        lastImportedPath = cycle.lastImportedPath ?? lastImportedPath
        if let entry = cycle.entry {
            succeededEntries.append(entry)
        }
    }
}
