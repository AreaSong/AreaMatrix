import SwiftUI

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
        .accessibilityIdentifier("tag-suggestions-tag-suggestions-core-tag-suggestions-panel")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("Tag suggestions"))
                .font(.headline)
            Text(L10n.string("Suggestions come from file name and path keywords. File contents are not read."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L10n.format("file-actions.tag-suggestion.reviewing-file", file.currentName))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if state.isLoading {
            Label(L10n.string("Finding tag suggestions..."), systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
        } else if let failure = state.failure {
            failureView(failure)
        } else if let report = state.report {
            reportContent(report)
        } else {
            Label(L10n.string("Open suggestions to review deterministic candidates."), systemImage: "tag")
                .foregroundStyle(.secondary)
        }
    }

    private func failureView(_ failure: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("Could not generate suggestions"), systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(failure.userMessage)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.string("Retry"), action: onRetry)
                Button(L10n.string("Add tag manually"), action: onAddManually)
                    .accessibilityIdentifier("tag-suggestions-tag-crud-core-add-tag-manually")
            }
        }
    }

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
            L10n.string("tag-suggestion.privacy-review-required") :
            L10n.string("tag-suggestion.local-privacy-safe")
        return Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("No tag suggestions"))
                .font(.callout.weight(.semibold))
            Button(L10n.string("Add tag manually"), action: onAddManually)
                .accessibilityIdentifier("tag-suggestions-tag-crud-core-add-tag-manually")
        }
    }

    private func suggestionList(_ report: TagSuggestionReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(L10n.string("Select all"), action: onSelectAll)
                Button(L10n.string("Clear selection"), action: onClearSelection)
                Spacer()
                Text(L10n.plural("file-actions.tag-suggestion.selected-count", count: state.selectedIDs.count))
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
            Text(L10n.string("Edit selected tags"))
                .font(.headline)
            Text(L10n.string("Editing changes pending tag names only. Nothing is written until Apply edited."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.attentionCount > 0 {
                Text(
                    L10n.plural(
                        "file-actions.tag-suggestion.attention-count",
                        count: session.attentionCount
                    )
                )
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
        .accessibilityIdentifier("tag-suggestions-tag-suggestions-core-edit-selected-tags")
    }

    private func applySummary(_ report: TagSuggestionApplyReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Applied \(report.appliedCount), skipped \(report.skippedCount), failed \(report.failedCount).")
            ForEach(report.itemResults.filter { $0.status == .failed }) { failed in
                Text(
                    failed.error
                        ?? L10n.format("file-actions.tag-suggestion.apply-failed", failed.slug)
                )
                .foregroundStyle(.secondary)
            }
            if report.failedCount > 0 {
                HStack {
                    Button(L10n.string("Retry failed"), action: onRetryFailed)
                        .disabled(!canRetryFailed)
                    Button(L10n.string("Add tag manually"), action: onAddManually)
                        .accessibilityIdentifier("tag-suggestions-tag-crud-core-add-tag-manually-after-failure")
                }
            }
        }
        .font(.caption)
    }

    private var actionBar: some View {
        HStack {
            Button(L10n.string("Ignore"), action: onClose)
            Spacer()
            if let session = state.editSession {
                Button(L10n.string("Cancel edit"), action: onCancelEditing)
                    .disabled(state.isApplying)
                Button(L10n.string("Apply edited"), action: onApplyEdited)
                    .disabled(!canApplyEdited(session))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(L10n.string("Edit selected..."), action: onStartEditing)
                    .disabled(!canStartEdit)
                Button(L10n.string("Apply selected"), action: onApplySelected)
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
                    Text(suggestion.matchStrength.displayName)
                    Text(suggestion.status.displayName)
                }
                .font(.caption)
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(suggestion.source.displayName)
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
        L10n.format(
            "tag-suggestion.accessibility-label",
            suggestion.displayName,
            suggestion.reason,
            suggestion.matchStrength.displayName,
            suggestion.status.displayName,
            isSelected ? L10n.string("Selected") : L10n.string("Not selected")
        )
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
            TextField(L10n.string("displayName"), text: Binding(
                get: { draft.displayName },
                set: onDisplayNameChange
            ))
            .textFieldStyle(.roundedBorder)
            .disabled(fieldsDisabled)
            HStack {
                TextField(L10n.string("slug"), text: Binding(get: { draft.slug }, set: onSlugChange))
                    .textFieldStyle(.roundedBorder)
                    .disabled(fieldsDisabled)
                Button(L10n.string("Regenerate slug"), action: onRegenerateSlug)
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
        L10n.format(
            "tag-suggestion.edit-accessibility-label",
            draft.originalDisplayName,
            draft.reason,
            draft.status.label
        )
    }
}
