import Foundation

struct ImportProgressRouteState: Equatable {
    enum Status: Equatable {
        case running
        case failed(CoreErrorMappingSnapshot)
    }

    var sourceOpening: RepositoryOpeningResult
    var status: Status
    var completed: Int
    var failed: Int
    var remaining: Int
    var currentPath: String
    var skipped: Int
    var pending: Int
    var items: [ImportBatchProgressSnapshot.Item]
    var retryContext: ImportProgressRetryContext?
    var recoveryCheck: ImportProgressRecoveryCheckState
    var diagnostics: ImportProgressDiagnosticsState
    var stopState: ImportProgressStopState
    var isRepositoryFinderAvailable: Bool

    init(
        sourceOpening: RepositoryOpeningResult,
        currentPath: String,
        remaining: Int = 1,
        isRepositoryFinderAvailable: Bool = true
    ) {
        self.sourceOpening = sourceOpening
        status = .running
        completed = 0
        failed = 0
        self.remaining = remaining
        self.currentPath = currentPath
        skipped = 0
        pending = 0
        items = [
            ImportBatchProgressSnapshot.Item(
                fileID: nil,
                sourcePath: currentPath,
                targetPath: currentPath,
                phase: .copying,
                errorMessage: nil
            )
        ]
        retryContext = nil
        recoveryCheck = .unavailable
        diagnostics = .idle
        stopState = .idle
        self.isRepositoryFinderAvailable = isRepositoryFinderAvailable
    }

    init(
        sourceOpening: RepositoryOpeningResult,
        currentPath: String,
        storageMode: ImportSingleFileStorageMode,
        retryContext: ImportProgressRetryContext? = nil,
        isRepositoryFinderAvailable: Bool = true
    ) {
        self.sourceOpening = sourceOpening
        status = .running
        completed = 0
        failed = 0
        remaining = 1
        self.currentPath = currentPath
        skipped = 0
        pending = 0
        items = [
            ImportBatchProgressSnapshot.Item(
                fileID: nil,
                sourcePath: currentPath,
                targetPath: currentPath,
                phase: storageMode.progressPhase,
                errorMessage: nil
            )
        ]
        self.retryContext = retryContext
        recoveryCheck = .unavailable
        diagnostics = .idle
        stopState = .idle
        self.isRepositoryFinderAvailable = isRepositoryFinderAvailable
    }

    init(
        sourceOpening: RepositoryOpeningResult,
        currentPath: String,
        status: Status,
        completed: Int,
        failed: Int,
        remaining: Int,
        skipped: Int = 0,
        pending: Int = 0,
        items: [ImportBatchProgressSnapshot.Item] = [],
        retryContext: ImportProgressRetryContext? = nil,
        recoveryCheck: ImportProgressRecoveryCheckState? = nil,
        diagnostics: ImportProgressDiagnosticsState = .idle,
        stopState: ImportProgressStopState = .idle,
        isRepositoryFinderAvailable: Bool = true
    ) {
        self.sourceOpening = sourceOpening
        self.status = status
        self.completed = completed
        self.failed = failed
        self.remaining = remaining
        self.currentPath = currentPath
        self.skipped = skipped
        self.pending = pending
        self.items = Self.resolvedItems(
            from: items,
            currentPath: currentPath,
            status: status,
            completed: completed,
            failed: failed
        )
        self.retryContext = retryContext
        self.recoveryCheck = recoveryCheck ?? Self.initialRecoveryCheck(status: status, retryContext: retryContext)
        self.diagnostics = diagnostics
        self.stopState = stopState
        self.isRepositoryFinderAvailable = isRepositoryFinderAvailable
    }

    var repoPath: String {
        sourceOpening.config.repoPath
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping) = status else { return nil }
        return mapping
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    var canRetryCurrentItem: Bool {
        guard retryContext?.storageMode.isImportProgressRetryable == true else { return false }
        if case .retryAllowed = recoveryCheck { return true }
        return false
    }

    var toolbarText: String {
        L10n.format("import.progress.toolbar", completed, completed + failed + remaining)
    }

    var bannerText: String {
        if let errorMapping {
            return errorMapping.userMessage
        }
        let extras = resultExtras
        return extras.isEmpty
            ? L10n.format("import.progress.summary", completed, failed, remaining)
            : L10n.format("import.progress.summaryWithExtras", completed, failed, remaining, extras)
    }

    var titleText: String {
        if isFailed {
            return L10n.string("import.progress.paused")
        }
        return L10n.plural("import.progress.importing-files", count: total)
    }

    var detailsButtonTitle: String {
        L10n.string("View details")
    }

    func withRecoveryCheck(_ recoveryCheck: ImportProgressRecoveryCheckState) -> ImportProgressRouteState {
        replacing(recoveryCheck: recoveryCheck)
    }

