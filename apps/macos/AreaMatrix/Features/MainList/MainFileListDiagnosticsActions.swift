import Foundation

enum UndoHistoryState: Equatable {
    case loading
    case loaded(UndoHistorySnapshot)
    case failed(CoreErrorMappingSnapshot)
    case undoing(UndoActionRecordSnapshot, previous: UndoHistorySnapshot)
    case undoFailed(CoreErrorMappingSnapshot, previous: UndoHistorySnapshot, attempted: UndoActionRecordSnapshot)
    case undone(UndoActionResultSnapshot, refreshed: UndoHistorySnapshot)
    case redoing(RedoActionRecordSnapshot, previous: UndoHistorySnapshot)
    case redoFailed(CoreErrorMappingSnapshot, previous: UndoHistorySnapshot, attempted: RedoActionRecordSnapshot)
    case redone(RedoActionResultSnapshot, refreshed: UndoHistorySnapshot)
    case refreshFailed(CoreErrorMappingSnapshot, previous: UndoHistorySnapshot)

    var snapshot: UndoHistorySnapshot {
        switch self {
        case .loading, .failed:
            .empty
        case let .loaded(snapshot), let .undoing(_, snapshot), let .undoFailed(_, snapshot, _):
            snapshot
        case let .undone(_, snapshot), let .redoing(_, snapshot), let .redoFailed(_, snapshot, _):
            snapshot
        case let .redone(_, snapshot), let .refreshFailed(_, snapshot):
            snapshot
        }
    }

    var actions: [UndoActionRecordSnapshot] {
        snapshot.undoActions
    }

    var failure: CoreErrorMappingSnapshot? {
        switch self {
        case let .failed(mapping), let .undoFailed(mapping, _, _), let .redoFailed(mapping, _, _):
            mapping
        case let .refreshFailed(mapping, _):
            mapping
        case .loading, .loaded, .undoing, .undone, .redoing, .redone:
            nil
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .undoing, .redoing:
            true
        case .loaded, .failed, .undoFailed, .undone, .redoFailed, .redone, .refreshFailed:
            false
        }
    }
}

struct UndoHistorySnapshot: Equatable {
    var undoActions: [UndoActionRecordSnapshot]
    var redoActions: [RedoActionRecordSnapshot]

    static let empty = UndoHistorySnapshot(undoActions: [], redoActions: [])

    func markingUndoBlockedIfNeeded(_ result: UndoActionResultSnapshot) -> UndoHistorySnapshot {
        guard result.status == .blocked else { return self }
        let updatedUndoActions = undoActions.map { action in
            guard action.actionID == result.actionID else { return action }
            var blocked = action
            blocked.status = .blocked
            blocked.canUndo = false
            if blocked.disabledReason?.isEmpty ?? true {
                blocked.disabledReason = result.summary
            }
            return blocked
        }
        return UndoHistorySnapshot(undoActions: updatedUndoActions, redoActions: redoActions)
    }

    func sourceUndoAction(for redoAction: RedoActionRecordSnapshot?) -> UndoActionRecordSnapshot? {
        guard let sourceUndoActionID = redoAction?.sourceUndoActionID else { return nil }
        return undoActions.first { $0.actionID == sourceUndoActionID }
    }
}

struct RedoUndoSourcePresentation: Equatable {
    let redoAction: RedoActionRecordSnapshot
    let sourceUndoAction: UndoActionRecordSnapshot?

    init(redoAction: RedoActionRecordSnapshot, undoActions: [UndoActionRecordSnapshot]) {
        self.redoAction = redoAction
        sourceUndoAction = undoActions.first { $0.actionID == redoAction.sourceUndoActionID }
    }

    var sourceText: String {
        guard let sourceUndoAction else {
            return "Source undo \(redoAction.sourceUndoActionID)"
        }
        return "Source undo: \(sourceUndoAction.summary)"
    }

    var accessibilityText: String {
        "\(redoAction.summary), \(statusText), \(sourceText)"
    }

    var statusText: String {
        if redoAction.status == .available, redoAction.canRedo {
            return "Available until the next file operation"
        }
        return RedoActionFeedback.disabledReason(for: redoAction)
    }
}

enum UndoHistoryActionLog {
    typealias Request = UndoToastHistoryRequest

