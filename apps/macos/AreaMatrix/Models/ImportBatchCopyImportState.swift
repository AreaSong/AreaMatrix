import Foundation

enum ImportBatchCopyImportRowStatus: Equatable {
    case loading
    case ready(reasonLabel: String)
    case duplicate(
        existingPath: String,
        strategy: ImportBatchDuplicateResolutionStrategy,
        isReplaceConfirmed: Bool
    )
    case nameConflict(existingPath: String, resolution: ImportBatchNameConflictResolution)
    case iCloudPlaceholder(path: String, message: String)
    case blocked(String)
    case importing(ImportSingleFileStorageMode)
    case skippedDuplicate(existingPath: String)
    case skippedICloud(path: String)
    case imported
    case error(String)

    var tag: String {
        switch self {
        case .loading:
            "PREVIEW"
        case .ready:
            "OK"
        case .duplicate:
            "DUP"
        case .nameConflict:
            "NAME"
        case .iCloudPlaceholder:
            "ICLOUD"
        case .blocked:
            "BLOCKED"
        case .importing:
            "IMPORTING"
        case .skippedDuplicate:
            "SKIPPED"
        case .skippedICloud:
            "PENDING"
        case .imported:
            "IMPORTED"
        case .error:
            "ERROR"
        }
    }

