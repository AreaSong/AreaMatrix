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
        .accessibilityIdentifier("S2-07-tags-add")
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
            HStack(spacing: 8) {
                Label(undoToast.message, systemImage: "arrow.uturn.backward.circle")
                Button("Undo", action: tagActions.onUndoTagChange)
                Button("Dismiss", action: tagActions.onDismissTagUndoToast)
            }
            .font(.caption)
            .padding(8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
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
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag \(tag.displayName)")
    }
}

private struct TagEditorPopover: View {
    @Binding var query: String
    let state: DetailTagEditorState
    let disabledReason: MainFileWriteActionDisabledReason?
    let onRetry: () -> Void
    let onAddTag: (String) -> Void
    let onOpenSuggestions: () -> Void
    let onOpenAISuggestions: () -> Void
    let onClose: () -> Void

    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search or create tag...", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .disabled(disabledReason != nil)
                .onSubmit(performSubmit)
                .accessibilityIdentifier("S2-07-tag-search-create")
            if shouldShowValidationMessage, let tagValidationMessage {
                Text(tagValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            popoverStatus
            tagList
            HStack {
                Button("Suggestions...", action: onOpenSuggestions)
                    .accessibilityIdentifier("S2-23-C2-19-open-tag-suggestions")
                Button("AI suggestions...", action: onOpenAISuggestions)
                    .accessibilityIdentifier("S3-07-C3-07-open-ai-tag-suggestions")
                Spacer()
                Button("Close", action: onClose)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { isInputFocused = true }
    }

    @ViewBuilder
    private var popoverStatus: some View {
        if state.isLoading {
            Text("Loading tags...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let failure = state.failure {
            HStack(spacing: 8) {
                Text(failure.mapping.userMessage)
                Button("Retry", action: onRetry)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let reason = disabledReason {
            Text(reason.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var tagList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(candidateTags) { tag in
                TagSuggestionRow(tag: tag) {
                    guard !tag.selected, !tag.disabled else { return }
                    onAddTag(tag.value)
                }
            }
            if candidateTags.isEmpty {
                Text(state.tagSet == nil ? "Could not load tags" : "No tags yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if canCreateTag {
                Button("Create \"\(normalizedQuery)\"") {
                    onAddTag(normalizedQuery)
                }
            }
        }
    }

    private var candidateTags: [TagRecordSnapshot] {
        let tags = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?
            state.tagSet?.recentTags ?? [] :
            state.tagSet?.availableTags ?? []
        let normalized = normalizedQuery
        guard !normalized.isEmpty else { return tags }
        return tags.filter { tag in
            tag.value.localizedCaseInsensitiveContains(normalized) ||
                tag.displayName.localizedCaseInsensitiveContains(normalized)
        }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreateTag: Bool {
        guard disabledReason == nil, !state.isLoading, tagValidationMessage == nil else { return false }
        return state.tagSet?.availableTags.contains { tag in
            tag.value.caseInsensitiveCompare(normalizedQuery) == .orderedSame
        } == false
    }

    private var shouldShowValidationMessage: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var tagValidationMessage: String? {
        let tag = normalizedQuery
        if tag.isEmpty { return "Tag is empty." }
        if tag.count > 64 { return "Tag is too long." }
        if tag.contains("/") || tag.contains(":") || tag.contains("\0") { return "Tag contains illegal characters." }
        return nil
    }

    private func performSubmit() {
        guard let first = candidateTags.first(where: { !$0.selected && !$0.disabled }) else {
            if canCreateTag { onAddTag(normalizedQuery) }
            return
        }
        onAddTag(first.value)
    }
}

private struct TagSuggestionRow: View {
    let tag: TagRecordSnapshot
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(tag.displayName)
                Spacer()
                if tag.selected {
                    Text("已添加")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(tag.fileCount)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(tag.selected || tag.disabled)
    }
}

struct AITagSuggestionsPanel: View {
    let repoPath: String
    let file: FileEntrySnapshot
    let existingTags: [TagRecordSnapshot]
    let state: AITagSuggestionState
    let disabledReason: MainFileWriteActionDisabledReason?
    let onRetry: () -> Void
    let onToggleSuggestion: (String) -> Void
    let onApplySingleSuggestion: (String) -> Void
    let onSelectHighConfidence: () -> Void
    let onClearSelection: () -> Void
    let onStartEditing: () -> Void
    let onCancelEditing: () -> Void
    let onEditDisplayName: (String, String) -> Void
    let onEditSlug: (String, String) -> Void
    let onRegenerateSlug: (String) -> Void
    let onApplySelected: () -> Void
    let onApplyEdited: () -> Void
    let onRetryFailed: () -> Void
    let onOpenAISettings: () -> Void
    let onClose: () -> Void
    @State private var callLogRoute: AITagCallLogRoute?
    @State private var privacyRuleRoute: AIClassificationPrivacyRuleRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review suggested tags").font(.headline).accessibilityAddTraits(.isHeader)
            Text("Review before adding tags. AI suggestions are not applied until you accept them.")
                .font(.caption).foregroundStyle(.secondary)
            Text("File: \(file.currentName)")
            Text("Current path: \(file.path)").foregroundStyle(.secondary)
            Text("Existing tags: \(existingTags.isEmpty ? "none" : existingTags.map(\.displayName).joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            content
            actions
        }
        .padding(16)
        .frame(width: 520, alignment: .topLeading)
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(repoPath: repoPath, callLogID: route.callLogID) { callLogRoute = nil }
        }
        .sheet(item: $privacyRuleRoute) { route in
            AIClassificationPrivacyRuleReferenceSheet(repoPath: repoPath, ruleID: route.ruleID) {
                privacyRuleRoute = nil
            }
        }
        .accessibilityIdentifier("S3-07-C3-07-ai-tag-suggestions")
    }

    @ViewBuilder private var content: some View {
        if state.isLoading {
            ProgressView("Loading suggested tags...")
        } else if let failure = state.failure {
            Label("Tags could not be applied.", systemImage: "exclamationmark.triangle")
            Text(failure.userMessage).foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
        } else if let session = state.editSession {
            ForEach(session.drafts) { draft in editRow(draft) }
        } else if let report = state.report {
            reportView(report)
        } else {
            Text("No AI tag suggestions loaded.").foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button("Accept high confidence") { onSelectHighConfidence(); onApplySelected() }
                .disabled(state.isApplying || disabledReason != nil || !state.hasHighConfidenceApplyCandidates)
            Button("Accept selected") { state.editSession == nil ? onApplySelected() : onApplyEdited() }
                .disabled(!state.canApplySelectedSuggestions || state.isApplying || disabledReason != nil)
            Button("Edit selected", action: onStartEditing)
                .disabled(!state.canEditSelectedSuggestions || state.isApplying || disabledReason != nil)
            Button("Reject selected", action: onClearSelection).disabled(state.selectedIDs.isEmpty || state.isApplying)
            Button("Cancel", action: onClose)
        }
    }

    @ViewBuilder func traceLinks(_ report: AiTagSuggestionReport) -> some View {
        HStack {
            if report.skippedReason == .aiDisabled || report.skippedReason == .featureDisabled {
                Button("Open AI settings", action: onOpenAISettings)
            }
            if let ruleID = privacyRuleID(for: report) {
                Button("View privacy rule") { privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID) }
                    .accessibilityIdentifier("S3-07-C3-09-view-privacy-rule")
            }
            if let callLogID = report.callLogId {
                Button("View AI call") { callLogRoute = AITagCallLogRoute(callLogID: callLogID) }
            }
        }
    }

    func privacyRuleID(for report: AiTagSuggestionReport) -> String? {
        guard report.skippedReason == .privacyRule else { return nil }
        return normalizedAITagPrivacyRuleID(from: report.privacyRuleId)
    }
}

func normalizedAITagPrivacyRuleID(from rawRuleID: String?) -> String? {
    var value = rawRuleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    while let prefix = ["rule:", "block:"].first(where: { value.lowercased().hasPrefix($0) }) {
        value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard !value.isEmpty, value != "privacy-rule" else { return nil }
    return value
}

private struct AITagCallLogRoute: Identifiable {
    let callLogID: Int64
    var id: Int64 { callLogID }
}
