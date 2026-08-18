import AreaMatrixUIFoundation
import SwiftUI

struct UndoToastHistoryRequest: Identifiable, Equatable {
    enum Source: String, Equatable {
        case viewHistory
        case viewDetails
    }

    let source: Source
    let state: BatchTagUndoState
    let actionLogRefreshFailure: CoreErrorMappingSnapshot?

    var id: String {
        "\(source.rawValue):\(state.routeIdentity):\(actionLogRefreshFailure?.rawContext ?? "")"
    }
}

struct BatchTagUndoToastHost: View {
    let repoPath: String
    let undoStore: any CoreUndoActionLogging
    let redoStore: any CoreRedoActionLogging
    let errorMapper: any CoreErrorMapping
    let onRefreshSelection: () -> Void
    let onRefreshChangeLog: () -> Void
    let onRefreshCurrentList: () -> Void
    let onOpenHistory: (UndoToastHistoryRequest) -> Void
    @Binding var undoState: BatchTagUndoState
    @Binding var actionLogRefreshFailure: CoreErrorMappingSnapshot?
    @State private var redoState: RedoActionState = .idle
    @State private var redoSourceUndoAction: UndoActionRecordSnapshot?

    var body: some View {
        Group {
            if !undoState.isIdle {
                BatchTagUndoToastView(
                    state: undoState,
                    redoState: redoState,
                    redoSourceUndoAction: redoSourceUndoAction,
                    actionLogRefreshFailure: actionLogRefreshFailure,
                    onUndo: { action in Task { await undo(action) } },
                    onRedo: { action in Task { await redo(action) } },
                    onOpenHistory: openHistory,
                    onDismiss: dismissUndoToast
                )
                .frame(maxWidth: 420)
            }
        }
        .task(id: repoPath) { await loadLatestUndoAction() }
        .onKeyPress("z", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            if event.modifiers.contains(.shift) {
                if let action = redoState.executableAction, !redoState.isBusy {
                    Task { await redo(action) }
                    return .handled
                }
                return .ignored
            }
            if let action = undoState.executableAction, !undoState.isBusy {
                Task { await undo(action) }
                return .handled
            }
            return .ignored
        }
    }

