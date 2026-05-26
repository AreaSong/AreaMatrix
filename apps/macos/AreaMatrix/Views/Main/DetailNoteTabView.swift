import SwiftUI

struct DetailNoteTabView: View {
    @ObservedObject var model: DetailNoteModel
    let file: FileEntrySnapshot
    let writeBlock: MainDetailNoteWriteBlock?
    let onOpenNoteFile: (String) -> Void

    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            stateContent
        }
        .task(id: file.id) {
            await model.load(file: file, writeBlock: writeBlock)
        }
        .onChange(of: writeBlock) { _, block in
            model.updateWriteBlock(block)
        }
        .onChange(of: model.editorFocusRequest) { _, isRequested in
            guard isRequested else { return }
            isEditorFocused = true
            model.consumeEditorFocusRequest()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Note")
                .font(.headline)
            Spacer()
            if let saveStatus = model.state.saveStatus {
                NoteSaveStatusView(status: saveStatus)
            }
            Button {
                if let notePath = model.noteSidecarRelativePath {
                    onOpenNoteFile(notePath)
                }
            } label: {
                Label("Open note file", systemImage: "doc.text")
            }
            .disabled(!model.canOpenNoteFile)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .notLoaded, .loading:
            noteLoadingView
        case .empty:
            emptyState
        case .editing:
            editorState
        case let .failed(_, error, _):
            noteLoadError(error)
        }
    }

    private var noteLoadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading note...")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有笔记")
                .font(.headline)
            Text("为这个文件添加上下文、处理状态或关联信息。")
                .foregroundStyle(.secondary)
            if let message = model.state.writeBlock?.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Create Note", action: model.createNote)
                .disabled(model.state.writeBlock != nil)
        }
        .accessibilityElement(children: .contain)
    }

    private var editorState: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message = model.state.writeBlock?.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: Binding(
                get: { model.noteText },
                set: { model.updateDraft($0) }
            ))
            .font(.body)
            .frame(minHeight: 180)
            .accessibilityLabel("Companion note")
            .disabled(model.state.writeBlock != nil)
            .focused($isEditorFocused)
            if let error = model.state.saveStatus?.failedError {
                saveErrorView(error)
            }
            if !model.canOpenNoteFile {
                Text("Save the note before opening the sidecar file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func noteLoadError(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("无法加载笔记", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await model.retryLoad() }
            }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .accessibilityElement(children: .contain)
    }

    private func saveErrorView(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("无法保存笔记", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await model.retrySave() }
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}

private struct NoteSaveStatusView: View {
    let status: MainDetailNoteSaveStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel("Note save status \(status.title)")
    }

    private var color: Color {
        switch status {
        case .saved:
            .secondary
        case .saving:
            .blue
        case .unsaved, .failed:
            .orange
        }
    }
}

