import Foundation

enum ImportProgressDuplicateStrategy: String, Equatable, Sendable {
    case skip
    case overwrite
    case keepBoth
    case ask

    init(coreStrategy: DuplicateStrategy) {
        switch coreStrategy {
        case .skip:
            self = .skip
        case .overwrite:
            self = .overwrite
        case .keepBoth:
            self = .keepBoth
        case .ask:
            self = .ask
        }
    }

    var coreStrategy: DuplicateStrategy {
        switch self {
        case .skip:
            return .skip
        case .overwrite:
            return .overwrite
        case .keepBoth:
            return .keepBoth
        case .ask:
            return .ask
        }
    }
}

struct ImportProgressRetryContext: Equatable, Sendable {
    var repoPath: String
    var sourcePath: String
    var storageMode: ImportSingleFileStorageMode
    var overrideCategory: String
    var overrideFilename: String
    var duplicateStrategy: ImportProgressDuplicateStrategy
}

enum ImportProgressRecoveryCheckState: Equatable, Sendable {
    case unavailable
    case checking
    case retryAllowed(RecoveryReportSnapshot?)
    case retryBlocked(String, RecoveryReportSnapshot?)
}

enum ImportProgressDiagnosticsState: Equatable, Sendable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

enum ImportProgressStopState: Equatable, Sendable {
    case idle
    case stopping
    case stopped
}

struct ImportProgressRouteState: Equatable, Sendable {
    enum Status: Equatable, Sendable {
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
                sourcePath: currentPath,
                targetPath: currentPath,
                phase: .copying,
                errorMessage: nil
            ),
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
                sourcePath: currentPath,
                targetPath: currentPath,
                phase: storageMode.progressPhase,
                errorMessage: nil
            ),
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
        guard case .failed(let mapping) = status else { return nil }
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
        "Importing \(completed) / \(completed + failed + remaining)"
    }

    var bannerText: String {
        if let errorMapping {
            return errorMapping.userMessage
        }
        let extras = resultExtras
        return extras.isEmpty
            ? "已完成 \(completed)，失败 \(failed)，剩余 \(remaining)"
            : "已完成 \(completed)，失败 \(failed)，剩余 \(remaining)，\(extras)"
    }

    var titleText: String {
        if isFailed {
            return "导入已暂停"
        }
        return total <= 1 ? "正在导入 1 个文件" : "正在导入 \(total) 个文件"
    }

    var detailsButtonTitle: String {
        "View details"
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
            parts.append("跳过 \(skipped)")
        }
        if pending > 0 {
            parts.append("待下载 \(pending)")
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
            return completed > 0 ? .done : .copying
        case .failed:
            return failed > 0 ? .failed : .pending
        }
    }

    private static func fallbackErrorMessage(status: Status) -> String? {
        guard case .failed(let mapping) = status else { return nil }
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
    var retryStatusText: String {
        switch recoveryCheck {
        case .unavailable:
            return "Retry is unavailable for this item."
        case .checking:
            return "Checking recovery state..."
        case .retryAllowed(let report):
            guard let report, report.hasVisibleDetails else {
                return "Recovery state checked. Current item can be retried."
            }
            return "Recovery checked: cleaned \(report.cleanedStagingFiles), reverted \(report.revertedStagingDbRows)."
        case .retryBlocked(let message, _):
            return message
        }
    }

    var resultSummaryText: String {
        "Imported \(completed), failed \(failed), stopped \(skipped), pending \(remaining + pending)."
    }

    var recoveryCheckTaskID: String {
        switch recoveryCheck {
        case .checking:
            return "checking-\(retryContext?.sourcePath ?? currentPath)"
        case .unavailable:
            return "unavailable"
        case .retryAllowed:
            return "allowed-\(retryContext?.sourcePath ?? currentPath)"
        case .retryBlocked:
            return "blocked-\(retryContext?.sourcePath ?? currentPath)"
        }
    }
}

private extension ImportSingleFileStorageMode {
    var isImportProgressRetryable: Bool {
        switch self {
        case .move, .indexOnly:
            return true
        case .copy:
            return false
        }
    }

    var progressPhase: ImportBatchProgressSnapshot.Phase {
        switch self {
        case .move:
            return .moving
        case .indexOnly:
            return .writingIndex
        case .copy:
            return .copying
        }
    }
}