    @MainActor
    private func loadLatestUndoAction() async {
        undoState = await BatchTagUndoAction.refreshLatestToastState(
            repoPath: repoPath,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
    }

    @MainActor
    private func undo(_ action: UndoActionRecordSnapshot) async {
        undoState = .undoing(action)
        actionLogRefreshFailure = nil
        let applied = await BatchTagUndoAction.undo(
            repoPath: repoPath,
            action: action,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let failure = applied.failure {
            undoState = .failed(failure, previous: action)
            return
        }
        guard let result = applied.result else {
            undoState = .unavailable(reason: L10n.string("Undo action finished without a result."))
            return
        }

        undoState = .undone(result)
        await refreshAfterUndo(result)
        await loadLatestRedoAction()
    }

    @MainActor
    private func refreshAfterUndo(_ result: UndoActionResultSnapshot) async {
        let plan = BatchTagUndoRefreshPlan(refreshTargets: result.refreshTargets)
        if plan.refreshesCurrentList { onRefreshCurrentList() }
        if plan.refreshesSelectionDetails { onRefreshSelection() }
        if plan.refreshesChangeLog { onRefreshChangeLog() }
        guard plan.refreshesUndoActions else { return }

        let refreshed = await BatchTagUndoAction.refreshActionLog(
            repoPath: repoPath,
            actionID: result.actionID,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        actionLogRefreshFailure = refreshed.failure
        redoSourceUndoAction = refreshed.action
    }

    @MainActor
    private func loadLatestRedoAction() async {
        let previous = redoState.action
        redoState = .checking(previous: previous)
        let loaded = await RedoActionFeedback.loadLatestAction(
            repoPath: repoPath,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        redoState = loaded.feedbackState() ?? .idle
        updateRedoSourceUndoAction(for: loaded.action)
    }

    @MainActor
    private func redo(_ action: RedoActionRecordSnapshot) async {
        redoState = .redoing(action)
        let applied = await RedoActionFeedback.redo(
            repoPath: repoPath,
            action: action,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        if let failure = applied.failure {
            redoState = .failed(failure, previous: action)
            return
        }
        guard let result = applied.result else {
            redoState = .unavailable(reason: L10n.string("Redo action finished without a result."))
            return
        }

        redoState = .redone(result)
        await refreshAfterRedo(result)
    }

    @MainActor
    private func refreshAfterRedo(_ result: RedoActionResultSnapshot) async {
        let plan = BatchTagUndoRefreshPlan(refreshTargets: result.refreshTargets)
        if plan.refreshesCurrentList { onRefreshCurrentList() }
        if plan.refreshesSelectionDetails { onRefreshSelection() }
        if plan.refreshesChangeLog { onRefreshChangeLog() }
        if plan.refreshesUndoActions {
            await loadLatestUndoAction()
        }
    }

    private func dismissUndoToast() {
        undoState = .idle
        redoState = .idle
        redoSourceUndoAction = nil
        actionLogRefreshFailure = nil
    }

    @MainActor
    private func updateRedoSourceUndoAction(for action: RedoActionRecordSnapshot?) {
        guard let action else {
            redoSourceUndoAction = nil
            return
        }
        if redoSourceUndoAction?.actionID == action.sourceUndoActionID {
            return
        }
        redoSourceUndoAction = undoState.action?.actionID == action.sourceUndoActionID ? undoState.action : nil
    }

    private func openHistory(_ source: UndoToastHistoryRequest.Source) {
        onOpenHistory(UndoToastHistoryRequest(
            source: source,
            state: undoState,
            actionLogRefreshFailure: actionLogRefreshFailure
        ))
    }
}

private extension BatchTagUndoState {
    var routeIdentity: String {
        switch self {
        case .idle:
            "idle"
        case let .loading(token):
            "loading:\(token)"
        case let .ready(action), let .disabled(action, _), let .undoing(action):
            action.actionID
        case let .unavailable(reason):
            "unavailable:\(reason)"
        case let .undone(result):
            "undone:\(result.actionID)"
        case let .failed(mapping, previous):
            "failed:\(previous?.actionID ?? "none"):\(mapping.kind.rawValue)"
        }
    }
}

extension UndoToastHistoryRequest {
    var focusedActionID: String? {
        switch state {
        case let .ready(action), let .disabled(action, _), let .undoing(action):
            action.actionID
        case let .undone(result):
            result.actionID
        case let .failed(_, previous):
            previous?.actionID
        case .idle, .loading, .unavailable:
            nil
        }
    }

    var failureMapping: CoreErrorMappingSnapshot? {
        if case let .failed(mapping, _) = state { return mapping }
        return actionLogRefreshFailure
    }
}

struct UndoToastHistoryRouteSheet: View {
    let request: UndoToastHistoryRequest
    let onClose: () -> Void

    var body: some View {
        AreaMatrixActionSheetContainer(title: title, pageID: "undo-toast") {
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: systemImage)
                    .font(.callout)
                if let failure = request.failureMapping {
                    Text(failure.userMessage)
                        .foregroundStyle(.secondary)
                    Text(failure.suggestedAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button(L10n.string("Close"), action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 420)
        .accessibilityIdentifier("undo-toast-undo-action-log-undo-history-route")
    }

    private var title: String {
        request.source == .viewDetails ? L10n.string("Undo Details") : L10n.string("Undo History")
    }

    private var message: String {
        request.source == .viewDetails ?
            L10n.string("Undo details will open in Undo History.") :
            L10n.string("Undo History will show recent undo actions.")
    }

    private var systemImage: String {
        request.source == .viewDetails ? "exclamationmark.triangle" : "clock.arrow.circlepath"
    }
}
