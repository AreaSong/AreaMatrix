import SwiftUI

struct TagEditorPopover: View {
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
                .accessibilityIdentifier("tag-crud-tag-search-create")
            if shouldShowValidationMessage, let tagValidationMessage {
                Text(tagValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            popoverStatus
            tagList
            HStack {
                Button("Suggestions...", action: onOpenSuggestions)
                    .accessibilityIdentifier("tag-suggestions-tag-suggestions-core-open-tag-suggestions")
                Button("AI suggestions...", action: onOpenAISuggestions)
                    .accessibilityIdentifier("ai-tag-suggestions-ai-tags-suggestion-open-ai-tag-suggestions")
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
            Text(reason.message)
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
                Text(state.tagSet == nil ? L10n.string("Could not load tags") : L10n.string("No tags yet"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if canCreateTag {
                Button(L10n.format("detail.tag.create", normalizedQuery)) {
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
        if tag.isEmpty { return L10n.string("Tag is empty.") }
        if tag.count > 64 { return L10n.string("Tag is too long.") }
        if tag.contains("/") || tag.contains(":") || tag.contains("\0") {
            return L10n.string("Tag contains illegal characters.")
        }
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
