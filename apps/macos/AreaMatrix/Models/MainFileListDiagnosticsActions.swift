import Foundation
import SwiftUI

enum UndoHistoryState: Equatable {
    case loading
    case loaded([UndoActionRecordSnapshot])
    case failed(CoreErrorMappingSnapshot)
    case undoing(UndoActionRecordSnapshot, previous: [UndoActionRecordSnapshot])
    case undoFailed(CoreErrorMappingSnapshot, previous: [UndoActionRecordSnapshot], attempted: UndoActionRecordSnapshot)
    case undone(UndoActionResultSnapshot, refreshed: [UndoActionRecordSnapshot])
    case refreshFailed(UndoActionResultSnapshot, CoreErrorMappingSnapshot, previous: [UndoActionRecordSnapshot])

    var actions: [UndoActionRecordSnapshot] {
        switch self {
        case .loading, .failed:
            []
        case let .loaded(actions), let .undoing(_, actions):
            actions
        case let .undoFailed(_, actions, _):
            actions
        case let .undone(_, actions), let .refreshFailed(_, _, actions):
            actions
        }
    }

    var failure: CoreErrorMappingSnapshot? {
        switch self {
        case let .failed(mapping), let .undoFailed(mapping, _, _), let .refreshFailed(_, mapping, _):
            mapping
        case .loading, .loaded, .undoing, .undone:
            nil
        }
    }

    var isBusy: Bool {
        switch self {
        case .loading, .undoing:
            true
        case .loaded, .failed, .undoFailed, .undone, .refreshFailed:
            false
        }
    }
}

