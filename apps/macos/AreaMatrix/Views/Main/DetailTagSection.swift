import SwiftUI

struct DetailTagSection: View {
    let file: FileEntrySnapshot
    let repoPath: String
    let state: DetailTagEditorState
    let suggestionState: DetailTagSuggestionState
    let suggestionPresentationRequest: TagSuggestionPresentationRequest?
    let undoToast: DetailTagUndoToast?
    let disabledReason: MainFileWriteActionDisabledReason?
    let tagActions: MainRepositoryDetailPaneTagActions

    @State private var isPopoverPresented = false
    @State private var isSuggestionsPresented = false
    @State private var isAISuggestionsPresented = false
    @State private var query = ""
    @State private var pendingSubmittedTag: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            tagHeader
            Text("分类决定“放哪儿”，标签决定“怎么横向组织”。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let failure = state.failure {
                tagFailureView(failure.mapping)
            }
            tagUndoToast
        }
        .task(id: file.id) { tagActions.onLoadTags() }
        .onChange(of: state) { _, newState in
            clearCommittedQuery(newState: newState)
        }
        .onChange(of: suggestionPresentationRequest) { _, request in
            presentSuggestionsIfNeeded(request)
        }
        .sheet(isPresented: $isSuggestionsPresented) {
            TagSuggestionsPanel(
                file: file,
                state: suggestionState,
                disabledReason: disabledReason,
                onRetry: tagActions.onRetrySuggestions,
                onToggleSuggestion: tagActions.onToggleSuggestion,
                onSelectAll: tagActions.onSelectAllSuggestions,
                onClearSelection: tagActions.onClearSuggestions,
                onStartEditing: tagActions.onStartEditingSuggestions,
                onCancelEditing: tagActions.onCancelEditingSuggestions,
                onEditDisplayName: tagActions.onEditSuggestionDisplayName,
                onEditSlug: tagActions.onEditSuggestionSlug,
                onRegenerateSlug: tagActions.onRegenerateSuggestionSlug,
                onApplySelected: tagActions.onApplySuggestions,
                onApplyEdited: tagActions.onApplyEditedSuggestions,
                onRetryFailed: tagActions.onRetryFailedSuggestions,
                onAddManually: {
                    isSuggestionsPresented = false
                    isPopoverPresented = true
                    if state.tagSet == nil { tagActions.onLoadTags() }
                },
                onClose: { isSuggestionsPresented = false }
            )
        }
        .sheet(isPresented: $isAISuggestionsPresented) {
            AITagSuggestionsPanel(
                repoPath: repoPath,
                file: file,
                existingTags: state.tagSet?.fileTags ?? [],
                state: tagActions.aiSuggestionState,
                disabledReason: disabledReason,
                onRetry: tagActions.onRetryAISuggestions,
                onToggleSuggestion: tagActions.onToggleAISuggestion,
                onApplySingleSuggestion: tagActions.onApplySingleAISuggestion,
                onSelectHighConfidence: tagActions.onSelectHighConfidenceAISuggestions,
                onClearSelection: tagActions.onClearAISuggestions,
                onStartEditing: tagActions.onStartEditingAISuggestions,
                onCancelEditing: tagActions.onCancelEditingAISuggestions,
                onEditDisplayName: tagActions.onEditAISuggestionDisplayName,
                onEditSlug: tagActions.onEditAISuggestionSlug,
                onRegenerateSlug: tagActions.onRegenerateAISuggestionSlug,
                onApplySelected: tagActions.onApplyAISuggestions,
                onApplyEdited: tagActions.onApplyEditedAISuggestions,
                onRetryFailed: tagActions.onRetryFailedAISuggestions,
                onOpenAISettings: tagActions.onOpenAISettings,
                onClose: { isAISuggestionsPresented = false }
            )
        }
    }

    private var tagHeader: some View {
        HStack(spacing: 8) {
            Text("Tags")
                .font(.caption)
                .foregroundStyle(.secondary)
            tagChips
            addButton
        }
    }

    private var tagChips: some View {
        Group {
            if let tagSet = state.tagSet, !tagSet.fileTags.isEmpty {
                ForEach(tagSet.fileTags) { tag in
                    TagChipView(tag: tag, disabled: disabledReason != nil || state.isLoading) {
                        tagActions.onRemoveTag(tag.value)
                    }
                }
            } else if state.isLoading {
                Text("Loading tags...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("No tags yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addButton: some View {
        Button("+ Add...") {
            isPopoverPresented = true
            if state.tagSet == nil { tagActions.onLoadTags() }
        }
        .disabled(disabledReason != nil)
        .popover(isPresented: $isPopoverPresented) {
            TagEditorPopover(
                query: $query,
                state: state,
                disabledReason: disabledReason,
                onRetry: tagActions.onRetryTags,
                onAddTag: submitTag,
                onOpenSuggestions: openSuggestions,
                onOpenAISuggestions: openAISuggestions,
                onClose: { isPopoverPresented = false }
            )
        }
        .accessibilityIdentifier("tag-crud-tags-add")
    }

    private func openSuggestions() {
        isPopoverPresented = false
        isSuggestionsPresented = true
        tagActions.onLoadSuggestions()
    }

    private func openAISuggestions() {
        isPopoverPresented = false
        isAISuggestionsPresented = true
        if state.tagSet == nil { tagActions.onLoadTags() }
        tagActions.onLoadAISuggestions()
    }

    private func presentSuggestionsIfNeeded(_ request: TagSuggestionPresentationRequest?) {
        guard let request, request.fileID == file.id else { return }
        if request.source == .importResult {
            openAISuggestions()
        } else {
            openSuggestions()
        }
        tagActions.onSuggestionPresentationConsumed(request)
    }

    private func tagFailureView(_ mapping: CoreErrorMappingSnapshot) -> some View {
        HStack(spacing: 8) {
            Label(mapping.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
            Button("Retry", action: tagActions.onRetryTags)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var tagUndoToast: some View {
        if let undoToast, undoToast.belongs(to: file.id) {
            TintedStatusBanner(
                tint: .secondary,
                fillsWidth: false,
                contentPadding: 8,
                backgroundOpacity: 0.12
            ) {
                HStack(spacing: 8) {
                    Label(undoToast.message, systemImage: "arrow.uturn.backward.circle")
                    Button("Undo", action: tagActions.onUndoTagChange)
                    Button("Dismiss", action: tagActions.onDismissTagUndoToast)
                }
                .font(.caption)
            }
        }
    }

    private func submitTag(_ tag: String) {
        pendingSubmittedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        tagActions.onAddTag(tag)
    }

    private func clearCommittedQuery(newState: DetailTagEditorState) {
        guard let pending = pendingSubmittedTag else { return }
        guard !newState.isLoading else { return }

        if DetailTagInputCommitPolicy.shouldClearSubmittedQuery(submittedTag: pending, state: newState) {
            query = ""
        }
        pendingSubmittedTag = nil
    }
}

enum DetailTagInputCommitPolicy {
    static func shouldClearSubmittedQuery(submittedTag: String, state: DetailTagEditorState) -> Bool {
        let normalizedTag = submittedTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case let .loaded(_, tagSet) = state, !normalizedTag.isEmpty else { return false }
        return tagSet.containsFileTag(value: normalizedTag)
    }
}

private struct TagChipView: View {
    let tag: TagRecordSnapshot
    let disabled: Bool
    let onRemove: () -> Void

    var body: some View {
        NeutralCapsuleChip {
            HStack(spacing: 4) {
                Text(tag.displayName)
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.borderless)
                .disabled(disabled)
                .accessibilityLabel("Remove tag \(tag.displayName)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag \(tag.displayName)")
    }
}
