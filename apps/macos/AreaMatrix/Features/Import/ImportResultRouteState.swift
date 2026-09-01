import Foundation

struct ImportResultRouteState: Equatable {
    enum ChangeLogState: Equatable {
        case notLoaded
        case loading
        case loaded([ChangeLogEntrySnapshot])
        case failed(CoreErrorMappingSnapshot)
    }

    enum ExportState: Equatable {
        case idle
        case confirmingPrivacy
        case exported(String)
        case failed(LocalizedMessage)
    }

    enum ItemStatus: String, Equatable, Hashable {
        case imported = "Imported"
        case sourceRetained = "Source retained"
        case skipped = "Skipped"
        case failed = "Failed"
        case pending = "Pending"

        var displayName: String {
            switch self {
            case .imported: L10n.string("Imported")
            case .sourceRetained: L10n.string("import.result.source-retained.status")
            case .skipped: L10n.string("Skipped")
            case .failed: L10n.string("Failed")
            case .pending: L10n.string("Pending")
            }
        }
    }

    struct Item: Identifiable, Equatable {
        var fileID: Int64?
        var sourcePath: String
        var targetPath: String
        var status: ItemStatus
        var reason: String
        var retryContext: ImportProgressRetryContext?
        var existingRelativePath: String?

        var id: String {
            sourcePath + "|" + targetPath + "|" + status.rawValue
        }

        var sanitizedSourcePath: String {
            ImportResultRouteState.sanitizedPathDisplay(sourcePath)
        }

        var sanitizedTargetPath: String {
            ImportResultRouteState.sanitizedPathDisplay(targetPath)
        }

        var canShowExistingFile: Bool {
            status == .skipped && existingRelativePath?.isEmpty == false
        }

        var canReviewTagSuggestions: Bool {
            (status == .imported || status == .sourceRetained) && fileID != nil
        }
    }

    var sourceOpening: RepositoryOpeningResult
    var imported: Int
    var failed: Int
    var stopped: Int
    var pending: Int
    var currentPath: String
    var items: [Item]
    var isRetryingFailedItems: Bool
    var changeLog: ChangeLogState
    var exportState: ExportState
    var shouldClearInterruptedSessionOnDone: Bool

    init(sourceOpening: RepositoryOpeningResult, progress: ImportBatchProgressSnapshot) {
        self.sourceOpening = sourceOpening
        imported = progress.completed
        failed = progress.failed
        stopped = progress.skipped
        pending = progress.remaining + progress.pending
        currentPath = progress.currentPath
        isRetryingFailedItems = false
        changeLog = .notLoaded
        exportState = .idle
        shouldClearInterruptedSessionOnDone = false
        items = Self.resultItems(
            from: progress.items,
            repoPath: sourceOpening.config.repoPath,
            currentPath: progress.currentPath,
            counts: ImportResultCounts(
                imported: progress.completed,
                failed: progress.failed,
                stopped: progress.skipped,
                pending: progress.remaining + progress.pending
            )
        )
    }

    init(sourceOpening: RepositoryOpeningResult, progressState: ImportProgressRouteState) {
        self.init(sourceOpening: sourceOpening, progress: progressState.progressSnapshot)
    }

    init(
        sourceOpening: RepositoryOpeningResult,
        imported: Int,
        failed: Int,
        stopped: Int,
        pending: Int,
        currentPath: String,
        items: [Item],
        isRetryingFailedItems: Bool = false,
        changeLog: ChangeLogState = .notLoaded,
        exportState: ExportState = .idle,
        shouldClearInterruptedSessionOnDone: Bool = false
    ) {
        self.sourceOpening = sourceOpening
        self.imported = imported
        self.failed = failed
        self.stopped = stopped
        self.pending = pending
        self.currentPath = currentPath
        self.items = items
        self.isRetryingFailedItems = isRetryingFailedItems
        self.changeLog = changeLog
        self.exportState = exportState
        self.shouldClearInterruptedSessionOnDone = shouldClearInterruptedSessionOnDone
    }

    var summaryText: String {
        L10n.format("import.result.summary", imported, stopped, failed, pending)
    }

