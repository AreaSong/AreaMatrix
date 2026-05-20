import SwiftUI

struct DetailTagSection: View {
    let file: FileEntrySnapshot
    let state: DetailTagEditorState
    let undoToast: DetailTagUndoToast?
    let disabledReason: MainFileWriteActionDisabledReason?
    let onLoadTags: () -> Void
    let onRetryTags: () -> Void
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onUndoTagChange: () -> Void
    let onDismissUndoToast: () -> Void

    @State private var isPopoverPresented = false
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
        .task(id: file.id) { onLoadTags() }
        .onChange(of: state) { _, newState in
            clearCommittedQuery(newState: newState)
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
                        onRemoveTag(tag.value)
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
            if state.tagSet == nil { onLoadTags() }
        }
        .disabled(disabledReason != nil)
        .popover(isPresented: $isPopoverPresented) {
            TagEditorPopover(
                query: $query,
                state: state,
                disabledReason: disabledReason,
                onRetry: onRetryTags,
                onAddTag: submitTag,
                onClose: { isPopoverPresented = false }
            )
        }
        .accessibilityIdentifier("S2-07-tags-add")
    }

    private func tagFailureView(_ mapping: CoreErrorMappingSnapshot) -> some View {
        HStack(spacing: 8) {
            Label(mapping.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
            Button("Retry", action: onRetryTags)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var tagUndoToast: some View {
        if let undoToast, undoToast.belongs(to: file.id) {
            HStack(spacing: 8) {
                Label(undoToast.message, systemImage: "arrow.uturn.backward.circle")
                Button("Undo", action: onUndoTagChange)
                Button("Dismiss", action: onDismissUndoToast)
            }
            .font(.caption)
            .padding(8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func submitTag(_ tag: String) {
        pendingSubmittedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        onAddTag(tag)
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
                Button("Suggestions...", action: {})
                    .disabled(true)
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

struct SearchTagFacetPicker: View {
    @Binding var filters: SearchFilterStateSnapshot
    var facetsState: MainSearchFacetsState
    var onRetry: () -> Void
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filter by tags")
                .font(.callout.weight(.semibold))
            TextField("Search tags", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityIdentifier("S2-08-tag-search")
            SelectedTagChips(filters: $filters, tagFacets: tagFacets)
            TagMatchModeControl(filters: $filters)
            tagList
            tagFooter
        }
        .accessibilityIdentifier("S2-08-tags-filter")
        .onAppear { isSearchFocused = true }
    }

    @ViewBuilder
    private var tagList: some View {
        if let error = facetsState.errorMapping {
            HStack(spacing: 8) {
                Text("Could not load tags")
                Button("Retry", action: onRetry)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Could not load tags. \(error.userMessage)")
        } else if facetsState.isLoading, tagFacets.isEmpty {
            Text("Loading tags...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if tagFacets.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("No tags yet")
                Text("Add tags from file detail or batch actions.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if visibleTagFacets.isEmpty {
            Text("No matching tags")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            tagOptions
        }
    }

    private var tagOptions: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleTagFacets) { option in
                Toggle(isOn: Binding(
                    get: { option.isSelected(in: filters) },
                    set: { _ in filters = SearchFilterEditing.togglingTag(option.value, in: filters) }
                )) {
                    TagFacetRow(option: option)
                }
                .disabled(option.disabled || facetsState.errorMapping != nil)
                .accessibilityLabel(option.accessibilityLabel(isSelected: option.isSelected(in: filters)))
            }
        }
    }

    private var tagFooter: some View {
        HStack {
            Button("Clear all") {
                filters = SearchFilterEditing.removing(.tags, from: filters)
            }
            .disabled(filters.tags.isEmpty)
            Spacer()
            if facetsState.isLoading, !tagFacets.isEmpty {
                Text("Loading tags...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tagFacets: [SearchFacetCountSnapshot] { facetsState.facets?.tags ?? [] }

    private var visibleTagFacets: [SearchFacetCountSnapshot] {
        TagFacetFiltering.visibleTags(query: query, facets: tagFacets)
    }
}

private struct TagFacetRow: View {
    var option: SearchFacetCountSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(option.disabled ? 0.25 : 0.75))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(option.label)
            Spacer()
            Text(option.countDisplayText)
                .foregroundStyle(.secondary)
        }
    }
}

struct SelectedTagChips: View {
    @Binding var filters: SearchFilterStateSnapshot
    var tagFacets: [SearchFacetCountSnapshot]

    var body: some View {
        if filters.tags.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters.tags, id: \.self) { tag in
                        Button {
                            filters = SearchFilterEditing.removingTag(tag, from: filters)
                        } label: {
                            Label(label(for: tag), systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Remove tag filter \(label(for: tag))")
                    }
                }
            }
            .accessibilityLabel("Selected tags \(filters.tags.joined(separator: ", "))")
        }
    }

    private func label(for tag: String) -> String {
        tagFacets.first { $0.value.caseInsensitiveCompare(tag) == .orderedSame }?.label ?? tag
    }
}

private struct TagMatchModeControl: View {
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Tag match mode", selection: Binding(
                get: { filters.tagMatchMode },
                set: { filters = SearchFilterEditing.settingTagMatchMode($0, in: filters) }
            )) {
                Text("Any").tag(SearchTagMatchModeSnapshot.any)
                Text("All").tag(SearchTagMatchModeSnapshot.all)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tag match mode")
            .accessibilityValue(filters.tagMatchMode.accessibilityText)
            if filters.tags.count == 1 {
                Text("Any and All match the same single selected tag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum TagFacetFiltering {
    static func visibleTags(query: String, facets: [SearchFacetCountSnapshot]) -> [SearchFacetCountSnapshot] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return facets }
        return facets.filter { facet in
            facet.value.localizedCaseInsensitiveContains(normalizedQuery) ||
                facet.label.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

extension SearchFacetCountSnapshot {
    var countDisplayText: String {
        disabled ? "--" : "\(count) files"
    }

    func isSelected(in filters: SearchFilterStateSnapshot) -> Bool {
        filters.tags.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    func accessibilityLabel(isSelected: Bool) -> String {
        let state = isSelected ? "selected" : "not selected"
        let availability = disabled ? "disabled" : countDisplayText
        return "\(label), \(availability), \(state)"
    }
}

private extension SearchTagMatchModeSnapshot {
    var accessibilityText: String {
        switch self {
        case .any:
            "Any selected tag"
        case .all:
            "All selected tags"
        }
    }
}
