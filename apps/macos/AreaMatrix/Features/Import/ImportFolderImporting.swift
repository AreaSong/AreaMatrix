import Foundation

@MainActor
extension ImportFolderPreviewModel {
    func importReadyFiles(
        controlState: ImportProgressControlState? = nil,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void = { _ in }
    ) async -> ImportBatchImportResult? {
        guard let request, importDisabledReason == nil else { return nil }

        let readyRowIDs = Set(importableRows.map(\.id))
        let total = importableRows.count
        let initialPreviewErrorCount = failedCount
        let storageMode = selectedStorageMode
        let actionContext = CoreImportTraceContext.operation(
            actionID: "repository.import.folder.confirmed",
            componentID: "macos.import.folder"
        )
        clearLastFailureMapping()
        await actionLogger.recordUIAction(traceContext: actionContext)
        let state = await importReadyFolderRows(
            input: ImportFolderImportRunInput(
                readyRowIDs: readyRowIDs,
                request: request,
                storageMode: storageMode,
                total: total,
                traceID: actionContext.traceID
            ),
            controlState: controlState,
            reportProgress: reportProgress
        )

        return ImportBatchImportResult(
            succeededEntries: state.succeededEntries,
            failedCount: state.failed,
            previewErrorCount: initialPreviewErrorCount,
            total: total,
            lastImportedPath: state.lastImportedPath,
            pendingDuplicateCount: 0,
            skippedDuplicateCount: skippedDuplicateCount,
            pendingICloudCount: pendingICloudCount,
            didStopAfterCurrentFile: state.didStopAfterCurrentFile,
            fatalRetryContext: state.fatalRetryContext
        )
    }