    var resultSummaryText: String {
        L10n.format("onboarding.importResult.summary", imported, failed, stopped, pending)
    }

    var canRetryFailedItems: Bool {
        !isRetryingFailedItems && items.contains { $0.retryContext?.storageMode == .copy && $0.status == .failed }
    }

    private static func resultItems(
        from progressItems: [ImportBatchProgressSnapshot.Item],
        repoPath: String,
        currentPath: String,
        counts: ImportResultCounts
    ) -> [Item] {
        guard !progressItems.isEmpty else {
            return [fallbackItem(currentPath: currentPath, counts: counts)]
        }
        return progressItems.map { item in
            Item(
                fileID: item.fileID,
                sourcePath: item.sourcePath,
                targetPath: item.targetPath,
                status: status(for: item, stopped: counts.stopped),
                reason: reason(for: item),
                retryContext: retryContext(for: item, repoPath: repoPath),
                existingRelativePath: item.existingRelativePath
            )
        }
    }

    private static func fallbackItem(currentPath: String, counts: ImportResultCounts) -> Item {
        Item(
            fileID: nil,
            sourcePath: currentPath,
            targetPath: currentPath,
            status: fallbackStatus(
                imported: counts.imported,
                failed: counts.failed,
                stopped: counts.stopped,
                pending: counts.pending
            ),
            reason: fallbackReason(failed: counts.failed, stopped: counts.stopped, pending: counts.pending),
            retryContext: nil,
            existingRelativePath: nil
        )
    }

    private static func status(for item: ImportBatchProgressSnapshot.Item, stopped: Int) -> ItemStatus {
        if item.importCommitState.isDegraded { return .sourceRetained }
        switch item.phase {
        case .done:
            return .imported
        case .failed:
            return .failed
        case .pending:
            return stopped > 0 ? .skipped : .pending
        case .copying, .moving, .hashing, .classifying, .writingIndex:
            return .pending
        }
    }

    private static func reason(for item: ImportBatchProgressSnapshot.Item) -> String {
        if item.importCommitState.isDegraded {
            return L10n.string("import.result.source-retained.reason")
        }
        if let errorMessage = item.errorMessage {
            return errorMessage
        }
        switch item.phase {
        case .done:
            return "-"
        case .failed:
            return L10n.string("Import failed")
        case .pending:
            return L10n.string("Not imported before the queue stopped")
        case .copying, .moving, .hashing, .classifying, .writingIndex:
            return L10n.string("Import not completed")
        }
    }

    private static func fallbackStatus(
        imported: Int,
        failed: Int,
        stopped: Int,
        pending: Int
    ) -> ItemStatus {
        if failed > 0 { return .failed }
        if stopped > 0 { return .skipped }
        if pending > 0 { return .pending }
        if imported > 0 { return .imported }
        return .pending
    }

    private static func fallbackReason(failed: Int, stopped: Int, pending: Int) -> String {
        if failed > 0 { return L10n.string("Import failed") }
        if stopped > 0 { return L10n.string("Stopped before import") }
        if pending > 0 { return L10n.string("Import not completed") }
        return "-"
    }

    private static func retryContext(
        for item: ImportBatchProgressSnapshot.Item,
        repoPath: String
    ) -> ImportProgressRetryContext? {
        guard item.phase == .failed else { return nil }
        let target = splitTargetPath(item.targetPath)
        return ImportProgressRetryContext(
            repoPath: repoPath,
            sourcePath: item.sourcePath,
            storageMode: .copy,
            overrideCategory: target.category,
            overrideFilename: target.filename,
            duplicateStrategy: .ask
        )
    }

    private static func splitTargetPath(_ targetPath: String) -> (category: String, filename: String) {
        let nsPath = targetPath as NSString
        let filename = nsPath.lastPathComponent
        let category = nsPath.deletingLastPathComponent
        return (
            category: category.isEmpty || category == "." ? "inbox" : category,
            filename: filename.isEmpty ? "untitled" : filename
        )
    }

    static func sanitizedPathDisplay(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "redacted path" : ".../\(name)"
    }
}

private struct ImportResultCounts {
    var imported: Int
    var failed: Int
    var stopped: Int
    var pending: Int
}
