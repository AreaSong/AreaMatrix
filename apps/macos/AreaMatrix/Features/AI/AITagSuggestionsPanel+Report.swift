import SwiftUI

extension AITagSuggestionsPanel {
    func reportView(_ report: AiTagSuggestionReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Confidence threshold: \(percent(report.confidenceThreshold))% - \(routeLabel(report.route))")
                .font(.caption)
            Text("Used fields: \(usedContextText(report.usedContext))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if report.status == .noSuggestion || report.suggestions.isEmpty {
                Text(report.skippedReason.map(skipReasonText) ?? "No tag suggestions for this file.")
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

    func suggestionRow(_ suggestion: AiTagSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(state.selectedIDs.contains(suggestion.suggestionId) ? "Reject" : "Add") {
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
            Text("Reason: \(suggestion.reason)").font(.caption)
            Text(mergeText(suggestion)).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(suggestion.displayName), confidence \(percent(suggestion.confidence)) percent")
    }

    func editRow(_ draft: AITagSuggestionEditDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Display name", text: Binding(
                get: { draft.displayName },
                set: { onEditDisplayName(draft.suggestionID, $0) }
            ))
            HStack {
                TextField("Slug", text: Binding(get: { draft.slug }, set: { onEditSlug(draft.suggestionID, $0) }))
                Button("Regenerate") { onRegenerateSlug(draft.suggestionID) }
            }
            if draft.status.preventsApply {
                Text(draft.status.message ?? draft.status.label)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    func applySummary(_ report: AiTagSuggestionApplyReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Applied \(report.appliedCount), skipped \(report.skippedCount), failed \(report.failedCount).")
            if report.failedCount > 0 { Button("Retry apply", action: onRetryFailed) }
        }
        .font(.caption)
    }

    func routeLabel(_ route: AiTagSuggestionRoute?) -> String {
        switch route {
        case .local: "Local"
        case .remote: "Remote"
        case nil: "No provider"
        }
    }

    func usedContextText(_ fields: [AiTagSuggestionInputField]) -> String {
        fields.isEmpty ? "none" : fields.map(aiTagInputFieldText).joined(separator: ", ")
    }

    func aiTagInputFieldText(_ field: AiTagSuggestionInputField) -> String {
        switch field {
        case .fileName: "filename"
        case .repoRelativePath: "repo-relative path"
        case .extractedTextExcerpt: "extracted text"
        case .aiSummary: "AI summary"
        case .noteSummary: "note summary"
        case .existingTags: "existing tags"
        case .tagRegistry: "tag registry"
        }
    }

    func skipReasonText(_ reason: AiTagSuggestionSkipReason) -> String {
        switch reason {
        case .aiDisabled: "AI tag suggestions are off"
        case .featureDisabled: "Auto tags are off"
        case .providerUnavailable: "AI provider is unavailable"
        case .privacyRule: "Skipped by privacy rule"
        case .noEligibleInput: "No eligible tag context"
        case .callLogUnavailable: "AI call log is unavailable"
        }
    }

    func candidateStatusText(_ suggestion: AiTagSuggestion) -> String {
        if let reason = suggestion.disabledReason { return reason }
        return switch suggestion.status {
        case .suggested: "Suggested"
        case .lowConfidence: "Low confidence"
        case .alreadyApplied: "Already applied"
        case .invalid: "Invalid"
        case .blocked: "Blocked"
        }
    }

    func mergeText(_ suggestion: AiTagSuggestion) -> String {
        switch suggestion.mergeAction {
        case .createTag: "Will create tag \(suggestion.slug)"
        case .useExistingTag: "Will use existing tag \(suggestion.matchedExistingSlug ?? suggestion.slug)"
        case .mergeWithExistingTag: "Merge with existing tag \(suggestion.matchedExistingSlug ?? suggestion.slug)"
        }
    }

    func percent(_ value: Float) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}