    private func importReadyFolderRows(
        input: ImportFolderImportRunInput,
        controlState: ImportProgressControlState?,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportFolderImportRunState {
        var state = ImportFolderImportRunState()
        for index in rows.indices where input.readyRowIDs.contains(rows[index].id) {
            let traceContext = CoreImportTraceContext.operation(
                traceID: input.traceID,
                actionID: "repository.import.confirmed",
                componentID: "macos.import.folder"
            )
            let cycleInput = ImportFolderImportCycleInput(
                rowIndex: index,
                request: input.request,
                storageMode: input.storageMode,
                completed: state.completed,
                failed: state.failed,
                total: input.total,
                traceContext: traceContext
            )
            let cycle = await runFolderImportCycle(input: cycleInput)
            updateFolderImportRunState(
                &state,
                cycle: cycle,
                input: cycleInput
            )
            reportProgress(cycle.progress.withItems(progressItems()))
            if shouldStopFolderImportRun(&state, controlState: controlState) {
                break
            }
        }
        return state
    }

    private func updateFolderImportRunState(
        _ state: inout ImportFolderImportRunState,
        cycle: ImportBatchCopyCycleResult,
        input: ImportFolderImportCycleInput
    ) {
        state.completed = cycle.completed
        state.failed = cycle.failed
        state.lastImportedPath = cycle.lastImportedPath ?? state.lastImportedPath
        if let entry = cycle.entry {
            state.succeededEntries.append(entry)
        }
        if cycle.stoppedForQueue {
            state.fatalRetryContext = retryContext(
                for: rows[input.rowIndex],
                request: input.request,
                storageMode: input.storageMode,
                traceContext: input.traceContext
            )
        }
    }

    private func shouldStopFolderImportRun(
        _ state: inout ImportFolderImportRunState,
        controlState: ImportProgressControlState?
    ) -> Bool {
        if state.fatalRetryContext != nil { return true }
        guard controlState?.isStopAfterCurrentFileRequested == true else { return false }
        controlState?.markStoppedAfterCurrentFile()
        state.didStopAfterCurrentFile = true
        return true
    }

    func runFolderImportCycle(input: ImportFolderImportCycleInput) async -> ImportBatchCopyCycleResult {
        let rowIndex = input.rowIndex
        let row = rows[rowIndex]
        let currentPath = targetRelativePath(for: row)
        updateRowStatus(at: rowIndex, status: .importing(input.storageMode))

        do {
            let entry = try await importer.importBatchFile(request: CoreBatchImportRequest(
                repoPath: input.request.repoPath,
                sourceURL: row.fileURL,
                storageMode: input.storageMode,
                destination: modelDestination,
                suggestedCategory: suggestedCategory(for: row, request: input.request),
                overrideFilename: row.resolvedIncomingName,
                duplicateStrategy: duplicateStrategy(for: row),
                traceContext: input.traceContext
            ))
            updateRowStatus(at: rowIndex, status: .imported(input.storageMode))
            updateRowCommitState(at: rowIndex, commitState: entry.importCommitState)
            return .success(
                entry: entry,
                completed: input.completed + 1,
                failed: input.failed,
                total: input.total,
                currentPath: currentPath
            )
        } catch {
            let mapping = await mapImportError(error)
            recordLastFailureMapping(mapping)
            updateRowStatus(at: rowIndex, status: .error(.localized(mapping.userMessageDescriptor)))
            return .failure(
                completed: input.completed,
                failed: input.failed + 1,
                total: input.total,
                currentPath: currentPath,
                stoppedForQueue: mapping.recoverability == .fatal
            )
        }
    }

    func retryContext(
        for row: ImportFolderPreviewRow,
        request: ImportEntryRequest,
        storageMode: ImportSingleFileStorageMode? = nil,
        traceContext: CoreImportTraceContext? = nil
    ) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: request.repoPath,
            sourcePath: row.fileURL.path,
            storageMode: storageMode ?? selectedStorageMode,
            overrideCategory: retryCategory(for: row),
            overrideFilename: row.resolvedIncomingName,
            duplicateStrategy: ImportProgressDuplicateStrategy(coreStrategy: duplicateStrategy(for: row)),
            traceID: traceContext?.traceID,
            operationID: traceContext?.operationID
        )
    }

    private func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }

    private func suggestedCategory(for row: ImportFolderPreviewRow, request _: ImportEntryRequest) -> String? {
        switch modelDestination {
        case .autoClassify:
            row.predictedCategory
        case let .category(slug):
            slug
        case .repositoryRoot:
            nil
        }
    }

    private var modelDestination: ImportEntryDestination {
        selectedDestination.entryDestination
    }

    private func duplicateStrategy(for row: ImportFolderPreviewRow) -> ImportDuplicateStrategySnapshot {
        if let duplicateResolution = row.duplicateResolution {
            return duplicateResolution.duplicateStrategy
        }
        if let nameConflictResolution = row.nameConflictResolution {
            if nameConflictResolution.isReplace {
                return .overwrite
            }
            return .keepBoth
        }
        return .ask
    }

    private func retryCategory(for row: ImportFolderPreviewRow) -> String {
        if let category = retryCategoryValue(for: row), !category.isEmpty {
            return category
        }
        return "inbox"
    }

    private func retryCategoryValue(for row: ImportFolderPreviewRow) -> String? {
        switch modelDestination {
        case .autoClassify:
            row.predictedCategory
        case let .category(slug):
            slug
        case .repositoryRoot:
            nil
        }
    }

    var skippedDuplicateCount: Int {
        rows.filter { row in
            if case .skippedDuplicate = row.status { return true }
            if row.duplicateResolution == .skip { return true }
            return false
        }.count
    }

    var pendingICloudCount: Int {
        rows.filter { row in
            if case .iCloudPlaceholder = row.status { return true }
            if case .skippedICloud = row.status { return true }
            return false
        }.count
    }

    func progressItems() -> [ImportBatchProgressSnapshot.Item] {
        rows.map { row in
            ImportBatchProgressSnapshot.Item(
                fileID: nil,
                sourcePath: row.fileURL.path,
                targetPath: targetRelativePath(for: row),
                phase: progressPhase(for: row.status),
                importCommitState: row.importCommitState,
                errorDisplayText: progressErrorDisplayText(for: row.status),
                existingRelativePath: row.existingConflictPath
            )
        }
    }

    private func progressPhase(for status: ImportFolderPreviewRowStatus) -> ImportBatchProgressSnapshot.Phase {
        switch status {
        case let .importing(mode):
            mode.folderProgressPhase
        case .imported:
            .done
        case .error:
            .failed
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked,
             .skippedDuplicate, .skippedICloud:
            .pending
        }
    }

    private func progressErrorDisplayText(for status: ImportFolderPreviewRowStatus) -> AppDisplayText? {
        guard case let .error(message) = status else { return nil }
        return message
    }
}

private extension ImportSingleFileStorageMode {
    var folderProgressPhase: ImportBatchProgressSnapshot.Phase {
        switch self {
        case .copy:
            .copying
        case .move:
            .moving
        case .indexOnly:
            .writingIndex
        }
    }
}