struct TagSuggestionsPanel: View {
    let file: FileEntrySnapshot
    let state: DetailTagSuggestionState
    let disabledReason: MainFileWriteActionDisabledReason?
    let onRetry: () -> Void
    let onToggleSuggestion: (String) -> Void
    let onSelectAll: () -> Void
    let onClearSelection: () -> Void
    let onStartEditing: () -> Void
    let onCancelEditing: () -> Void
    let onEditDisplayName: (String, String) -> Void
    let onEditSlug: (String, String) -> Void
    let onRegenerateSlug: (String) -> Void
    let onApplySelected: () -> Void
    let onApplyEdited: () -> Void
    let onRetryFailed: () -> Void
    let onAddManually: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stateContent
            actionBar
        }
        .padding(16)
        .frame(width: 420, alignment: .topLeading)
        .accessibilityIdentifier("S2-23-C2-19-tag-suggestions-panel")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tag suggestions")
                .font(.headline)
            Text("Suggestions come from file name and path keywords. File contents are not read.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Reviewing \(file.currentName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if state.isLoading {
            Label("Finding tag suggestions...", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        } else if let failure = state.failure {
            failureView(failure)
        } else if let report = state.report {
            reportContent(report)
        } else {
            Label("Open suggestions to review deterministic candidates.", systemImage: "tag")
                .foregroundStyle(.secondary)
        }
    }

    private func failureView(_ failure: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Could not generate suggestions", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(failure.userMessage)
                .foregroundStyle(.secondary)
            HStack {
                Button("Retry", action: onRetry)
                Button("Add tag manually", action: onAddManually)
                    .accessibilityIdentifier("S2-23-C2-05-add-tag-manually")
            }
        }
    }

    @ViewBuilder
    private func reportContent(_ report: TagSuggestionReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            privacyStatus(report)
            if let session = state.editSession {
                editMode(session)
            } else if report.suggestions.isEmpty {
                emptyState
            } else {
                suggestionList(report)
            }
            if let applyReport = state.appliedReport {
                applySummary(applyReport)
            }
        }
    }

    private func privacyStatus(_ report: TagSuggestionReportSnapshot) -> some View {
        let status = report.contentsRead || report.aiUsed || report.networkUsed ?
            "Privacy boundary needs review." :
            "Non-AI suggestions. No content or network access."
        return Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No tag suggestions")
                .font(.callout.weight(.semibold))
            Button("Add tag manually", action: onAddManually)
                .accessibilityIdentifier("S2-23-C2-05-add-tag-manually")
        }
    }

    private func suggestionList(_ report: TagSuggestionReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Select all", action: onSelectAll)
                Button("Clear selection", action: onClearSelection)
                Spacer()
                Text("\(state.selectedIDs.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(report.suggestions) { suggestion in
                SuggestedTagRow(
                    suggestion: suggestion,
                    isSelected: state.selectedIDs.contains(suggestion.suggestionID),
                    isBusy: state.isApplying,
                    onToggle: { onToggleSuggestion(suggestion.suggestionID) }
                )
            }
        }
    }

    private func editMode(_ session: TagSuggestionEditSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit selected tags")
                .font(.headline)
            Text("Editing changes pending tag names only. Nothing is written until Apply edited.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.attentionCount > 0 {
                Text("\(session.attentionCount) tags need attention before applying.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(session.drafts) { draft in
                SuggestedTagEditRow(
                    draft: draft,
                    isBusy: state.isApplying,
                    isReadOnly: disabledReason != nil,
                    onDisplayNameChange: { onEditDisplayName(draft.suggestionID, $0) },
                    onSlugChange: { onEditSlug(draft.suggestionID, $0) },
                    onRegenerateSlug: { onRegenerateSlug(draft.suggestionID) }
                )
            }
        }
        .accessibilityIdentifier("S2-23-C2-19-edit-selected-tags")
    }

    private func applySummary(_ report: TagSuggestionApplyReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Applied \(report.appliedCount), skipped \(report.skippedCount), failed \(report.failedCount).")
            ForEach(report.itemResults.filter { $0.status == .failed }) { failed in
                Text(failed.error ?? "\(failed.slug) could not be applied.")
                    .foregroundStyle(.secondary)
            }
            if report.failedCount > 0 {
                HStack {
                    Button("Retry failed", action: onRetryFailed)
                        .disabled(!canRetryFailed)
                    Button("Add tag manually", action: onAddManually)
                        .accessibilityIdentifier("S2-23-C2-05-add-tag-manually-after-failure")
                }
            }
        }
        .font(.caption)
    }

    private var actionBar: some View {
        HStack {
            Button("Ignore", action: onClose)
            Spacer()
            if let session = state.editSession {
                Button("Cancel edit", action: onCancelEditing)
                    .disabled(state.isApplying)
                Button("Apply edited", action: onApplyEdited)
                    .disabled(!canApplyEdited(session))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Edit selected...", action: onStartEditing)
                    .disabled(!canStartEdit)
                Button("Apply selected", action: onApplySelected)
                    .disabled(!canApply)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var canApply: Bool {
        disabledReason == nil &&
            !state.isLoading &&
            !state.isApplying &&
            !DetailTagSuggestionAction.selectedApplyItems(in: state).isEmpty
    }

    private var canStartEdit: Bool {
        !state.isLoading &&
            !state.isApplying &&
            !state.selectedIDs.isEmpty
    }

    private func canApplyEdited(_ session: TagSuggestionEditSession) -> Bool {
        disabledReason == nil &&
            !state.isLoading &&
            !state.isApplying &&
            session.canApply
    }

    private var canRetryFailed: Bool {
        disabledReason == nil &&
            !state.isLoading &&
            !state.isApplying &&
            !DetailTagSuggestionAction.retryFailedItems(in: state).isEmpty
    }
}

private struct SuggestedTagRow: View {
    let suggestion: TagSuggestionSnapshot
    let isSelected: Bool
    let isBusy: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(suggestion.displayName)
                        .font(.callout.weight(.semibold))
                    Text(suggestion.matchStrength.rawValue)
                    Text(suggestion.status.rawValue)
                }
                .font(.caption)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestion.source.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let reason = suggestion.disabledReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isBusy || !suggestion.canApply)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        "\(suggestion.displayName), \(suggestion.reason), \(suggestion.matchStrength.rawValue), " +
            "\(suggestion.status.rawValue), \(isSelected ? "selected" : "not selected")"
    }
}

private struct SuggestedTagEditRow: View {
    let draft: TagSuggestionEditDraft
    let isBusy: Bool
    let isReadOnly: Bool
    let onDisplayNameChange: (String) -> Void
    let onSlugChange: (String) -> Void
    let onRegenerateSlug: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(draft.originalDisplayName)
                    .font(.callout.weight(.semibold))
                Text(draft.status.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("displayName", text: Binding(
                get: { draft.displayName },
                set: onDisplayNameChange
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(fieldsDisabled)
            HStack {
                TextField("slug", text: Binding(get: { draft.slug }, set: onSlugChange))
                    .textFieldStyle(.roundedBorder)
                    .disabled(fieldsDisabled)
                Button("Regenerate slug", action: onRegenerateSlug)
                    .disabled(fieldsDisabled)
            }
            Text(draft.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = draft.status.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var fieldsDisabled: Bool {
        isBusy || isReadOnly || draft.status == .applied
    }

    private var accessibilityLabel: String {
        "\(draft.originalDisplayName), \(draft.reason), \(draft.status.label)"
    }
}
