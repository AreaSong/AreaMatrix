import SwiftUI

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
            Text(
                // swiftlint:disable:next line_length
                "Existing tags: \(existingTags.isEmpty ? "none" : existingTags.map(\.displayName).joined(separator: ", "))"
            )
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
        .accessibilityIdentifier("ai-tag-suggestions-ai-tags-suggestion-ai-tag-suggestions")
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

    func traceLinks(_ report: AiTagSuggestionReport) -> some View {
        HStack {
            if report.skippedReason == .aiDisabled || report.skippedReason == .featureDisabled {
                Button("Open AI settings", action: onOpenAISettings)
            }
            if let ruleID = privacyRuleID(for: report) {
                Button("View privacy rule") { privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID) }
                    .accessibilityIdentifier("ai-tag-suggestions-ai-privacy-rules-core-view-privacy-rule")
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
    var id: Int64 {
        callLogID
    }
}
