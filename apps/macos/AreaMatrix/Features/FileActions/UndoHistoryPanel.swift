import SwiftUI

struct UndoHistoryPanel: View {
    static let accessibilityID = "undo-history-undo-action-log-undo-history-panel"
    let repoPath: String
    let focusedActionID: String?
    let initialFailure: CoreErrorMappingSnapshot?
    let undoStore: any CoreUndoActionLogging
    let redoStore: any CoreRedoActionLogging
    let errorMapper: any CoreErrorMapping
    let onClose: () -> Void
    let onUndoCompleted: (UndoActionResultSnapshot) -> Void
    let onRedoCompleted: (RedoActionResultSnapshot) -> Void

    @State private var state: UndoHistoryState
    @State private var selectedActionID: String?

    init(
        repoPath: String,
        focusedActionID: String?,
        initialFailure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        redoStore: any CoreRedoActionLogging,
        errorMapper: any CoreErrorMapping,
        onClose: @escaping () -> Void,
        onUndoCompleted: @escaping (UndoActionResultSnapshot) -> Void,
        onRedoCompleted: @escaping (RedoActionResultSnapshot) -> Void
    ) {
        self.repoPath = repoPath
        self.focusedActionID = focusedActionID
        self.initialFailure = initialFailure
        self.undoStore = undoStore
        self.redoStore = redoStore
        self.errorMapper = errorMapper
        self.onClose = onClose
        self.onUndoCompleted = onUndoCompleted
        self.onRedoCompleted = onRedoCompleted
        _state = State(initialValue: initialFailure.map(UndoHistoryState.failed) ?? .loading)
        _selectedActionID = State(initialValue: focusedActionID)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720)
        .frame(minHeight: 430)
        .task(id: repoPath) { await loadActionsIfNeeded() }
        .onKeyPress("z", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            if event.modifiers.contains(.shift) {
                Task { await redoLatest() }
                return .handled
            }
            Task { await undoLatest() }
            return .handled
        }
        .accessibilityIdentifier(Self.accessibilityID)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("Undo History"))
                    .font(.title3.weight(.semibold))
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.string("Retry")) { Task { await loadActions() } }
                .disabled(state.isBusy)
                .accessibilityIdentifier("undo-history-undo-action-log-retry")
        }
        .padding(18)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Loading undo history...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(mapping):
            UndoHistoryErrorPane(mapping: mapping)
        default:
            if state.actions.isEmpty, state.snapshot.redoActions.isEmpty {
                Text(L10n.string("No undoable or redoable actions"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    UndoHistoryList(actions: state.actions, selectedActionID: $selectedActionID)
                    Divider()
                    UndoPreviewPane(
                        action: selectedAction,
                        redoAction: latestRedoAction,
                        redoSourceUndoAction: state.snapshot.sourceUndoAction(for: latestRedoAction),
                        isLatest: selectedActionID == state.actions.first?.actionID
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let failure = state.failure {
                Text(failure.userMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.string("Undo latest")) { Task { await undoLatest() } }
                .disabled(!canUndoLatest)
                .accessibilityIdentifier("undo-history-undo-action-log-undo-latest")
            Button(L10n.string("Redo latest")) { Task { await redoLatest() } }
                .disabled(!canRedoLatest)
                .help(L10n.string("Redo latest action"))
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-latest")
            Button(L10n.string("Close"), action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }

    private var selectedAction: UndoActionRecordSnapshot? {
        UndoHistoryActionLog.action(in: state.actions, focusedActionID: selectedActionID)
    }

    private var latestRedoAction: RedoActionRecordSnapshot? {
        state.snapshot.redoActions.first
    }

    private var canUndoLatest: Bool {
        guard let latest = state.actions.first else { return false }
        return latest.status == .pending && latest.canUndo && !state.isBusy
    }

    private var canRedoLatest: Bool {
        guard let latest = latestRedoAction else { return false }
        return latest.status == .available && latest.canRedo && !state.isBusy
    }

    private var statusText: String {
        let undoCount = state.actions.filter { $0.status == .pending && $0.canUndo }.count
        let redoCount = state.snapshot.redoActions.filter { $0.status == .available && $0.canRedo }.count
        if redoCount > 0 { return L10n.plural("file-actions.undo.redoable-actions", count: redoCount) }
        return undoCount == 0
            ? L10n.string("No undoable actions")
            : L10n.plural("file-actions.undo.undoable-actions", count: undoCount)
    }

    @MainActor
    private func loadActionsIfNeeded() async {
        if initialFailure != nil { return }
        await loadActions()
    }

    @MainActor
    private func loadActions() async {
        state = .loading
        state = await UndoHistoryActionLog.load(
            repoPath: repoPath,
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        selectedActionID = UndoHistoryActionLog.action(in: state.actions, focusedActionID: focusedActionID)?.actionID
    }

    @MainActor
    private func undoLatest() async {
        let previous = state.snapshot
        guard let latest = previous.undoActions.first else { return }
        state = .undoing(latest, previous: previous)
        state = await UndoHistoryActionLog.undoLatest(
            repoPath: repoPath,
            snapshot: previous,
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        selectedActionID = UndoHistoryActionLog.action(in: state.actions, focusedActionID: latest.actionID)?.actionID
        if case let .undone(result, _) = state {
            onUndoCompleted(result)
        }
    }

    @MainActor
    private func redoLatest() async {
        let previous = state.snapshot
        guard let latest = previous.redoActions.first else { return }
        state = .redoing(latest, previous: previous)
        state = await UndoHistoryActionLog.redoLatest(
            repoPath: repoPath,
            snapshot: previous,
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        selectedActionID = UndoHistoryActionLog.action(in: state.actions, focusedActionID: selectedActionID)?.actionID
        if case let .redone(result, _) = state {
            onRedoCompleted(result)
        }
    }
}

private struct UndoHistoryErrorPane: View {
    let mapping: CoreErrorMappingSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.string("Could not load undo history"), systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(mapping.userMessage)
            Text(mapping.suggestedAction)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
