import Foundation

enum RedoActionState: Equatable {
    case idle
    case checking(previous: RedoActionRecordSnapshot?)
    case available(RedoActionRecordSnapshot)
    case disabled(RedoActionRecordSnapshot, reason: String)
    case unavailable(reason: String)
    case redoing(RedoActionRecordSnapshot)
    case redone(RedoActionResultSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: RedoActionRecordSnapshot?)

    var action: RedoActionRecordSnapshot? {
        switch self {
        case let .checking(action?), let .available(action), let .disabled(action, _), let .redoing(action):
            action
        case let .failed(_, action?):
            action
        case .idle, .checking, .unavailable, .redone, .failed:
            nil
        }
    }

    var executableAction: RedoActionRecordSnapshot? {
        guard case let .available(action) = self else { return nil }
        return action
    }

    var isBusy: Bool {
        switch self {
        case .checking, .redoing:
            true
        case .idle, .available, .disabled, .unavailable, .redone, .failed:
            false
        }
    }
}

struct RedoActionLoadResult: Equatable {
    var action: RedoActionRecordSnapshot?
    var unavailableReason: String?
    var failure: CoreErrorMappingSnapshot?

    func feedbackState(emptyReason: String? = nil) -> RedoActionState? {
        if let failure { return .failed(failure, previous: action) }
        if let action, let unavailableReason { return .disabled(action, reason: unavailableReason) }
        if let unavailableReason { return .unavailable(reason: unavailableReason) }
        if let action { return .available(action) }
        return emptyReason.map(RedoActionState.unavailable)
    }
}

struct RedoActionApplyResult: Equatable {
    var result: RedoActionResultSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

enum BatchRenameUndoAction {
    static func stateAfterBatchApply(
        repoPath: String,
        report: BatchRenameReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState? {
        guard failure == nil, let report, report.shouldRefreshConsumerAfterApply else { return nil }
        guard let token = normalizedToken(report.undoToken) else {
            return .unavailable(reason: "Undo is unavailable for this rename result.")
        }

        let loadResult = await BatchTagUndoAction.loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .unavailable(reason: "Undo action is no longer available.")
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }
}

enum RedoActionFeedback {
    static func loadLatestAction(
        repoPath: String,
        redoStore: any CoreRedoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> RedoActionLoadResult {
        do {
            let actions = try await redoStore.listRedoActions(repoPath: repoPath)
            guard let action = latestFeedbackAction(from: actions) else {
                return RedoActionLoadResult(action: nil, unavailableReason: nil, failure: nil)
            }
            return loadResult(for: action)
        } catch {
            return RedoActionLoadResult(action: nil, unavailableReason: nil, failure: await mapError(error, errorMapper))
        }
    }

    static func redo(
        repoPath: String,
        action: RedoActionRecordSnapshot,
        redoStore: any CoreRedoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> RedoActionApplyResult {
        do {
            let result = try await redoStore.redoAction(repoPath: repoPath, actionID: action.actionID)
            return RedoActionApplyResult(result: result, failure: nil)
        } catch {
            return RedoActionApplyResult(result: nil, failure: await mapError(error, errorMapper))
        }
    }

    static func disabledReason(for action: RedoActionRecordSnapshot) -> String {
        if let reason = action.disabledReason, !reason.isEmpty { return reason }
        switch action.status {
        case .available:
            return "Redo action is currently unavailable."
        case .cleared:
            return "Redo was cleared by the next file operation."
        case .blocked:
            return "Review details before redoing this action."
        case .expired:
            return "Redo expired after app restart or later changes."
        case .executed:
            return "This action has already been redone."
        }
    }

    static func mapError(_ error: Error, _ errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private static func latestFeedbackAction(from actions: [RedoActionRecordSnapshot]) -> RedoActionRecordSnapshot? {
        actions.first { action in
            action.status == .available || action.status == .cleared || action.status == .blocked || action.status == .expired
        }
    }

    private static func loadResult(for action: RedoActionRecordSnapshot) -> RedoActionLoadResult {
        guard action.status == .available, action.canRedo else {
            return RedoActionLoadResult(action: action, unavailableReason: disabledReason(for: action), failure: nil)
        }
        return RedoActionLoadResult(action: action, unavailableReason: nil, failure: nil)
    }
}