    var detail: String? {
        switch self {
        case .loading:
            return "Preparing preview..."
        case let .ready(reasonLabel), let .error(reasonLabel):
            return reasonLabel
        case let .duplicate(existingPath, strategy, isReplaceConfirmed):
            if strategy == .replace, isReplaceConfirmed {
                return "Replace confirmed: \(existingPath)"
            }
            return "\(strategy.title): \(existingPath)"
        case let .nameConflict(existingPath, resolution):
            return "\(resolution.title): \(existingPath)"
        case let .iCloudPlaceholder(_, message):
            return message
        case let .blocked(message):
            return message
        case let .importing(mode):
            return mode.importingMessage
        case let .skippedDuplicate(existingPath):
            return "Duplicate skipped: \(existingPath)"
        case let .skippedICloud(path):
            return "iCloud pending: \(path)"
        case .imported:
            return "已完成导入"
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

enum ImportBatchDuplicateResolutionStrategy: String, CaseIterable, Equatable {
    case skip
    case keepBoth
    case replace

    var title: String {
        switch self {
        case .skip:
            "Skip"
        case .keepBoth:
            "Keep both"
        case .replace:
            "Replace"
        }
    }

    var duplicateStrategy: DuplicateStrategy {
        switch self {
        case .skip:
            .skip
        case .keepBoth:
            .keepBoth
        case .replace:
            .overwrite
        }
    }

    var importsIncomingFile: Bool {
        self == .keepBoth || self == .replace
    }
}

enum ImportBatchNameConflictResolution: Hashable {
    case keepBoth
    case renameIncoming(String)
    case replace(isConfirmed: Bool)

    var title: String {
        switch self {
        case .keepBoth:
            "Keep both (auto-number)"
        case .renameIncoming:
            "Rename incoming"
        case let .replace(isConfirmed):
            isConfirmed ? "Replace confirmed" : "Replace"
        }
    }

    var importsIncomingFile: Bool {
        switch self {
        case .keepBoth, .renameIncoming:
            true
        case let .replace(isConfirmed):
            isConfirmed
        }
    }

    var isReplace: Bool {
        if case .replace = self { return true }
        return false
    }
}

struct ImportBatchCopyImportRow: Identifiable, Equatable {
    var originalName: String
    var sourcePath: String
    var sourceURL: URL
    var sizeBytes: Int64?
    var predictedCategory: String?
    var categoryOverride: String?
    var suggestedName: String
    var status: ImportBatchCopyImportRowStatus

    var id: String {
        sourcePath
    }

    var duplicateResolution: ImportBatchDuplicateResolutionStrategy? {
        if case let .duplicate(_, strategy, _) = status {
            return strategy
        }
        if case .skippedDuplicate = status {
            return .skip
        }
        return nil
    }

    var nameConflictResolution: ImportBatchNameConflictResolution? {
        if case let .nameConflict(_, resolution) = status {
            return resolution
        }
        return nil
    }

    var resolvedIncomingName: String {
        guard case let .nameConflict(_, resolution) = status else {
            return suggestedName
        }
        switch resolution {
        case .keepBoth, .replace:
            return suggestedName
        case let .renameIncoming(name):
            return name
        }
    }

    var isConflictReviewRow: Bool {
        switch status {
        case .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .skippedDuplicate, .skippedICloud:
            true
        case .loading, .ready, .importing, .imported, .error:
            false
        }
    }

    var isBlockedForImport: Bool {
        switch status {
        case .blocked:
            true
        case .duplicate(_, .replace, false):
            true
        case .nameConflict(_, .replace(false)):
            true
        case let .nameConflict(_, .renameIncoming(name)):
            ImportSingleFileFilenameValidator.validationMessage(for: name) != nil
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            false
        }
    }

    var existingConflictPath: String? {
        switch status {
        case let .duplicate(existingPath, _, _), let .nameConflict(existingPath, _),
             let .skippedDuplicate(existingPath):
            existingPath
        case .loading, .ready, .iCloudPlaceholder, .blocked, .importing, .skippedICloud, .imported, .error:
            nil
        }
    }

    var conflictLabel: String {
        switch status {
        case .duplicate, .skippedDuplicate:
            "Duplicate content"
        case .nameConflict:
            "Same name, different content"
        case .iCloudPlaceholder, .skippedICloud:
            "iCloud placeholder"
        case .blocked:
            "Blocked"
        case .loading, .ready, .importing, .imported, .error:
            "-"
        }
    }

    func displayCategory(for destination: ImportBatchDestinationOption) -> String {
        if let categoryOverride {
            return categoryOverride
        }
        if destination == .repositoryRoot {
            return "repo root"
        }
        return resolvedCategory(for: destination) ?? "inbox"
    }

    func resolvedCategory(for destination: ImportBatchDestinationOption) -> String? {
        if let categoryOverride {
            return categoryOverride
        }
        return defaultCategory(for: destination)
    }

    func defaultCategory(for destination: ImportBatchDestinationOption) -> String? {
        switch destination {
        case .autoClassify:
            predictedCategory ?? "inbox"
        case let .category(slug):
            slug
        case .repositoryRoot:
            nil
        }
    }
}

enum ImportBatchCopyImportStatus: Equatable {
    case idle
    case importing(completed: Int, total: Int, failed: Int, currentPath: String)
    case imported(successful: Int, failed: Int)

    var isImporting: Bool {
        if case .importing = self {
            return true
        }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            nil
        case let .importing(completed, total, failed, _):
            "正在导入：已完成 \(completed)/\(total)，失败 \(failed)"
        case let .imported(successful, failed):
            "批量导入完成：成功 \(successful)，失败 \(failed)"
        }
    }
}

extension ImportBatchCopyImportModel {
    var storageModeRiskMessage: String? {
        switch selectedStorageMode {
        case .copy:
            nil
        case .move:
            "Move 模式会移走源文件；请确认批量队列只包含要移入资料库的文件。"
        case .indexOnly:
            "Index-only 不复制文件，只写入索引；源文件移动或删除后会显示缺失。"
        }
    }
}

enum ImportConflictBatchUndoAction {
    static func stateAfterBatchApply(
        repoPath: String,
        report: ImportConflictBatchApplyReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState? {
        guard failure == nil, let report, report.shouldRefreshUndoActionLogAfterApply else { return nil }
        guard let token = normalizedToken(report.undoToken) else {
            return .unavailable(reason: "Undo is unavailable for this import conflict result.")
        }

        let loadResult = await BatchTagUndoAction.loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .unavailable(reason: "Undo action is no longer available.")
    }

    static func undo(
        repoPath: String,
        state: BatchTagUndoState,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState {
        guard let action = state.executableAction else { return state }
        let result = await BatchTagUndoAction.undo(
            repoPath: repoPath,
            action: action,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let undoResult = result.result {
            return .undone(undoResult)
        }
        if let failure = result.failure {
            return .failed(failure, previous: action)
        }
        return .failed(await fallbackMapping(errorMapper: errorMapper), previous: action)
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    private static func fallbackMapping(errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapCoreError(CoreError.Internal(message: "undo_action returned no result"))
    }
}

extension ImportConflictBatchApplyReportSnapshot {
    var shouldRefreshUndoActionLogAfterApply: Bool {
        resolvedCount > 0 || !changeLogActions.isEmpty || undoToken != nil
    }
}

@MainActor
extension ImportBatchCopyImportModel {
    func resetConflictBatchOutcome() {
        conflictBatchApplyResult = nil
        conflictBatchUndoState = .idle
        conflictBatchPerItemQueue = nil
    }

    func refreshConflictBatchUndoState(
        report: ImportConflictBatchApplyReportSnapshot?,
        failure: CoreErrorMappingSnapshot?
    ) async {
        if let state = await ImportConflictBatchUndoAction.stateAfterBatchApply(
            repoPath: request?.repoPath ?? "",
            report: report,
            failure: failure,
            undoStore: undoActionStore,
            errorMapper: errorMapper
        ) {
            conflictBatchUndoState = state
        } else {
            conflictBatchUndoState = .idle
        }
    }

    func undoImportConflictBatchAction() async {
        let currentState = conflictBatchUndoState
        if let action = currentState.executableAction {
            conflictBatchUndoState = .undoing(action)
        }
        let state = await ImportConflictBatchUndoAction.undo(
            repoPath: request?.repoPath ?? "",
            state: currentState,
            undoStore: undoActionStore,
            errorMapper: errorMapper
        )
        conflictBatchUndoState = state
    }
}

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
