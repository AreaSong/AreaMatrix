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
        var completed = 0
        var failed = 0
        var succeededEntries: [FileEntrySnapshot] = []
        var lastImportedPath = ""
        var didStopAfterCurrentFile = false
        var fatalRetryContext: ImportProgressRetryContext?
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
            reportProgress(cycle.progress.withItems(progressItems()))
            if cycle.stoppedForQueue {
                fatalRetryContext = retryContext(for: rows[index], request: request, storageMode: storageMode)
                break
            }
            if controlState?.isStopAfterCurrentFileRequested == true {
                controlState?.markStoppedAfterCurrentFile()
                didStopAfterCurrentFile = true
                break
            }
        }

        return ImportBatchImportResult(
            succeededEntries: succeededEntries,
            failedCount: failed,
            previewErrorCount: initialPreviewErrorCount,
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: 0,
            skippedDuplicateCount: skippedDuplicateCount,
            pendingICloudCount: pendingICloudCount,
            didStopAfterCurrentFile: didStopAfterCurrentFile,
            fatalRetryContext: fatalRetryContext
        )
    }

    func runFolderImportCycle(
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
                destination: modelDestination,
                suggestedCategory: suggestedCategory(for: row, request: request),
                overrideFilename: row.resolvedIncomingName,
                duplicateStrategy: duplicateStrategy(for: row)
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
                currentPath: currentPath,
                stoppedForQueue: mapping.recoverability == .fatal
            )
        }
    }

    func retryContext(
        for row: ImportFolderPreviewRow,
        request: ImportEntryRequest,
        storageMode: ImportSingleFileStorageMode? = nil
    ) -> ImportProgressRetryContext {
        ImportProgressRetryContext(
            repoPath: request.repoPath,
            sourcePath: row.fileURL.path,
            storageMode: storageMode ?? selectedStorageMode,
            overrideCategory: retryCategory(for: row),
            overrideFilename: row.resolvedIncomingName,
            duplicateStrategy: ImportProgressDuplicateStrategy(coreStrategy: duplicateStrategy(for: row))
        )
    }

    private func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func suggestedCategory(for row: ImportFolderPreviewRow, request: ImportEntryRequest) -> String? {
        switch modelDestination {
        case .autoClassify:
            return row.predictedCategory
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return nil
        }
    }

    private var modelDestination: ImportEntryDestination {
        selectedDestination.entryDestination
    }

    private func duplicateStrategy(for row: ImportFolderPreviewRow) -> DuplicateStrategy {
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
            return row.predictedCategory
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return nil
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
                sourcePath: row.fileURL.path,
                targetPath: targetRelativePath(for: row),
                phase: progressPhase(for: row.status),
                errorMessage: progressErrorMessage(for: row.status),
                existingRelativePath: row.existingConflictPath
            )
        }
    }

    private func progressPhase(for status: ImportFolderPreviewRowStatus) -> ImportBatchProgressSnapshot.Phase {
        switch status {
        case .importing(let mode):
            return mode.folderProgressPhase
        case .imported:
            return .done
        case .error:
            return .failed
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked,
             .skippedDuplicate, .skippedICloud:
            return .pending
        }
    }

    private func progressErrorMessage(for status: ImportFolderPreviewRowStatus) -> String? {
        guard case .error(let message) = status else { return nil }
        return message
    }
}

private extension ImportSingleFileStorageMode {
    var folderProgressPhase: ImportBatchProgressSnapshot.Phase {
        switch self {
        case .copy:
            return .copying
        case .move:
            return .moving
        case .indexOnly:
            return .writingIndex
        }
    }
}
