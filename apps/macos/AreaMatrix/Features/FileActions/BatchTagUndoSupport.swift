import Foundation

struct BatchMutationReportPresentation: Equatable {
    let addedSummaryText: String
    let skippedSummaryText: String
    let failedSummaryText: String

    init(report: BatchMutationReportSnapshot) {
        let added = BatchMutationReportSummary(status: .added, relationCount: report.addedCount, report: report)
        let skipped = BatchMutationReportSummary(
            status: .alreadyHadTag,
            relationCount: report.skippedCount,
            report: report
        )
        let failed = BatchMutationReportSummary(status: .failed, relationCount: report.failedCount, report: report)
        addedSummaryText = added.addedText
        skippedSummaryText = skipped.skippedText
        failedSummaryText = failed.failedText
    }
}

enum BatchTagUndoState: Equatable {
    case idle
    case loading(token: String)
    case ready(UndoActionRecordSnapshot)
    case disabled(UndoActionRecordSnapshot, reason: String)
    case unavailable(reason: String)
    case undoing(UndoActionRecordSnapshot)
    case undone(UndoActionResultSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: UndoActionRecordSnapshot?)

    var action: UndoActionRecordSnapshot? {
        switch self {
        case let .ready(action), let .disabled(action, _), let .undoing(action), let .failed(_, action?):
            action
        case .idle, .loading, .unavailable, .undone, .failed:
            nil
        }
    }

    var executableAction: UndoActionRecordSnapshot? {
        guard case let .ready(action) = self else { return nil }
        return action
    }