    static func load(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        redoStore: any CoreRedoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> UndoHistoryState {
        do {
            return try await .loaded(loadSnapshot(repoPath: repoPath, undoStore: undoStore, redoStore: redoStore))
        } catch {
            return await .failed(mapError(error, errorMapper: errorMapper))
        }
    }

    static func undoLatest(
        repoPath: String,
        snapshot: UndoHistorySnapshot,
        undoStore: any CoreUndoActionLogging,
        redoStore: any CoreRedoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> UndoHistoryState {
        guard let latest = snapshot.undoActions.first else { return .loaded(snapshot) }
        guard latest.status == .pending, latest.canUndo else {
            return .undoFailed(
                unavailableMapping(reason: disabledReason(for: latest)),
                previous: snapshot,
                attempted: latest
            )
        }
        do {
            let result = try await undoStore.undoAction(repoPath: repoPath, actionID: latest.actionID)
            do {
                let refreshed = try await loadSnapshot(repoPath: repoPath, undoStore: undoStore, redoStore: redoStore)
                return .undone(result, refreshed: refreshed.markingUndoBlockedIfNeeded(result))
            } catch {
                return await .refreshFailed(
                    mapError(error, errorMapper: errorMapper),
                    previous: snapshot.markingUndoBlockedIfNeeded(result)
                )
            }
        } catch {
            return await .undoFailed(mapError(error, errorMapper: errorMapper), previous: snapshot, attempted: latest)
        }
    }

    static func redoLatest(
        repoPath: String,
        snapshot: UndoHistorySnapshot,
        undoStore: any CoreUndoActionLogging,
        redoStore: any CoreRedoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> UndoHistoryState {
        guard let latest = snapshot.redoActions.first else { return .loaded(snapshot) }
        guard latest.status == .available, latest.canRedo else {
            return .redoFailed(unavailableRedoMapping(for: latest), previous: snapshot, attempted: latest)
        }
        do {
            let result = try await redoStore.redoAction(repoPath: repoPath, actionID: latest.actionID)
            do {
                return try await .redone(result, refreshed: loadSnapshot(
                    repoPath: repoPath,
                    undoStore: undoStore,
                    redoStore: redoStore
                ))
            } catch {
                return await .refreshFailed(mapError(error, errorMapper: errorMapper), previous: snapshot)
            }
        } catch {
            return await .redoFailed(mapError(error, errorMapper: errorMapper), previous: snapshot, attempted: latest)
        }
    }

    static func action(
        in actions: [UndoActionRecordSnapshot],
        focusedActionID: String?
    ) -> UndoActionRecordSnapshot? {
        if let focusedActionID, let focused = actions.first(where: { $0.actionID == focusedActionID }) {
            return focused
        }
        return actions.first
    }

    static func disabledReason(for action: UndoActionRecordSnapshot) -> String {
        if action.status == .pending, action.canUndo { return "" }
        if let reason = action.disabledReason, !reason.isEmpty { return reason }
        switch action.status {
        case .blocked:
            return "Review details before undoing this action."
        case .expired:
            return "This action expired after app restart or later changes."
        case .executed:
            return "This action has already been undone."
        case .pending:
            return "Undo newer actions first."
        }
    }

    static func menuRequest(state: BatchTagUndoState, failure: CoreErrorMappingSnapshot?) -> Request {
        UndoToastHistoryRequest(source: .viewHistory, state: state, actionLogRefreshFailure: failure)
    }

    static func shortcutRequest(state: BatchTagUndoState, failure: CoreErrorMappingSnapshot?) -> Request {
        UndoToastHistoryRequest(source: .viewHistory, state: state, actionLogRefreshFailure: failure)
    }

    static func redoShortcutRequest(
        state: BatchTagUndoState,
        failure: CoreErrorMappingSnapshot?
    ) -> Request {
        UndoToastHistoryRequest(source: .viewHistory, state: state, actionLogRefreshFailure: failure)
    }

    private static func loadSnapshot(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        redoStore: any CoreRedoActionLogging
    ) async throws -> UndoHistorySnapshot {
        let undoActions = try await undoStore.listUndoActions(repoPath: repoPath)
        let redoActions = try await redoStore.listRedoActions(repoPath: repoPath)
        return UndoHistorySnapshot(undoActions: undoActions, redoActions: redoActions)
    }

    private static func unavailableMapping(reason: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: reason,
            severity: .medium,
            suggestedAction: "Review details in Undo History.",
            recoverability: .refreshRequired,
            rawContext: "undo-history undo-action-log undo-action-log"
        )
    }

    private static func unavailableRedoMapping(for action: RedoActionRecordSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: action.status == .expired ? .expiredAction : .conflict,
            userMessage: RedoActionFeedback.disabledReason(for: action),
            severity: .medium,
            suggestedAction: "Review details in Undo History.",
            recoverability: .refreshRequired,
            rawContext: "redo-action-log redo-action-log-core redo-action-log"
        )
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

extension MainFileListModel {
    func collectCurrentListDiagnostics() async {
        guard diagnosticsState != .collecting else { return }

        diagnosticsState = .collecting
        do {
            diagnosticsState = try await .collected(diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath))
        } catch {
            diagnosticsState = await .failed(mapCoreError(error))
        }
    }

    func clearDiagnosticsState() {
        diagnosticsState = .idle
    }
}
