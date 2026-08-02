import SwiftUI

struct AITagSuggestionsPanel: View {
    let repoPath: String
    let aiDependencies: AIFeatureDependencies
    let errorMapper: any CoreErrorMapping
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
            Text(L10n.string("Review suggested tags")).font(.headline).accessibilityAddTraits(.isHeader)
            Text(L10n.string("Review before adding tags. AI suggestions are not applied until you accept them."))
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
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID,
                feature: .tags,
                lister: aiDependencies.aiCallLogLister,
                errorMapper: errorMapper
            ) { callLogRoute = nil }
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
        .accessibilityIdentifier("ai-tag-suggestions-ai-tags-suggestion-ai-tag-suggestions")
    }

    @ViewBuilder private var content: some View {
        if state.isLoading {
            ProgressView("Loading suggested tags...")
        } else if let failure = state.failure {
            Label(L10n.string("Tags could not be applied."), systemImage: "exclamationmark.triangle")
            Text(failure.userMessage).foregroundStyle(.secondary)
            Button(L10n.string("Retry"), action: onRetry)
        } else if let session = state.editSession {
            ForEach(session.drafts) { draft in editRow(draft) }
        } else if let report = state.report {
            reportView(report)
        } else {
            Text(L10n.string("No AI tag suggestions loaded.")).foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button(L10n.string("Accept high confidence")) { onSelectHighConfidence(); onApplySelected() }
                .disabled(state.isApplying || disabledReason != nil || !state.hasHighConfidenceApplyCandidates)
            Button(L10n.string("Accept selected")) { state.editSession == nil ? onApplySelected() : onApplyEdited() }
                .disabled(!state.canApplySelectedSuggestions || state.isApplying || disabledReason != nil)
            Button(L10n.string("Edit selected"), action: onStartEditing)
                .disabled(!state.canEditSelectedSuggestions || state.isApplying || disabledReason != nil)
            Button(L10n.string("Reject selected"), action: onClearSelection)
                .disabled(state.selectedIDs.isEmpty || state.isApplying)
            Button(L10n.string("Cancel"), action: onClose)
        }
    }

    func traceLinks(_ report: AITagSuggestionReportSnapshot) -> some View {
        HStack {
            if report.skippedReason == .aiDisabled || report.skippedReason == .featureDisabled {
                Button(L10n.string("Open AI settings"), action: onOpenAISettings)
            }
            if let ruleID = privacyRuleID(for: report) {
                Button(L10n.string("View privacy rule")) {
                    privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                }
                .accessibilityIdentifier("ai-tag-suggestions-ai-privacy-rules-core-view-privacy-rule")
            }
            if let callLogID = report.callLogId {
                Button(L10n.string("View AI call")) { callLogRoute = AITagCallLogRoute(callLogID: callLogID) }
            }
        }
    }

    func privacyRuleID(for report: AITagSuggestionReportSnapshot) -> String? {
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
