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
                    Text(L10n.string("Select an action"))
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
            Label(
                L10n.format("file-actions.undo.action-kind", displayKind(action.kind)),
                systemImage: "clock.arrow.circlepath"
            )
            .font(.headline)
            Text(L10n.plural("file-actions.undo.affected-files", count: Int(action.affectedCount)))
            Text(L10n.format("file-actions.undo.result", action.summary))
                .foregroundStyle(.secondary)
            fileSamples(action.affectedFileNames)
            if !isLatest {
                Text(L10n.string("Undo newer actions first."))
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
                Label(
                    L10n.format("file-actions.redo.action-kind", displayKind(redoAction.kind)),
                    systemImage: "arrow.uturn.forward.circle"
                )
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
            .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-row")
            .accessibilityLabel(source.accessibilityText)
        } else {
            Text(L10n.string("No redoable actions"))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("redo-action-log-redo-action-log-core-redo-empty")
        }
    }

    @ViewBuilder
    private func fileSamples(_ names: [String]) -> some View {
        if !names.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Files"))
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
        .accessibilityLabel(L10n.format(
            "%@, %@, %lld files, %@",
            action.summary,
            timeText,
            action.affectedCount,
            statusText
        ))
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
            if action.canUndo {
                L10n.string("Available")
            } else {
                L10n.string("Blocked")
            }
        case .blocked:
            L10n.string("Blocked")
        case .expired:
            L10n.string("Expired")
        case .executed:
            L10n.string("Executed")
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
        Button(L10n.string("Rename...")) { isPresented = true }
            .help(BatchRenameEntryPolicy.openHelp(disabledReason: disabledReason))
            .accessibilityIdentifier("batch-rename-batch-rename-open")
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
    let aiDependencies: AIFeatureDependencies
    let errorMapper: any CoreErrorMapping
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let state: AITagBatchSuggestionState
    let actions: AITagBatchSuggestionActions
    let onOpenAISettings: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button(L10n.string("AI tag suggestions...")) {
            isPresented = true
            actions.load(selectedFiles)
        }
        .disabled(openDisabledReason != nil)
        .help(openDisabledReason ?? L10n.string("Review AI suggested tags for selected files"))
        .sheet(isPresented: $isPresented) {
            BatchAITagSuggestionSheet(
                repoPath: repoPath,
                aiDependencies: aiDependencies,
                errorMapper: errorMapper,
                selectedFiles: selectedFiles,
                state: state,
                actions: actions,
                onOpenAISettings: onOpenAISettings,
                onClose: { isPresented = false }
            )
        }
        .accessibilityIdentifier("ai-tag-suggestions-ai-tags-suggestion-open-batch-ai-tag-suggestions")
    }

    private var openDisabledReason: String? {
        if selectedCount < 2 { return L10n.string("Select at least two files") }
        return disabledReason
    }
}

struct BatchAITagSuggestionSheet: View {
    let repoPath: String
    let aiDependencies: AIFeatureDependencies
    let errorMapper: any CoreErrorMapping
    let selectedFiles: [FileEntrySnapshot]
    let state: AITagBatchSuggestionState
    let actions: AITagBatchSuggestionActions
    let onOpenAISettings: () -> Void
    let onClose: () -> Void
    @State var callLogRoute: BatchAITagCallLogRoute?
    @State var privacyRuleRoute: AIClassificationPrivacyRuleRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.plural("file-actions.ai-tag-suggestion.review-files", count: selectedFiles.count))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.string("Review before adding tags. AI suggestions are not applied until you accept them."))
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
            Button(L10n.string("Apply tags"), action: actions.apply)
            Button(L10n.string("Cancel"), role: .cancel, action: actions.cancelConfirmation)
        } message: {
            Text(confirmationMessage)
        }
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID,
                feature: .tags,
                lister: aiDependencies.aiCallLogLister,
                errorMapper: errorMapper
            ) {
                callLogRoute = nil
            }
        }
        .sheet(item: $privacyRuleRoute) { route in
            AIClassificationPrivacyRuleReferenceSheet(
                repoPath: repoPath,
                ruleID: route.ruleID,
                bridge: aiDependencies.aiPrivacyRulesManager,
                errorMapper: errorMapper
            ) {
                privacyRuleRoute = nil
            }
        }
        .accessibilityIdentifier("ai-tag-suggestions-ai-tags-suggestion-batch-ai-tag-suggestions")
    }

    var actionBar: some View {
        HStack {
            Button(L10n.string("Accept high confidence")) {
                actions.selectHighConfidence()
                actions.confirm()
            }
            .disabled(!state.hasHighConfidenceApplyCandidates || state.isApplying || state.isLoading || isAIBlocked)
            Button(L10n.string("Accept selected"), action: actions.confirm)
                .disabled(!state.canApplySelectedSuggestions || isAIBlocked)
            Button(L10n.string("Reject selected"), action: actions.clearSelection)
                .disabled(state.review?.selectedTagCount == 0 || state.isApplying || state.isLoading || isAIBlocked)
            if case .applied = state {
                Button(L10n.string("Retry apply"), action: actions.confirm)
                    .disabled(!state.canApplySelectedSuggestions)
            }
            Button(L10n.string("Cancel")) {
                actions.cancel()
                onClose()
            }
        }
    }
}
