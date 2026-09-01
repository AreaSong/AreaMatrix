import AreaMatrixCoreBridgeContract
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
            return L10n.format("redo.sourceUndo.id", redoAction.sourceUndoActionID)
        }
        return L10n.format("redo.sourceUndo.summary", sourceUndoAction.summary)
    }

    var accessibilityText: String {
        "\(redoAction.summary), \(statusText), \(sourceText)"
    }

    var statusText: String {
        if redoAction.status == .available, redoAction.canRedo {
            return L10n.string("Available until the next file operation")
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
            return await .failed(errorMapper.mapError(error))
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
                unavailableMapping(technicalReason: disabledReason(for: latest)),
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
                    errorMapper.mapError(error),
                    previous: snapshot.markingUndoBlockedIfNeeded(result)
                )
            }
        } catch {
            return await .undoFailed(
                errorMapper.mapError(error),
                previous: snapshot,
                attempted: latest
            )
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
                return await .refreshFailed(
                    errorMapper.mapError(error),
                    previous: snapshot
                )
            }
        } catch {
            return await .redoFailed(
                errorMapper.mapError(error),
                previous: snapshot,
                attempted: latest
            )
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
            return L10n.string("Review details before undoing this action.")
        case .expired:
            return L10n.string("This action expired after app restart or later changes.")
        case .executed:
            return L10n.string("This action has already been undone.")
        case .pending:
            return L10n.string("Undo newer actions first.")
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

    private static func unavailableMapping(technicalReason: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: L10n.message(
                "Undo action is currently unavailable.",
                technicalDetail: technicalReason
            ),
            severity: .medium,
            suggestedAction: L10n.message("Review details in Undo History."),
            recoverability: .refreshRequired,
            rawContext: technicalReason
        )
    }

    private static func unavailableRedoMapping(for action: RedoActionRecordSnapshot) -> CoreErrorMappingSnapshot {
        let reason = RedoActionFeedback.disabledReason(for: action)
        return CoreErrorMappingSnapshot(
            kind: action.status == .expired ? .expiredAction : .conflict,
            userMessage: L10n.message(
                "Redo action is currently unavailable.",
                technicalDetail: reason
            ),
            severity: .medium,
            suggestedAction: L10n.message("Review details in Undo History."),
            recoverability: .refreshRequired,
            rawContext: reason
        )
    }
}

@MainActor
final class MainListDiagnosticsModel: ObservableObject {
    @Published private(set) var state = MainListDiagnosticsState.idle

    private let repoPath: String
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private let errorMapper: any CoreErrorMapping
    private var generation = 0

    init(
        repoPath: String,
        diagnosticsCollector: any CoreDiagnosticsCollecting,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.diagnosticsCollector = diagnosticsCollector
        self.errorMapper = errorMapper
    }

    func requestCollection() {
        guard state != .collecting else { return }
        generation += 1
        state = .confirmingPrivacy
    }

    func cancelCollection() {
        guard state == .confirmingPrivacy || state == .collecting else { return }
        generation += 1
        state = .idle
    }

    func collect() async {
        guard state == .confirmingPrivacy else { return }

        generation += 1
        let expectedGeneration = generation
        state = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            guard generation == expectedGeneration else { return }
            state = .collected(snapshot)
        } catch {
            let mapping = await errorMapper.mapError(error)
            guard generation == expectedGeneration else { return }
            state = .failed(mapping)
        }
    }

    func clear() {
        generation += 1
        state = .idle
    }
}
