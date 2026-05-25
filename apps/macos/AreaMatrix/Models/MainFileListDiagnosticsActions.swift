import Foundation
import SwiftUI

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
    static func load(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        redoStore: any CoreRedoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> UndoHistoryState {
        do {
            return .loaded(try await loadSnapshot(repoPath: repoPath, undoStore: undoStore, redoStore: redoStore))
        } catch {
            return .failed(await mapError(error, errorMapper: errorMapper))
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
                return .refreshFailed(
                    await mapError(error, errorMapper: errorMapper),
                    previous: snapshot.markingUndoBlockedIfNeeded(result)
                )
            }
        } catch {
            return .undoFailed(await mapError(error, errorMapper: errorMapper), previous: snapshot, attempted: latest)
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
                return .redone(result, refreshed: try await loadSnapshot(
                    repoPath: repoPath,
                    undoStore: undoStore,
                    redoStore: redoStore
                ))
            } catch {
                return .refreshFailed(await mapError(error, errorMapper: errorMapper), previous: snapshot)
            }
        } catch {
            return .redoFailed(await mapError(error, errorMapper: errorMapper), previous: snapshot, attempted: latest)
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

    static func menuRequest(state: BatchTagUndoState, failure: CoreErrorMappingSnapshot?) -> UndoToastHistoryRequest {
        UndoToastHistoryRequest(source: .viewHistory, state: state, actionLogRefreshFailure: failure)
    }

    static func shortcutRequest(state: BatchTagUndoState, failure: CoreErrorMappingSnapshot?) -> UndoToastHistoryRequest {
        UndoToastHistoryRequest(source: .viewHistory, state: state, actionLogRefreshFailure: failure)
    }

    static func redoShortcutRequest(
        state: BatchTagUndoState,
        failure: CoreErrorMappingSnapshot?
    ) -> UndoToastHistoryRequest {
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
            rawContext: "S2-11 C2-07 undo-action-log"
        )
    }

    private static func unavailableRedoMapping(for action: RedoActionRecordSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: action.status == .expired ? .expiredAction : .conflict,
            userMessage: RedoActionFeedback.disabledReason(for: action),
            severity: .medium,
            suggestedAction: "Review details in Undo History.",
            recoverability: .refreshRequired,
            rawContext: "S2-22 C2-18 redo-action-log"
        )
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

struct UndoHistoryPanel: View {
    static let accessibilityID = "S2-11-C2-07-undo-history-panel"
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
                Text("Undo History")
                    .font(.title3.weight(.semibold))
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { Task { await loadActions() } }
                .disabled(state.isBusy)
                .accessibilityIdentifier("S2-11-C2-07-retry")
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
                Text("No undoable or redoable actions")
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
            Button("Undo latest") { Task { await undoLatest() } }
                .disabled(!canUndoLatest)
                .accessibilityIdentifier("S2-11-C2-07-undo-latest")
            Button("Redo latest") { Task { await redoLatest() } }
                .disabled(!canRedoLatest)
                .help("Redo latest action")
                .accessibilityIdentifier("S2-22-C2-18-redo-latest")
            Button("Close", action: onClose)
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
        if redoCount > 0 { return "\(redoCount) action can be redone" }
        return undoCount == 0 ? "No undoable actions" : "\(undoCount) actions can be undone"
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
            Label("Could not load undo history", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(mapping.userMessage)
            Text(mapping.suggestedAction)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