    var isBusy: Bool {
        switch self {
        case .loading, .undoing:
            true
        case .idle, .ready, .disabled, .unavailable, .undone, .failed:
            false
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

struct BatchTagUndoLoadResult: Equatable {
    var action: UndoActionRecordSnapshot?
    var unavailableReason: String?
    var failure: CoreErrorMappingSnapshot?

    var toastState: BatchTagUndoState? {
        if let failure { return .failed(failure, previous: action) }
        if let action, let unavailableReason { return .disabled(action, reason: unavailableReason) }
        if let unavailableReason { return .unavailable(reason: unavailableReason) }
        if let action { return .ready(action) }
        return nil
    }
}

struct BatchTagUndoApplyResult: Equatable {
    var result: UndoActionResultSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct BatchTagUndoActionLogRefreshResult: Equatable {
    var action: UndoActionRecordSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct BatchAddTagsSheetCompletion: Equatable {
    var undoState: BatchTagUndoState?
    var closesSheet: Bool
}

struct BatchTagUndoRefreshPlan: Equatable {
    var refreshTargets: [String]

    var refreshesCurrentList: Bool {
        containsAny(["files", "tree"])
    }

    var refreshesSelectionDetails: Bool {
        containsAny(["files", "tags", "selection"])
    }

    var refreshesChangeLog: Bool {
        contains("change_log")
    }

    var refreshesUndoActions: Bool {
        contains("undo_actions")
    }

    var refreshesRedoActions: Bool {
        contains("redo_actions")
    }

    private func containsAny(_ targets: [String]) -> Bool {
        targets.contains { contains($0) }
    }

    private func contains(_ target: String) -> Bool {
        refreshTargets.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
    }
}

struct BatchUndoStateRequest {
    var repoPath: String
    var shouldRefreshConsumer: Bool
    var undoToken: String?
    var failure: CoreErrorMappingSnapshot?
    var unavailableResultReason: String
}

enum BatchTagUndoAction {
    static func stateAfterBatchApply(
        request: BatchUndoStateRequest,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState? {
        guard request.failure == nil, request.shouldRefreshConsumer else { return nil }
        guard let token = normalizedToken(request.undoToken) else {
            return .unavailable(reason: request.unavailableResultReason)
        }

        let loadResult = await loadAction(
            repoPath: request.repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .unavailable(reason: L10n.string("Undo action is no longer available."))
    }

    static func refreshLatestToastState(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState {
        let loadResult = await loadLatestAction(
            repoPath: repoPath,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .idle
    }

    static func completionAfterBatchApply(
        repoPath: String,
        report: BatchMutationReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchAddTagsSheetCompletion {
        guard failure == nil, let report, report.failedCount == 0 else {
            return BatchAddTagsSheetCompletion(undoState: nil, closesSheet: false)
        }
        guard let token = normalizedToken(report.undoToken) else {
            return BatchAddTagsSheetCompletion(
                undoState: .unavailable(reason: L10n.string("Undo is unavailable for this result.")),
                closesSheet: true
            )
        }

        let loadResult = await loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let toastState = loadResult.toastState {
            return BatchAddTagsSheetCompletion(undoState: toastState, closesSheet: true)
        }
        return BatchAddTagsSheetCompletion(
            undoState: .unavailable(reason: L10n.string("Undo action is no longer available.")),
            closesSheet: true
        )
    }

    static func loadAction(
        repoPath: String,
        undoToken: String?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoLoadResult {
        guard let token = normalizedToken(undoToken) else {
            return BatchTagUndoLoadResult(
                action: nil,
                unavailableReason: L10n.string("Undo is unavailable for this result."),
                failure: nil
            )
        }
        do {
            let actions = try await undoStore.listUndoActions(repoPath: repoPath)
            guard let action = actions.first(where: { $0.actionID == token }) else {
                return BatchTagUndoLoadResult(
                    action: nil,
                    unavailableReason: L10n.string("Undo action is no longer available."),
                    failure: nil
                )
            }
            return loadResult(for: action)
        } catch {
            return await BatchTagUndoLoadResult(
                action: nil,
                unavailableReason: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }

    static func loadLatestAction(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoLoadResult {
        do {
            let actions = try await undoStore.listUndoActions(repoPath: repoPath)
            guard let action = latestToastAction(from: actions) else {
                return BatchTagUndoLoadResult(action: nil, unavailableReason: nil, failure: nil)
            }
            return loadResult(for: action)
        } catch {
            return await BatchTagUndoLoadResult(
                action: nil,
                unavailableReason: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }

    static func undo(
        repoPath: String,
        action: UndoActionRecordSnapshot,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoApplyResult {
        do {
            let result = try await undoStore.undoAction(repoPath: repoPath, actionID: action.actionID)
            return BatchTagUndoApplyResult(result: result, failure: nil)
        } catch {
            return await BatchTagUndoApplyResult(
                result: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }

    static func refreshActionLog(
        repoPath: String,
        actionID: String,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoActionLogRefreshResult {
        do {
            let actions = try await undoStore.listUndoActions(repoPath: repoPath)
            return BatchTagUndoActionLogRefreshResult(
                action: actions.first { $0.actionID == actionID },
                failure: nil
            )
        } catch {
            return await BatchTagUndoActionLogRefreshResult(
                action: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    private static func latestToastAction(from actions: [UndoActionRecordSnapshot]) -> UndoActionRecordSnapshot? {
        actions.first { action in
            action.status == .pending || action.status == .blocked || action.status == .expired
        }
    }

    private static func loadResult(for action: UndoActionRecordSnapshot) -> BatchTagUndoLoadResult {
        guard action.status == .pending, action.canUndo else {
            return BatchTagUndoLoadResult(
                action: action,
                unavailableReason: disabledReason(for: action),
                failure: nil
            )
        }
        return BatchTagUndoLoadResult(action: action, unavailableReason: nil, failure: nil)
    }

    private static func disabledReason(for action: UndoActionRecordSnapshot) -> String {
        if let reason = action.disabledReason, !reason.isEmpty { return reason }
        switch action.status {
        case .blocked:
            return L10n.string("Undo action is currently blocked.")
        case .expired:
            return L10n.string("Undo action expired.")
        case .executed:
            return L10n.string("Undo action has already been executed.")
        case .pending:
            return L10n.string("Undo action is currently unavailable.")
        }
    }
}

private struct BatchMutationReportSummary {
    var status: BatchMutationStatusSnapshot
    var relationCount: Int64
    var report: BatchMutationReportSnapshot

    var addedText: String {
        guard fileCount > 0 else {
            return relationOnlyText(action: L10n.string("added"), emptyText: L10n.string("Added to 0 files"))
        }
        return L10n.format("batchTags.report.addedFiles", fileCount) + relationSuffix
    }

    var skippedText: String {
        guard fileCount > 0 else {
            return relationOnlyText(
                action: L10n.string("already existed"),
                emptyText: L10n.string("0 files already had these tags")
            )
        }
        return L10n.plural("batchTags.report.skippedFiles", count: fileCount) + relationSuffix
    }

    var failedText: String {
        guard fileCount > 0 else {
            return relationOnlyText(action: L10n.string("failed"), emptyText: L10n.string("0 failed"))
        }
        return L10n.format("batchTags.report.failedFiles", fileCount) + relationSuffix
    }

    private var fileCount: Int64 {
        Int64(Set(report.itemResults.filter { $0.status == status }.map(\.fileID)).count)
    }

    private var relationSuffix: String {
        guard relationCount > 0, relationCount != fileCount else { return "" }
        return L10n.format("batchTags.report.relationSuffix", relationCount)
    }

    private func relationOnlyText(action: String, emptyText: String) -> String {
        guard relationCount > 0 else { return emptyText }
        return L10n.format("batchTags.report.relationAction", relationCount, action)
    }
}
