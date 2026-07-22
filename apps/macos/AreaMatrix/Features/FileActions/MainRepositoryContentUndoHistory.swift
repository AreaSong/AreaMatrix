import SwiftUI

extension MainRepositoryContentView {
    func applyMainRepositoryUndoHistoryMenuCommandRelay(to content: some View) -> some View {
        content.onReceive(NotificationCenter.default.publisher(
            for: AreaMatrixUndoHistoryCommandRelay.notification
        )) { _ in
            openUndoHistoryFromMenu()
        }
    }

    func applyMainRepositoryUndoRedoKeyCommands(to content: some View) -> some View {
        content.onKeyPress("z", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
            if event.modifiers.contains(.shift) {
                openUndoHistoryFromRedoShortcut()
                return .handled
            }
            openUndoHistoryFromShortcut()
            return .handled
        }
    }

    var batchTagUndoToastOverlay: some View {
        BatchTagUndoToastHost(
            repoPath: opening.config.repoPath,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper,
            onRefreshSelection: { Task { await fileListModel.retrySelectedFileDetail() } },
            onRefreshChangeLog: { Task { await fileListModel.loadSelectedFileChangeLog() } },
            onRefreshCurrentList: { Task { await fileListModel.retryCurrentCategory() } },
            onOpenHistory: { fileActionRoutingState.undoHistoryRequest = $0 },
            undoState: $fileActionRoutingState.batchTagUndoState,
            actionLogRefreshFailure: $fileActionRoutingState.actionLogRefreshFailure
        )
    }

    func undoHistorySheet(_ request: UndoToastHistoryRequest) -> some View {
        UndoHistoryPanel(
            repoPath: opening.config.repoPath,
            focusedActionID: request.focusedActionID,
            initialFailure: request.failureMapping,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper,
            onClose: { fileActionRoutingState.undoHistoryRequest = nil },
            onUndoCompleted: handleUndoHistoryResult,
            onRedoCompleted: handleRedoHistoryResult
        )
    }

    func handleUndoHistoryResult(_ result: UndoActionResultSnapshot) {
        refreshAfterUndoRedo(targets: result.refreshTargets)
    }

    func handleRedoHistoryResult(_ result: RedoActionResultSnapshot) {
        refreshAfterUndoRedo(targets: result.refreshTargets)
    }

    func updateBatchTagUndoState(_ state: BatchTagUndoState) {
        fileActionRoutingState.batchTagUndoState = state
        fileActionRoutingState.actionLogRefreshFailure = nil
    }

    @MainActor
    func refreshLatestUndoToast() {
        Task {
            fileActionRoutingState.batchTagUndoState = await BatchTagUndoAction.refreshLatestToastState(
                repoPath: opening.config.repoPath,
                undoStore: fileListModel.undoActionStore,
                errorMapper: fileListModel.errorMapper
            )
            fileActionRoutingState.actionLogRefreshFailure = nil
        }
    }

    func openUndoHistoryFromToolbar() {
        fileActionRoutingState.undoHistoryRequest = UndoToastHistoryRequest(
            source: .viewHistory,
            state: fileActionRoutingState.batchTagUndoState,
            actionLogRefreshFailure: fileActionRoutingState.actionLogRefreshFailure
        )
    }

    func openUndoHistoryFromMenu() {
        fileActionRoutingState.undoHistoryRequest = UndoHistoryActionLog.menuRequest(
            state: fileActionRoutingState.batchTagUndoState,
            failure: fileActionRoutingState.actionLogRefreshFailure
        )
    }

    func openUndoHistoryFromShortcut() {
        fileActionRoutingState.undoHistoryRequest = UndoHistoryActionLog.shortcutRequest(
            state: fileActionRoutingState.batchTagUndoState,
            failure: fileActionRoutingState.actionLogRefreshFailure
        )
    }

    func openUndoHistoryFromRedoShortcut() {
        Task { await executeLatestRedoAction(entryPoint: .keyboardShortcut) }
    }

    @MainActor
    func executeLatestRedoAction(entryPoint: RedoLatestEntryPoint) async {
        if entryPoint == .commandPalette {
            fileListModel.commandPaletteState = .loading(commandPaletteContext())
        }
        let loaded = await UndoHistoryActionLog.load(
            repoPath: opening.config.repoPath,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper
        )
        guard case let .loaded(snapshot) = loaded else {
            handleRedoEntryFailure(loaded.failure, entryPoint: entryPoint)
            return
        }
        let result = await UndoHistoryActionLog.redoLatest(
            repoPath: opening.config.repoPath,
            snapshot: snapshot,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper
        )
        handleRedoEntryResult(result, entryPoint: entryPoint)
    }

    @MainActor
    private func handleRedoEntryResult(_ state: UndoHistoryState, entryPoint: RedoLatestEntryPoint) {
        switch state {
        case let .redone(result, _):
            closeCommandPaletteIfNeeded(entryPoint)
            handleRedoHistoryResult(result)
        case let .redoFailed(mapping, _, _), let .refreshFailed(mapping, _):
            handleRedoEntryFailure(mapping, entryPoint: entryPoint)
        case .loaded:
            handleRedoEntryFailure(RedoLatestEntryPoint.noRedoMapping, entryPoint: entryPoint)
        case let .failed(mapping):
            handleRedoEntryFailure(mapping, entryPoint: entryPoint)
        case .loading, .undoing, .undoFailed, .undone, .redoing:
            break
        }
    }

    @MainActor
    private func handleRedoEntryFailure(_ mapping: CoreErrorMappingSnapshot?, entryPoint: RedoLatestEntryPoint) {
        let mapping = mapping ?? RedoLatestEntryPoint.noRedoMapping
        switch entryPoint {
        case .commandPalette:
            fileListModel.commandPaletteState = .failed(
                commandPaletteContext(),
                fileListModel.commandPaletteState.snapshot ?? .commandRegistryRecovery(
                    query: fileListModel.commandPaletteQuery
                ),
                mapping
            )
        case .keyboardShortcut:
            fileActionRoutingState.actionLogRefreshFailure = mapping
            fileActionRoutingState.undoHistoryRequest = UndoHistoryActionLog.redoShortcutRequest(
                state: fileActionRoutingState.batchTagUndoState,
                failure: mapping
            )
        }
    }

    @MainActor
    private func closeCommandPaletteIfNeeded(_ entryPoint: RedoLatestEntryPoint) {
        guard entryPoint == .commandPalette else { return }
        closeCommandPalette()
    }

    private func refreshAfterUndoRedo(targets: [String]) {
        let plan = BatchTagUndoRefreshPlan(refreshTargets: targets)
        if plan.refreshesCurrentList {
            Task { await fileListModel.retryCurrentCategory() }
        }
        if plan.refreshesSelectionDetails {
            Task { await fileListModel.retrySelectedFileDetail() }
        }
        if plan.refreshesChangeLog {
            Task { await fileListModel.loadSelectedFileChangeLog() }
        }
        if plan.refreshesUndoActions {
            refreshLatestUndoToast()
        }
    }
}

enum RedoLatestEntryPoint: Equatable {
    case keyboardShortcut
    case commandPalette

    static let noRedoMapping = CoreErrorMappingSnapshot(
        kind: .expiredAction,
        userMessage: L10n.string("No redoable action is available."),
        severity: .medium,
        suggestedAction: L10n.string("Undo an AreaMatrix action before using Redo latest."),
        recoverability: .refreshRequired,
        rawContext: "redo-action-log redo-action-log-core redo-action-log"
    )
}
