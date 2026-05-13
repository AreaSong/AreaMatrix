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
            continuation: ImportBatchRetryContinuation(
                request: request,
                retryEntry: entry,
                retryRowIndex: retryRowIndex,
                retryPath: retryPath
            ),
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
        continuation: ImportBatchRetryContinuation,
        controlState: ImportProgressControlState,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchImportResult {
        let total = importableRows.count + 1
        var state = ImportBatchCopyRunState()
        state.completed = 1
        state.succeededEntries = [continuation.retryEntry]
        state.lastImportedPath = continuation.retryPath
        clearLastFailureMapping()

        for index in rows.indices where rows[index].status.isReady {
            let cycle = await runImportCycle(
                input: ImportBatchCopyCycleInput(
                    rowIndex: index,
                    request: continuation.request,
                    selectedDestination: selectedDestination,
                    completed: state.completed,
                    failed: state.failed,
                    total: total
                ),
                reportProgress: reportProgress
            )
            updateContinuationRunState(&state, cycle: cycle)
            reportProgress(cycle.progress.withItems(progressItems()))
            if cycle.stoppedForDuplicate {
                return continuedImportResult(from: state, total: total)
            }
            if controlState.isStopAfterCurrentFileRequested {
                controlState.markStoppedAfterCurrentFile()
                state.didStopAfterCurrentFile = true
                reportProgress(stoppedProgressSnapshot(currentPath: state.lastImportedPath))
                break
            }
        }

        markSkippedDuplicates(excluding: continuation.retryRowIndex)
        finishImportedStatus(successful: state.completed, failed: state.failed)
        return continuedImportResult(from: state, total: total)
    }

    private func updateContinuationRunState(
        _ state: inout ImportBatchCopyRunState,
        cycle: ImportBatchCopyCycleResult
    ) {
        state.completed = cycle.completed
        state.failed = cycle.failed
        state.lastImportedPath = cycle.lastImportedPath ?? state.lastImportedPath
        if let entry = cycle.entry {
            state.succeededEntries.append(entry)
        }
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

    private func continuedImportResult(
        from state: ImportBatchCopyRunState,
        total: Int
    ) -> ImportBatchImportResult {
        continuedImportResult(
            entries: state.succeededEntries,
            failed: state.failed,
            total: total,
            lastImportedPath: state.lastImportedPath,
            didStopAfterCurrentFile: state.didStopAfterCurrentFile
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
            .loading
        case let .ready(reasonLabel):
            .ready(reasonLabel: reasonLabel)
        case let .duplicate(existingPath, _):
            .duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false)
        case let .nameConflict(existingPath, _):
            .nameConflict(existingPath: existingPath, resolution: .keepBoth)
        case let .iCloudPlaceholder(path, message):
            .iCloudPlaceholder(path: path, message: message)
        case let .blocked(message):
            .blocked(message)
        case let .error(message):
            .error(message)
        }
    }

    func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    func currentDuplicateStrategiesByRowID()
        -> [ImportBatchCopyImportRow.ID: ImportBatchDuplicateResolutionStrategy] {
        rows.reduce(into: [:]) { strategies, row in
            guard let strategy = row.duplicateResolution else { return }
            strategies[row.id] = strategy
        }
    }

    func currentDuplicateStatusesByRowID() -> [ImportBatchCopyImportRow.ID: String] {
        rows.reduce(into: [:]) { duplicates, row in
            guard case let .duplicate(existingPath, _, _) = row.status else { return }
            duplicates[row.id] = existingPath
        }
    }

    func currentNameConflictResolutionsByRowID()
        -> [ImportBatchCopyImportRow.ID: ImportBatchNameConflictResolution] {
        rows.reduce(into: [:]) { resolutions, row in
            guard case let .nameConflict(_, resolution) = row.status else { return }
            resolutions[row.id] = resolution
        }
    }

    func restoreDuplicateStatus(
        for row: ImportBatchCopyImportRow,
        from duplicateStatuses: [ImportBatchCopyImportRow.ID: String]
    ) -> ImportBatchCopyImportRow {
        guard let existingPath = duplicateStatuses[row.id] else { return row }
        guard case .ready = row.status else { return row }
        var restoredRow = row
        restoredRow.status = .duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false)
        return restoredRow
    }

    func restoreDuplicateStrategy(
        for row: ImportBatchCopyImportRow,
        from strategies: [ImportBatchCopyImportRow.ID: ImportBatchDuplicateResolutionStrategy]
    ) -> ImportBatchCopyImportRow {
        guard let strategy = strategies[row.id] else { return row }
        guard case let .duplicate(existingPath, _, isReplaceConfirmed) = row.status else { return row }
        var restoredRow = row
        restoredRow.status = .duplicate(
            existingPath: existingPath,
            strategy: strategy,
            isReplaceConfirmed: strategy == .replace ? isReplaceConfirmed : false
        )
        return restoredRow
    }

    func restoreNameConflictResolution(
        for row: ImportBatchCopyImportRow,
        from resolutions: [ImportBatchCopyImportRow.ID: ImportBatchNameConflictResolution]
    ) -> ImportBatchCopyImportRow {
        guard let resolution = resolutions[row.id] else { return row }
        guard case let .nameConflict(existingPath, _) = row.status else { return row }
        var restoredRow = row
        restoredRow.status = .nameConflict(existingPath: existingPath, resolution: resolution)
        return restoredRow
    }
}
