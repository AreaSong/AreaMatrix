import SwiftUI

struct UndoPreviewPane: View {
    let action: UndoActionRecordSnapshot?
    let redoAction: RedoActionRecordSnapshot?
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let action {
                undoDetails(action)
                redoSection
            } else {
                redoSection
                if redoAction == nil {
                    Text("Select an action")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(18)
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func undoDetails(_ action: UndoActionRecordSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
        }
    }

    @ViewBuilder
    private var redoSection: some View {
        if let redoAction {
            VStack(alignment: .leading, spacing: 8) {
                Label("Redo: \(displayKind(redoAction.kind))", systemImage: "arrow.uturn.forward.circle")
                    .font(.headline)
                Text(redoAction.summary)
                    .foregroundStyle(.secondary)
                Text("Source undo: \(redoAction.sourceUndoActionID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(statusText(for: redoAction))
                    .font(.caption)
                    .foregroundStyle(redoAction.canRedo ? .green : .secondary)
                fileSamples(redoAction.affectedFileNames)
            }
            .accessibilityIdentifier("S2-22-C2-18-redo-row")
        } else {
            Text("No redoable actions")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S2-22-C2-18-redo-empty")
        }
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

    private func statusText(for action: RedoActionRecordSnapshot) -> String {
        if action.status == .available, action.canRedo {
            return "Available until the next file operation"
        }
        return RedoActionFeedback.disabledReason(for: action)
    }
}

struct UndoHistoryList: View {
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

struct BatchRenameTrigger: View {
    let repoPath: String
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let renamer: any CoreBatchRenaming
    let undoStore: any CoreUndoActionLogging
    let errorMapper: any CoreErrorMapping
    let onApplied: (BatchRenameReportSnapshot) -> Void
    let onUndoStateChange: (BatchTagUndoState) -> Void
    @State private var isPresented = false

    var body: some View {
        Button("Rename...") { isPresented = true }
            .help(BatchRenameEntryPolicy.openHelp(disabledReason: disabledReason))
            .accessibilityIdentifier("S2-14-batch-rename-open")
            .sheet(isPresented: $isPresented) {
                BatchRenameSheet(
                    repoPath: repoPath,
                    fileIDs: fileIDs,
                    selectedFiles: selectedFiles,
                    selectedCount: selectedCount,
                    disabledReason: disabledReason,
                    renamer: renamer,
                    undoStore: undoStore,
                    errorMapper: errorMapper,
                    onApplied: onApplied,
                    onUndoStateChange: onUndoStateChange,
                    onClose: { isPresented = false }
                )
            }
    }
}
