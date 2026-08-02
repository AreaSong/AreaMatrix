import SwiftUI

extension AITagSuggestionsPanel {
    func reportView(_ report: AITagSuggestionReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.format(
                "ai.tagSuggestion.confidenceThreshold",
                String(percent(report.confidenceThreshold)),
                routeLabel(report.route)
            ))
            .font(.caption)
            Text(L10n.format("ai.tagSuggestion.usedFields", usedContextText(report.usedContext)))
                .font(.caption)
                .foregroundStyle(.secondary)
            if report.status == .noSuggestion || report.suggestions.isEmpty {
                Text(report.skippedReason.map(skipReasonText) ?? L10n.string("No tag suggestions for this file."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.suggestions, id: \.suggestionId, content: suggestionRow)
                if let applyReport = state.appliedReport { applySummary(applyReport) }
            }
            if let feedback = state.rejectedFeedback {
                Label(feedback.message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ai-tag-suggestions-ai-tags-suggestion-reject-feedback")
            }
            traceLinks(report)
        }
    }

    func suggestionRow(_ suggestion: AITagSuggestionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(
                    state.selectedIDs.contains(suggestion.suggestionId)
                        ? L10n.string("Reject")
                        : L10n.string("Add")
                ) {
                    if state.selectedIDs.contains(suggestion.suggestionId) {
                        onToggleSuggestion(suggestion.suggestionId)
                    } else {
                        onApplySingleSuggestion(suggestion.suggestionId)
                    }
                }
                .disabled(!AITagSuggestionAction.canApply(suggestion) || state.isApplying)
                Text(suggestion.displayName).font(.callout.weight(.semibold))
                AISuggestionConfidenceBadge(confidence: suggestion.confidence)
                Text(candidateStatusText(suggestion)).foregroundStyle(.secondary)
            }
            Text(L10n.format("ai.tagSuggestion.reason", suggestion.reason)).font(.caption)
            Text(mergeText(suggestion)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format(
            "ai.tagSuggestion.accessibilityLabel",
            suggestion.displayName,
            String(percent(suggestion.confidence))
        ))
    }

    func editRow(_ draft: AITagSuggestionEditDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L10n.string("Display name"), text: Binding(
                get: { draft.displayName },
                set: { onEditDisplayName(draft.suggestionID, $0) }
            ))
            HStack {
                TextField(
                    L10n.string("Slug"),
                    text: Binding(get: { draft.slug }, set: { onEditSlug(draft.suggestionID, $0) })
                )
                Button(L10n.string("Regenerate")) { onRegenerateSlug(draft.suggestionID) }
            }
            if draft.status.preventsApply {
                Text(draft.status.message ?? draft.status.label)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    func applySummary(_ report: AITagSuggestionApplyReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Applied \(report.appliedCount), skipped \(report.skippedCount), failed \(report.failedCount).")
            if report.failedCount > 0 { Button(L10n.string("Retry apply"), action: onRetryFailed) }
        }
        .font(.caption)
    }

    func routeLabel(_ route: AITagSuggestionRouteSnapshot?) -> String {
        switch route {
        case .local: L10n.string("Local")
        case .remote: L10n.string("Remote")
        case nil: L10n.string("No provider")
        }
    }

    func usedContextText(_ fields: [AITagSuggestionInputFieldSnapshot]) -> String {
        fields.isEmpty ? L10n.string("none") : fields.map(aiTagInputFieldText).joined(separator: ", ")
    }

    func aiTagInputFieldText(_ field: AITagSuggestionInputFieldSnapshot) -> String {
        switch field {
        case .fileName: L10n.string("filename")
        case .repoRelativePath: L10n.string("repo-relative path")
        case .extractedTextExcerpt: L10n.string("extracted text")
        case .aiSummary: L10n.string("AI summary")
        case .noteSummary: L10n.string("note summary")
        case .existingTags: L10n.string("existing tags")
        case .tagRegistry: L10n.string("tag registry")
        }
    }

    func skipReasonText(_ reason: AITagSuggestionSkipReasonSnapshot) -> String {
        switch reason {
        case .aiDisabled: L10n.string("AI tag suggestions are off")
        case .featureDisabled: L10n.string("Auto tags are off")
        case .providerUnavailable: L10n.string("AI provider is unavailable")
        case .privacyRule: L10n.string("Skipped by privacy rule")
        case .noEligibleInput: L10n.string("No eligible tag context")
        case .callLogUnavailable: L10n.string("AI call log is unavailable")
        }
    }

    func candidateStatusText(_ suggestion: AITagSuggestionSnapshot) -> String {
        if let reason = suggestion.disabledReason { return reason }
        return switch suggestion.status {
        case .suggested: L10n.string("Suggested")
        case .lowConfidence: L10n.string("Low confidence")
        case .alreadyApplied: L10n.string("Already applied")
        case .invalid: L10n.string("Invalid")
        case .blocked: L10n.string("Blocked")
        }
    }

    func mergeText(_ suggestion: AITagSuggestionSnapshot) -> String {
        switch suggestion.mergeAction {
        case .createTag: L10n.format("ai.tagSuggestion.merge.create", suggestion.slug)
        case .useExistingTag:
            L10n.format("ai.tagSuggestion.merge.useExisting", suggestion.matchedExistingSlug ?? suggestion.slug)
        case .mergeWithExistingTag:
            L10n.format("ai.tagSuggestion.merge.mergeExisting", suggestion.matchedExistingSlug ?? suggestion.slug)
        }
    }

    func percent(_ value: Float) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}
