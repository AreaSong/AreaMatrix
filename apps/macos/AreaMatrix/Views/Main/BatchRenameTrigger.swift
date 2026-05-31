import SwiftUI

struct UndoPreviewPane: View {
    let action: UndoActionRecordSnapshot?
    let redoAction: RedoActionRecordSnapshot?
    let redoSourceUndoAction: UndoActionRecordSnapshot?
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
            let source = RedoUndoSourcePresentation(
                redoAction: redoAction,
                undoActions: redoSourceUndoAction.map { [$0] } ?? []
            )
            VStack(alignment: .leading, spacing: 8) {
                Label("Redo: \(displayKind(redoAction.kind))", systemImage: "arrow.uturn.forward.circle")
                    .font(.headline)
                Text(redoAction.summary)
                    .foregroundStyle(.secondary)
                Text(source.sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(source.statusText)
                    .font(.caption)
                    .foregroundStyle(redoAction.canRedo ? .green : .secondary)
                fileSamples(redoAction.affectedFileNames)
            }
            .accessibilityIdentifier("S2-22-C2-18-redo-row")
            .accessibilityLabel(source.accessibilityText)
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
            action.canUndo ? "Available" : "Blocked"
        case .blocked:
            "Blocked"
        case .expired:
            "Expired"
        case .executed:
            "Executed"
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

struct BatchAITagSuggestionTrigger: View {
    let repoPath: String
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let state: AITagBatchSuggestionState
    let actions: AITagBatchSuggestionActions
    let onOpenAISettings: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button("AI tag suggestions...") {
            isPresented = true
            actions.load(selectedFiles)
        }
        .disabled(openDisabledReason != nil)
        .help(openDisabledReason ?? "Review AI suggested tags for selected files")
        .sheet(isPresented: $isPresented) {
            BatchAITagSuggestionSheet(
                repoPath: repoPath,
                selectedFiles: selectedFiles,
                state: state,
                actions: actions,
                onOpenAISettings: onOpenAISettings,
                onClose: { isPresented = false }
            )
        }
        .accessibilityIdentifier("S3-07-C3-07-open-batch-ai-tag-suggestions")
    }

    private var openDisabledReason: String? {
        if selectedCount < 2 { return "Select at least two files" }
        return disabledReason
    }
}

struct BatchAITagSuggestionSheet: View {
    let repoPath: String
    let selectedFiles: [FileEntrySnapshot]
    let state: AITagBatchSuggestionState
    let actions: AITagBatchSuggestionActions
    let onOpenAISettings: () -> Void
    let onClose: () -> Void
    @State var callLogRoute: BatchAITagCallLogRoute?
    @State var privacyRuleRoute: AIClassificationPrivacyRuleRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review suggested tags for \(selectedFiles.count) files")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Review before adding tags. AI suggestions are not applied until you accept them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            content
            actionBar
        }
        .padding(16)
        .frame(width: 720, alignment: .topLeading)
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { state.isConfirming },
                set: { if !$0 { actions.cancelConfirmation() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apply tags", action: actions.apply)
            Button("Cancel", role: .cancel, action: actions.cancelConfirmation)
        } message: {
            Text(confirmationMessage)
        }
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID,
                feature: .tags
            ) {
                callLogRoute = nil
            }
        }
        .sheet(item: $privacyRuleRoute) { route in
            AIClassificationPrivacyRuleReferenceSheet(repoPath: repoPath, ruleID: route.ruleID) {
                privacyRuleRoute = nil
            }
        }
        .accessibilityIdentifier("S3-07-C3-07-batch-ai-tag-suggestions")
    }

    var actionBar: some View {
        HStack {
            Button("Accept high confidence") {
                actions.selectHighConfidence()
                actions.confirm()
            }
            .disabled(!state.hasHighConfidenceApplyCandidates || state.isApplying || state.isLoading || isAIBlocked)
            Button("Accept selected", action: actions.confirm)
                .disabled(!state.canApplySelectedSuggestions || isAIBlocked)
            Button("Reject selected", action: actions.clearSelection)
                .disabled(state.review?.selectedTagCount == 0 || state.isApplying || state.isLoading || isAIBlocked)
            if case .applied = state {
                Button("Retry apply", action: actions.confirm)
                    .disabled(!state.canApplySelectedSuggestions)
            }
            Button("Cancel") {
                actions.cancel()
                onClose()
            }
        }
    }
}
