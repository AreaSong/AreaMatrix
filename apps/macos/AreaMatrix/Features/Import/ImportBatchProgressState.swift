import Foundation

struct ImportBatchProgressSnapshot: Equatable {
    enum Phase: String, Codable, Equatable {
        case pending = "Pending"
        case copying = "Copying"
        case moving = "Moving"
        case hashing = "Hashing"
        case classifying = "Classifying"
        case writingIndex = "Writing index"
        case done = "Done"
        case failed = "Failed"
    }

    struct Item: Identifiable, Equatable {
        var fileID: Int64?
        var sourcePath: String
        var targetPath: String
        var phase: Phase
        var importCommitState: CoreImportCommitState
        var errorDisplayText: AppDisplayText?
        var existingRelativePath: String?
        var importConflictBatch: ImportConflictBatchProgressMetadata?

        init(
            fileID: Int64? = nil,
            sourcePath: String,
            targetPath: String,
            phase: Phase,
            importCommitState: CoreImportCommitState = .committed,
            errorMessage: String? = nil,
            existingRelativePath: String? = nil,
            importConflictBatch: ImportConflictBatchProgressMetadata? = nil
        ) {
            self.fileID = fileID
            self.sourcePath = sourcePath
            self.targetPath = targetPath
            self.phase = phase
            self.importCommitState = importCommitState
            errorDisplayText = errorMessage.map { L10n.verbatim($0, reason: .technicalDetail) }
            self.existingRelativePath = existingRelativePath
            self.importConflictBatch = importConflictBatch
        }

        init(
            fileID: Int64? = nil,
            sourcePath: String,
            targetPath: String,
            phase: Phase,
            importCommitState: CoreImportCommitState = .committed,
            errorDisplayText: AppDisplayText?,
            existingRelativePath: String? = nil,
            importConflictBatch: ImportConflictBatchProgressMetadata? = nil
        ) {
            self.fileID = fileID
            self.sourcePath = sourcePath
            self.targetPath = targetPath
            self.phase = phase
            self.importCommitState = importCommitState
            self.errorDisplayText = errorDisplayText
            self.existingRelativePath = existingRelativePath
            self.importConflictBatch = importConflictBatch
        }

        var errorMessage: String? {
            errorDisplayText.map(L10n.resolve)
        }

        var id: String {
            sourcePath
        }
    }

    var completed: Int
    var failed: Int
    var total: Int
    var remaining: Int
    var currentPath: String
    var skipped: Int = 0
    var pending: Int = 0
    var items: [Item] = []
}

extension ImportBatchProgressSnapshot.Phase {
    var displayText: String {
        switch self {
        case .pending:
            L10n.string("Queued")
        case .copying:
            L10n.string("Copying file")
        case .moving:
            L10n.string("Moving file")
        case .hashing:
            L10n.string("Checking file")
        case .classifying:
            L10n.string("Choosing category")
        case .writingIndex:
            L10n.string("Saving index")
        case .done:
            L10n.string("Imported")
        case .failed:
            L10n.string("Failed")
        }
    }
}

struct ImportBatchImportResult: Equatable {
    var succeededEntries: [FileEntrySnapshot]
    var failedCount: Int
    var previewErrorCount: Int = 0
    var total: Int
    var lastImportedPath: String
    var pendingDuplicateCount: Int
    var skippedDuplicateCount: Int
    var pendingICloudCount: Int
    var didStopAfterCurrentFile = false
    var fatalRetryContext: ImportProgressRetryContext?

    var needsResultSummary: Bool {
        didStopAfterCurrentFile
            || failedCount > 0
            || previewErrorCount > 0
            || skippedDuplicateCount > 0
            || pendingICloudCount > 0
            || succeededEntries.contains { $0.importCommitState.isDegraded }
    }

    func progressSnapshot(currentPath fallbackPath: String) -> ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: succeededEntries.count,
            failed: failedCount + previewErrorCount,
            total: total + previewErrorCount + skippedDuplicateCount + pendingICloudCount,
            remaining: 0,
            currentPath: lastImportedPath.isEmpty ? fallbackPath : lastImportedPath,
            skipped: skippedDuplicateCount + stoppedPendingCount,
            pending: pendingICloudCount,
            items: succeededProgressItems
        )
    }

    private var stoppedPendingCount: Int {
        guard didStopAfterCurrentFile else { return 0 }
        let processed = succeededEntries.count + failedCount
        return max(total - processed, 0)
    }

    private var succeededProgressItems: [ImportBatchProgressSnapshot.Item] {
        succeededEntries.map { entry in
            ImportBatchProgressSnapshot.Item(
                fileID: entry.id,
                sourcePath: entry.sourcePath ?? entry.path,
                targetPath: entry.path,
                phase: .done,
                importCommitState: entry.importCommitState,
                errorMessage: nil
            )
        }
    }
}

extension ImportBatchProgressSnapshot {
    func withItems(_ items: [Item]) -> ImportBatchProgressSnapshot {
        var snapshot = self
        snapshot.items = items
        return snapshot
    }
}