    func withDiagnostics(_ diagnostics: ImportProgressDiagnosticsState) -> ImportProgressRouteState {
        replacing(diagnostics: diagnostics)
    }

    func withStopState(_ stopState: ImportProgressStopState) -> ImportProgressRouteState {
        replacing(stopState: stopState)
    }

    private var total: Int {
        completed + failed + remaining + skipped + pending
    }

    private var resultExtras: String {
        var parts: [String] = []
        if skipped > 0 {
            parts.append(L10n.format("import.progress.skipped", skipped))
        }
        if pending > 0 {
            parts.append(L10n.format("import.progress.pendingDownload", pending))
        }
        return parts.joined(separator: "，")
    }

    private static func resolvedItems(
        from items: [ImportBatchProgressSnapshot.Item],
        currentPath: String,
        status: Status,
        completed: Int,
        failed: Int
    ) -> [ImportBatchProgressSnapshot.Item] {
        guard !items.isEmpty else {
            return [fallbackItem(
                currentPath: currentPath,
                status: status,
                completed: completed,
                failed: failed
            )]
        }
        return items
    }

    private static func fallbackItem(
        currentPath: String,
        status: Status,
        completed: Int,
        failed: Int
    ) -> ImportBatchProgressSnapshot.Item {
        ImportBatchProgressSnapshot.Item(
            fileID: nil,
            sourcePath: currentPath,
            targetPath: currentPath,
            phase: fallbackPhase(status: status, completed: completed, failed: failed),
            errorMessage: fallbackErrorMessage(status: status)
        )
    }

    private static func fallbackPhase(
        status: Status,
        completed: Int,
        failed: Int
    ) -> ImportBatchProgressSnapshot.Phase {
        switch status {
        case .running:
            completed > 0 ? .done : .copying
        case .failed:
            failed > 0 ? .failed : .pending
        }
    }

    private static func fallbackErrorMessage(status: Status) -> String? {
        guard case let .failed(mapping) = status else { return nil }
        return mapping.userMessage
    }

    private static func initialRecoveryCheck(
        status: Status,
        retryContext: ImportProgressRetryContext?
    ) -> ImportProgressRecoveryCheckState {
        guard case .failed = status, retryContext?.storageMode.isImportProgressRetryable == true else {
            return .unavailable
        }
        return .checking
    }

    private func replacing(
        recoveryCheck: ImportProgressRecoveryCheckState? = nil,
        diagnostics: ImportProgressDiagnosticsState? = nil,
        stopState: ImportProgressStopState? = nil
    ) -> ImportProgressRouteState {
        ImportProgressRouteState(
            sourceOpening: sourceOpening,
            currentPath: currentPath,
            status: status,
            completed: completed,
            failed: failed,
            remaining: remaining,
            skipped: skipped,
            pending: pending,
            items: items,
            retryContext: retryContext,
            recoveryCheck: recoveryCheck ?? self.recoveryCheck,
            diagnostics: diagnostics ?? self.diagnostics,
            stopState: stopState ?? self.stopState,
            isRepositoryFinderAvailable: isRepositoryFinderAvailable
        )
    }
}

extension ImportProgressRouteState {
    var progressSnapshot: ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: remaining,
            currentPath: currentPath,
            skipped: skipped,
            pending: pending,
            items: items
        )
    }

    var retryStatusText: String {
        switch recoveryCheck {
        case .unavailable:
            return L10n.string("Retry is unavailable for this item.")
        case .checking:
            return L10n.string("Checking recovery state...")
        case let .retryAllowed(report):
            guard let report, report.hasVisibleDetails else {
                return L10n.string("Recovery state checked. Current item can be retried.")
            }
            return L10n.format(
                "Recovery checked: cleaned %d, reverted %d.",
                report.cleanedStagingFiles,
                report.revertedStagingDbRows
            )
        case let .retryBlocked(message, _):
            return message
        }
    }

    var resultSummaryText: String {
        L10n.format(
            "Imported %d, failed %d, stopped %d, pending %d.",
            completed,
            failed,
            skipped,
            remaining + pending
        )
    }

    var recoveryCheckTaskID: String {
        switch recoveryCheck {
        case .checking:
            "checking-\(retryContext?.sourcePath ?? currentPath)"
        case .unavailable:
            "unavailable"
        case .retryAllowed:
            "allowed-\(retryContext?.sourcePath ?? currentPath)"
        case .retryBlocked:
            "blocked-\(retryContext?.sourcePath ?? currentPath)"
        }
    }
}

private extension ImportSingleFileStorageMode {
    var isImportProgressRetryable: Bool {
        true
    }

    var progressPhase: ImportBatchProgressSnapshot.Phase {
        switch self {
        case .move:
            .moving
        case .indexOnly:
            .writingIndex
        case .copy:
            .copying
        }
    }
}
