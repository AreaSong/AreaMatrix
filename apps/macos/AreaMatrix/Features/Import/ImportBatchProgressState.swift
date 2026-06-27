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
        var errorMessage: String?
        var existingRelativePath: String?
        var importConflictBatch: ImportConflictBatchProgressMetadata?

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
