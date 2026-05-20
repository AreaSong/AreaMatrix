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

struct BatchTagUndoToastHost: View {
    let repoPath: String
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onRefreshSelection: () -> Void
    let onRefreshChangeLog: () -> Void
    @Binding var undoState: BatchTagUndoState
    @Binding var actionLogRefreshFailure: CoreErrorMappingSnapshot?

    var body: some View {
        if !undoState.isIdle {
            BatchTagUndoToastView(
                state: undoState,
                actionLogRefreshFailure: actionLogRefreshFailure,
                onUndo: { action in Task { await undo(action) } },
                onDismiss: dismissUndoToast
            )
            .frame(maxWidth: 420)
        }
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
}

struct SearchCommandPaletteRouteView: View {
    let query: String
    let batchAddTagsRoute: BatchAddTagsRoute
    let onOpenBatchAddTags: (BatchAddTagsRoute) -> Void
    let onClose: () -> Void

    var body: some View {
        MainFileActionSheetContainer(title: "Command Palette", pageID: "S2-15") {
            TextField("Search commands", text: .constant(query))
                .textFieldStyle(.roundedBorder)
            Text("Search related commands")
                .font(.callout)
                .foregroundStyle(.secondary)
            commandPaletteBatchAddTagsButton
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .accessibilityIdentifier("S2-15-search-route")
    }

    private var commandPaletteBatchAddTagsButton: some View {
        Button {
            onOpenBatchAddTags(batchAddTagsRoute)
        } label: {
            Label("Add tags...", systemImage: "tag")
        }
        .disabled(batchAddTagsRoute.selectedCount == 0)
        .help(BatchAddTagsEntryPolicy.openHelp(disabledReason: batchAddTagsRoute.disabledReason))
        .accessibilityIdentifier("S2-09-command-palette-add-tags")
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
