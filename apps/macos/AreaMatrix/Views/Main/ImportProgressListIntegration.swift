import SwiftUI

struct ImportProgressListRow: Identifiable, Equatable {
    let item: ImportBatchProgressSnapshot.Item

    var id: String {
        item.id
    }

    var displayName: String {
        let name = (item.targetPath as NSString).lastPathComponent
        return name.isEmpty ? item.targetPath : name
    }

    var categoryPathDisplay: String {
        let directory = (item.targetPath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? item.targetPath : directory
    }

    var sourcePath: String {
        item.sourcePath
    }

    var targetPath: String {
        item.targetPath
    }

    var phaseText: String {
        item.phase.rawValue
    }

    var errorMessage: String? {
        item.errorMessage
    }
}

struct ImportProgressTableView: View {
    let rows: [ImportProgressListRow]
    @Binding var selection: Set<String>

    var body: some View {
        if !rows.isEmpty {
            Table(rows, selection: $selection) {
                TableColumn("Importing") { row in
                    Text(row.displayName)
                        .lineLimit(1)
                }
                TableColumn("Target") { row in
                    Text(row.categoryPathDisplay)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                TableColumn("Status") { row in
                    Text(row.phaseText)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 96, idealHeight: tableHeight, maxHeight: tableHeight)
        }
    }

    private var tableHeight: CGFloat {
        CGFloat(min(max(rows.count, 1), 4)) * 34 + 34
    }
}

struct ImportProgressDetailPane: View {
    let row: ImportProgressListRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Import details", systemImage: row.systemImage)
                    .font(.headline)
                metadataRows
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Status", row.phaseText)
            metadataRow("Target", row.targetPath)
            metadataRow("Source", row.sourcePath)
            if let errorMessage = row.errorMessage {
                metadataRow("Error", errorMessage)
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(4)
        }
    }
}

extension MainRepositoryContentView {
    var selectedImportProgressRow: ImportProgressListRow? {
        guard let id = selectedImportProgressIDs.first else { return nil }
        return importProgressRows.first { $0.id == id }
    }
}

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
    let errorMapper: any CoreErrorMapping
    let onRefreshSelection: () -> Void
    let onRefreshChangeLog: () -> Void
    let onRefreshCurrentList: () -> Void
    let onOpenHistory: (UndoToastHistoryRequest) -> Void
    @Binding var undoState: BatchTagUndoState
    @Binding var actionLogRefreshFailure: CoreErrorMappingSnapshot?

    var body: some View {
        Group {
            if !undoState.isIdle {
                BatchTagUndoToastView(
                    state: undoState,
                    actionLogRefreshFailure: actionLogRefreshFailure,
                    onUndo: { action in Task { await undo(action) } },
                    onOpenHistory: openHistory,
                    onDismiss: dismissUndoToast
                )
                .frame(maxWidth: 420)
            }
        }
        .task(id: repoPath) { await loadLatestUndoAction() }
        .onKeyPress("z", phases: .down) { event in
            guard event.modifiers.contains(.command) else { return .ignored }
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
            undoState = .unavailable(reason: "Undo action finished without a result.")
            return
        }

        undoState = .undone(result)
        await refreshAfterUndo(result)
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
    }

    private func dismissUndoToast() {
        undoState = .idle
        actionLogRefreshFailure = nil
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
        MainFileActionSheetContainer(title: title, pageID: "S2-10") {
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
                    Button("Close", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(width: 420)
        .accessibilityIdentifier("S2-10-C2-07-undo-history-route")
    }

    private var title: String {
        request.source == .viewDetails ? "Undo Details" : "Undo History"
    }

    private var message: String {
        request.source == .viewDetails ?
            "Undo details will open in Undo History." :
            "Undo History will show recent undo actions."
    }

    private var systemImage: String {
        request.source == .viewDetails ? "exclamationmark.triangle" : "clock.arrow.circlepath"
    }
}

struct CommandPaletteSmartListTarget: Equatable, Identifiable {
    let savedSearch: SavedSearchSnapshot

    var id: Int64 { savedSearch.id }
    var title: String { savedSearch.name }
    var systemImage: String { savedSearch.icon ?? "line.3.horizontal.decrease.circle" }
    var helpText: String { "Open Smart List" }
    var accessibilityIdentifier: String { "S2-15-C2-04-smart-list-\(savedSearch.id)" }

    static func matching(_ savedSearches: [SavedSearchSnapshot], query: String) -> [CommandPaletteSmartListTarget] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = savedSearches.filter { saved in
            trimmed.isEmpty ||
                saved.name.localizedCaseInsensitiveContains(trimmed) ||
                saved.query.query.localizedCaseInsensitiveContains(trimmed)
        }
        return filtered.map(CommandPaletteSmartListTarget.init(savedSearch:))
    }
}

struct SearchCommandPaletteRouteView: View {
    @Binding var query: String
    let state: CommandPaletteLoadState
    var smartLists: [SavedSearchSnapshot] = []
    let onLoad: () -> Void
    var onOpenSmartList: (SavedSearchSnapshot) -> Void = { _ in }
    let onExecuteTarget: (CommandTargetSnapshot) -> Void
    let onClose: () -> Void

    var body: some View {
        CommandPaletteView(
            query: $query,
            state: state,
            smartLists: smartLists,
            onLoad: onLoad,
            onOpenSmartList: onOpenSmartList,
            onExecuteTarget: onExecuteTarget,
            onClose: onClose
        )
        .accessibilityIdentifier("S2-15-search-route")
    }
}

extension MainRepositoryContentView {
    func commandPaletteBatchDeleteRoute() -> BatchDeleteRoute {
        CommandPaletteBatchRouteBuilder.batchDeleteRoute(
            selectedFileIDs: selectedFileIDs,
            visibleFiles: visibleFiles,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func commandPaletteBatchRenameRoute() -> BatchRenameRoute {
        CommandPaletteBatchRouteBuilder.batchRenameRoute(
            selectedFileIDs: selectedFileIDs,
            visibleFiles: visibleFiles,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }
}

private extension ImportProgressListRow {
    var systemImage: String {
        switch item.phase {
        case .done:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .pending:
            "clock"
        case .copying, .moving, .hashing, .classifying, .writingIndex:
            "arrow.triangle.2.circlepath"
        }
    }
}