enum UndoHistoryActionLog {
    static func load(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> UndoHistoryState {
        do {
            return .loaded(try await undoStore.listUndoActions(repoPath: repoPath))
        } catch {
            return .failed(await mapError(error, errorMapper: errorMapper))
        }
    }

    static func undoLatest(
        repoPath: String,
        actions: [UndoActionRecordSnapshot],
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> UndoHistoryState {
        guard let latest = actions.first else { return .loaded(actions) }
        guard latest.status == .pending, latest.canUndo else {
            return .undoFailed(
                unavailableMapping(reason: disabledReason(for: latest)),
                previous: actions,
                attempted: latest
            )
        }
        do {
            let result = try await undoStore.undoAction(repoPath: repoPath, actionID: latest.actionID)
            do {
                let refreshedActions = try await undoStore.listUndoActions(repoPath: repoPath)
                return .undone(result, refreshed: markAttemptedActionBlockedIfNeeded(refreshedActions, result: result))
            } catch {
                return .refreshFailed(
                    result,
                    await mapError(error, errorMapper: errorMapper),
                    previous: markAttemptedActionBlockedIfNeeded(actions, result: result)
                )
            }
        } catch {
            return .undoFailed(await mapError(error, errorMapper: errorMapper), previous: actions, attempted: latest)
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
        let mapping = failure ?? CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Redo latest is handled by S2-22 / C2-18.",
            severity: .medium,
            suggestedAction: "Review Undo History until Redo is available.",
            recoverability: .refreshRequired,
            rawContext: "S2-11 C2-07 undo-action-log"
        )
        return UndoToastHistoryRequest(source: .viewHistory, state: state, actionLogRefreshFailure: mapping)
    }

    private static func markAttemptedActionBlockedIfNeeded(
        _ actions: [UndoActionRecordSnapshot],
        result: UndoActionResultSnapshot
    ) -> [UndoActionRecordSnapshot] {
        guard result.status == .blocked else { return actions }
        return actions.map { action in
            guard action.actionID == result.actionID else { return action }
            var blocked = action
            blocked.status = .blocked
            blocked.canUndo = false
            if blocked.disabledReason?.isEmpty ?? true {
                blocked.disabledReason = result.summary
            }
            return blocked
        }
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
    let errorMapper: any CoreErrorMapping
    let onClose: () -> Void
    let onUndoCompleted: (UndoActionResultSnapshot) -> Void

    @State private var state: UndoHistoryState
    @State private var selectedActionID: String?
    init(
        repoPath: String,
        focusedActionID: String?,
        initialFailure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping,
        onClose: @escaping () -> Void,
        onUndoCompleted: @escaping (UndoActionResultSnapshot) -> Void
    ) {
        self.repoPath = repoPath
        self.focusedActionID = focusedActionID
        self.initialFailure = initialFailure
        self.undoStore = undoStore
        self.errorMapper = errorMapper
        self.onClose = onClose
        self.onUndoCompleted = onUndoCompleted
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
                markRedoUnavailable()
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
            if state.actions.isEmpty {
                Text("No undoable actions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    UndoHistoryList(actions: state.actions, selectedActionID: $selectedActionID)
                    Divider()
                    UndoPreviewPane(action: selectedAction, isLatest: selectedActionID == state.actions.first?.actionID)
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
            Button("Redo latest") {}
                .onTapGesture(perform: markRedoUnavailable)
                .disabled(true)
                .help("Redo latest is handled by S2-22 / C2-18.")
                .accessibilityIdentifier("S2-11-C2-07-redo-latest")
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
        }
        .padding(18)
    }

    private var selectedAction: UndoActionRecordSnapshot? {
        UndoHistoryActionLog.action(in: state.actions, focusedActionID: selectedActionID)
    }

    private var canUndoLatest: Bool {
        guard let latest = state.actions.first else { return false }
        return latest.status == .pending && latest.canUndo && !state.isBusy
    }

    private var statusText: String {
        let count = state.actions.filter { $0.status == .pending && $0.canUndo }.count
        return count == 0 ? "No undoable actions" : "\(count) actions can be undone"
    }

    @MainActor
    private func loadActionsIfNeeded() async {
        if initialFailure != nil { return }
        await loadActions()
    }

    @MainActor
    private func loadActions() async {
        state = .loading
        state = await UndoHistoryActionLog.load(repoPath: repoPath, undoStore: undoStore, errorMapper: errorMapper)
        selectedActionID = UndoHistoryActionLog.action(in: state.actions, focusedActionID: focusedActionID)?.actionID
    }

    @MainActor
    private func undoLatest() async {
        let previous = state.actions
        guard let latest = previous.first else { return }
        state = .undoing(latest, previous: previous)
        state = await UndoHistoryActionLog.undoLatest(
            repoPath: repoPath,
            actions: previous,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        selectedActionID = UndoHistoryActionLog.action(in: state.actions, focusedActionID: latest.actionID)?.actionID
        if case let .undone(result, _) = state {
            onUndoCompleted(result)
        } else if case let .refreshFailed(result, _, _) = state {
            onUndoCompleted(result)
        }
    }

    @MainActor
    private func markRedoUnavailable() {
        guard let latest = state.actions.first else { return }
        state = .undoFailed(
            CoreErrorMappingSnapshot(
                kind: .conflict,
                userMessage: "Redo latest is handled by S2-22 / C2-18.",
                severity: .medium,
                suggestedAction: "Open the Redo task flow when C2-18 is available.",
                recoverability: .refreshRequired,
                rawContext: "S2-11 C2-07 undo-action-log"
            ),
            previous: state.actions,
            attempted: latest
        )
    }
}

private struct UndoHistoryList: View {
    let actions: [UndoActionRecordSnapshot]
    @Binding var selectedActionID: String?

    var body: some View {
        List(actions, selection: $selectedActionID) { action in
            UndoHistoryRow(action: action)
                .tag(action.actionID)
        }
        .frame(minWidth: 310)
    }
}

private struct UndoHistoryRow: View {
    let action: UndoActionRecordSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.summary)
                    .lineLimit(2)
                Text("\(timeText) · \(action.affectedCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(action.canUndo ? .green : .secondary)
            }
            Spacer()
        }
        .accessibilityLabel("\(action.summary), \(timeText), \(action.affectedCount) files, \(statusText)")
    }

    private var iconName: String {
        if action.kind.contains("tag") { return "tag" }
        if action.kind.contains("rename") { return "text.cursor" }
        if action.kind.contains("trash") || action.kind.contains("delete") { return "trash" }
        if action.kind.contains("move") { return "folder" }
        return "arrow.uturn.backward"
    }

    private var statusText: String {
        switch action.status {
        case .pending:
            return action.canUndo ? "Available" : "Blocked"
        case .blocked:
            return "Blocked"
        case .expired:
            return "Expired"
        case .executed:
            return "Executed"
        }
    }

    private var timeText: String {
        Date(timeIntervalSince1970: TimeInterval(action.createdAt))
            .formatted(date: .abbreviated, time: .shortened)
    }
}

private struct UndoPreviewPane: View {
    let action: UndoActionRecordSnapshot?
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let action {
                Label("Action: \(displayKind(action.kind))", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Text("Affected files: \(action.affectedCount)")
                Text("Undo result: \(action.summary)")
                    .foregroundStyle(.secondary)
                fileSamples(action.affectedFileNames)
                if !isLatest {
                    Text("Undo newer actions first.")
                        .foregroundStyle(.secondary)
                }
                if let reason = disabledReason(action) {
                    Text(reason)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select an action")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func fileSamples(_ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(names.prefix(5), id: \.self) { name in
                    Text(name)
                        .lineLimit(1)
                }
            }
        }
    }

    private func disabledReason(_ action: UndoActionRecordSnapshot) -> String? {
        let reason = UndoHistoryActionLog.disabledReason(for: action)
        return reason.isEmpty ? nil : reason
    }

    private func displayKind(_ kind: String) -> String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized
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
