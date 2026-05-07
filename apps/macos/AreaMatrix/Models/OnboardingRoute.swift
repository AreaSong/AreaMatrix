extension OnboardingModel {
    enum Route: Equatable, Sendable {
        case loadingConfiguration
        case welcome
        case choosePath
        case validatePath
        case confirmRepositoryInitialization(RepositoryInitializationDraft)
        case initializing(RepositoryInitializationDraft)
        case initializationFailed(String, CoreErrorMappingSnapshot?, RepositoryInitializationDraft?)
        case initializationDone(RepositoryInitializationResult)
        case mainLoading(MainLoadingState)
        case mainRepoError(String, CoreErrorMappingSnapshot?)
        case dbRepairConfirm(String, ScanSessionSnapshot?, CoreErrorMappingSnapshot?)
        case settingsRepository
        case importProgress(ImportProgressRouteState)
        case importResult(ImportResultRouteState)
        case mainEmpty(RepositoryOpeningResult)
        case mainList(RepositoryOpeningResult)
        case configurationError(ConfigLoadFailure)
    }

    enum ChoosePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
    }

    enum ValidatePathAction: Equatable, Sendable {
        case continueRequested(RepoPathValidationSnapshot)
        case adoptExistingRequested(RepoPathValidationSnapshot, scanSession: ScanSessionSnapshot?)
        case openExistingRepositoryRequested(RepoPathValidationSnapshot)
    }
}

struct ImportResultRouteState: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        enum Status: String, Equatable, Hashable, Sendable {
            case imported = "Imported"
            case skipped = "Skipped"
            case failed = "Failed"
            case pending = "Pending"
        }

        var sourcePath: String
        var targetPath: String
        var status: Status
        var reason: String

        var id: String {
            sourcePath + "|" + targetPath + "|" + status.rawValue
        }
    }

    var sourceOpening: RepositoryOpeningResult
    var imported: Int
    var failed: Int
    var stopped: Int
    var pending: Int
    var currentPath: String
    var items: [Item]

    init(sourceOpening: RepositoryOpeningResult, progress: ImportBatchProgressSnapshot) {
        self.sourceOpening = sourceOpening
        imported = progress.completed
        failed = progress.failed
        stopped = progress.skipped
        pending = progress.remaining + progress.pending
        currentPath = progress.currentPath
        items = Self.resultItems(
            from: progress.items,
            currentPath: progress.currentPath,
            imported: progress.completed,
            failed: progress.failed,
            stopped: progress.skipped,
            pending: progress.remaining + progress.pending
        )
    }

    init(sourceOpening: RepositoryOpeningResult, progressState: ImportProgressRouteState) {
        self.init(sourceOpening: sourceOpening, progress: progressState.progressSnapshot)
    }

    var summaryText: String {
        "成功 \(imported) · 停止 \(stopped) · 失败 \(failed) · 待处理 \(pending)"
    }

    var resultSummaryText: String {
        "Imported \(imported), failed \(failed), stopped \(stopped), pending \(pending)."
    }

    private static func resultItems(
        from progressItems: [ImportBatchProgressSnapshot.Item],
        currentPath: String,
        imported: Int,
        failed: Int,
        stopped: Int,
        pending: Int
    ) -> [Item] {
        guard !progressItems.isEmpty else {
            return [fallbackItem(
                currentPath: currentPath,
                imported: imported,
                failed: failed,
                stopped: stopped,
                pending: pending
            )]
        }
        return progressItems.map { item in
            Item(
                sourcePath: item.sourcePath,
                targetPath: item.targetPath,
                status: status(for: item.phase, stopped: stopped),
                reason: reason(for: item)
            )
        }
    }

    private static func fallbackItem(
        currentPath: String,
        imported: Int,
        failed: Int,
        stopped: Int,
        pending: Int
    ) -> Item {
        Item(
            sourcePath: currentPath,
            targetPath: currentPath,
            status: fallbackStatus(imported: imported, failed: failed, stopped: stopped, pending: pending),
            reason: fallbackReason(failed: failed, stopped: stopped, pending: pending)
        )
    }

    private static func status(
        for phase: ImportBatchProgressSnapshot.Phase,
        stopped: Int
    ) -> Item.Status {
        switch phase {
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
        if let errorMessage = item.errorMessage {
            return errorMessage
        }
        switch item.phase {
        case .done:
            return "-"
        case .failed:
            return "Import failed"
        case .pending:
            return "Not imported before the queue stopped"
        case .copying, .moving, .hashing, .classifying, .writingIndex:
            return "Import not completed"
        }
    }

    private static func fallbackStatus(
        imported: Int,
        failed: Int,
        stopped: Int,
        pending: Int
    ) -> Item.Status {
        if failed > 0 { return .failed }
        if stopped > 0 { return .skipped }
        if pending > 0 { return .pending }
        if imported > 0 { return .imported }
        return .pending
    }

    private static func fallbackReason(failed: Int, stopped: Int, pending: Int) -> String {
        if failed > 0 { return "Import failed" }
        if stopped > 0 { return "Stopped before import" }
        if pending > 0 { return "Import not completed" }
        return "-"
    }
}
