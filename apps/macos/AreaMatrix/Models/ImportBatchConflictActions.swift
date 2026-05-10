import Foundation

@MainActor
extension ImportBatchCopyImportModel {
    func updateDuplicateStrategy(
        for rowID: ImportBatchCopyImportRow.ID,
        strategy: ImportBatchDuplicateResolutionStrategy
    ) {
        guard canSelectDuplicateStrategy(strategy) else { return }
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case let .duplicate(existingPath, _, isReplaceConfirmed) = row.status else { return }
        setStatus(.duplicate(
            existingPath: existingPath,
            strategy: strategy,
            isReplaceConfirmed: strategy == .replace ? isReplaceConfirmed : false
        ), for: rowID)
    }

    func updateNameConflictResolution(
        for rowID: ImportBatchCopyImportRow.ID,
        resolution: ImportBatchNameConflictResolution
    ) {
        guard canSelectNameConflictResolution(resolution) else { return }
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case let .nameConflict(existingPath, _) = row.status else { return }
        setStatus(.nameConflict(existingPath: existingPath, resolution: resolution), for: rowID)
    }

    func renameIncomingFile(for rowID: ImportBatchCopyImportRow.ID, to name: String) {
        updateNameConflictResolution(for: rowID, resolution: .renameIncoming(name))
    }

    func beginReplaceConfirmation(for rowID: ImportBatchCopyImportRow.ID)
        -> SingleFileReplaceConfirmationContext? {
        clearReplaceConfirmationRecovery()
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        guard request?.allowReplaceDuringImport == true, request?.isTrashAvailable == true else { return nil }
        guard let existingPath = row.existingConflictPath else { return nil }
        return SingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: row.sourceURL.path,
            incomingSizeBytes: row.sizeBytes,
            targetRelativePath: targetRelativePath(for: row, destination: selectedDestination),
            isTrashAvailable: true
        )
    }

    func applyReplaceConfirmation(
        for rowID: ImportBatchCopyImportRow.ID,
        decision: SingleFileReplaceConfirmationDecision
    ) -> Bool {
        guard decision.understandsReplace else {
            recordReplaceConfirmationFailure("Replace 需要先勾选二次确认")
            return false
        }
        guard let expected = currentReplaceConfirmationContext(for: rowID), expected == decision.context else {
            recordReplaceConfirmationFailure("Replace confirmation context expired")
            return false
        }
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }

        switch row.status {
        case let .duplicate(existingPath, .replace, _):
            setStatus(.duplicate(
                existingPath: existingPath,
                strategy: .replace,
                isReplaceConfirmed: true
            ), for: rowID)
        case let .nameConflict(existingPath, .replace):
            setStatus(.nameConflict(
                existingPath: existingPath,
                resolution: .replace(isConfirmed: true)
            ), for: rowID)
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            recordReplaceConfirmationFailure("Replace confirmation context expired")
            return false
        }
        clearReplaceConfirmationRecovery()
        return true
    }

    func downloadICloudPlaceholderAndRetry(rowID: ImportBatchCopyImportRow.ID) async -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        guard case let .iCloudPlaceholder(path, _) = row.status else { return false }
        isICloudDownloading = true
        defer { isICloudDownloading = false }

        do {
            try await placeholderDownloader.downloadPlaceholder(at: row.sourceURL)
            setStatus(.loading, for: rowID)
            return true
        } catch {
            setStatus(.iCloudPlaceholder(
                path: path,
                message: "iCloud 下载失败：\(error.localizedDescription)"
            ), for: rowID)
            return false
        }
    }

    func downloadAllICloudPlaceholdersAndRetry() async -> Bool {
        var didDownload = false
        for row in rows {
            if case .iCloudPlaceholder = row.status {
                didDownload = await downloadICloudPlaceholderAndRetry(rowID: row.id) || didDownload
            }
        }
        return didDownload
    }

    func markICloudPlaceholderPending(rowID: ImportBatchCopyImportRow.ID) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case let .iCloudPlaceholder(path, _) = row.status else { return }
        setStatus(.skippedICloud(path: path), for: rowID)
    }

    private func canSelectDuplicateStrategy(_ strategy: ImportBatchDuplicateResolutionStrategy) -> Bool {
        strategy != .replace || replaceOptionVisibility == .enabled
    }

    private func canSelectNameConflictResolution(_ resolution: ImportBatchNameConflictResolution) -> Bool {
        !resolution.isReplace || replaceOptionVisibility == .enabled
    }

    private func currentReplaceConfirmationContext(
        for rowID: ImportBatchCopyImportRow.ID
    ) -> SingleFileReplaceConfirmationContext? {
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        guard request?.allowReplaceDuringImport == true, request?.isTrashAvailable == true else { return nil }
        guard let existingPath = row.existingConflictPath else { return nil }
        return SingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: row.sourceURL.path,
            incomingSizeBytes: row.sizeBytes,
            targetRelativePath: targetRelativePath(for: row, destination: selectedDestination),
            isTrashAvailable: true
        )
    }
}

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
