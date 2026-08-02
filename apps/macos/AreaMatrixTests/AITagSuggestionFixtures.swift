@testable import AreaMatrix

func aiTagSuggestionAITagReport(
    fileID: Int64,
    status: AITagSuggestionReportStatusSnapshot = .suggested,
    skippedReason: AITagSuggestionSkipReasonSnapshot? = nil,
    suggestions: [AITagSuggestionSnapshot] = []
) -> AITagSuggestionReportSnapshot {
    AITagSuggestionReportSnapshot(
        fileId: fileID,
        status: status,
        suggestions: suggestions,
        route: status == .suggested ? .local : nil,
        modelName: status == .suggested ? "Local tags model" : nil,
        generatedAt: status == .suggested ? 1_700_000_300 : nil,
        usedContext: status == .suggested ? [.fileName, .tagRegistry] : [],
        skippedReason: skippedReason,
        privacyRuleId: skippedReason == .privacyRule ? "rule-confidential" : nil,
        callLogId: 7707,
        requiresUserConfirmation: true,
        confidenceThreshold: 0.8,
        contentsRead: status == .suggested,
        aiUsed: status == .suggested,
        networkUsed: false
    )
}

func aiTagSuggestionAITagSuggestion(
    id: String,
    slug: String,
    confidence: Float,
    selectedByDefault: Bool = true,
    displayName: String? = nil,
    status: AITagSuggestionCandidateStatusSnapshot = .suggested,
    mergeAction: AITagSuggestionMergeActionSnapshot = .createTag,
    matchedExistingSlug: String? = nil,
    disabledReason: String? = nil
) -> AITagSuggestionSnapshot {
    AITagSuggestionSnapshot(
        suggestionId: id,
        slug: slug,
        displayName: displayName ?? slug.prefix(1).uppercased() + slug.dropFirst(),
        confidence: confidence,
        reason: "ai-tag-suggestions ai-tags-suggestion local tag suggestion.",
        status: status,
        mergeAction: mergeAction,
        matchedExistingSlug: matchedExistingSlug,
        selectedByDefault: selectedByDefault,
        disabledReason: disabledReason
    )
}

func aiTagSuggestionApplyReport(fileID: Int64) -> AITagSuggestionApplyReportSnapshot {
    let tag = aiTagSuggestionTag("finance")
    return AITagSuggestionApplyReportSnapshot(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: 1,
        skippedCount: 0,
        failedCount: 0,
        itemResults: [
            AITagSuggestionApplyItemResultSnapshot(
                suggestionId: "ai-tag-finance",
                slug: "finance",
                status: .applied,
                error: nil
            )
        ],
        tagSet: TagSetSnapshot.testFixture(
            fileID: fileID,
            fileTags: [tag],
            availableTags: [tag],
            recentTags: [tag],
            updatedAt: 1_700_000_350
        ),
        undoToken: nil,
        callLogId: 7707,
        refreshTargets: ["tags", "change_log", "undo_actions", "ai_call_log"]
    )
}

func aiTagSuggestionBatchApplyReport(
    fileID: Int64,
    suggestionID: String,
    slug: String,
    status: AITagSuggestionApplyStatusSnapshot = .applied,
    error: String? = nil
) -> AITagSuggestionApplyReportSnapshot {
    let tag = aiTagSuggestionTag(slug)
    return AITagSuggestionApplyReportSnapshot(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: status == AITagSuggestionApplyStatusSnapshot.applied ? 1 : 0,
        skippedCount: status == AITagSuggestionApplyStatusSnapshot.alreadyAdded ? 1 : 0,
        failedCount: status == AITagSuggestionApplyStatusSnapshot.failed ? 1 : 0,
        itemResults: [
            AITagSuggestionApplyItemResultSnapshot(
                suggestionId: suggestionID,
                slug: slug,
                status: status,
                error: error
            )
        ],
        tagSet: TagSetSnapshot.testFixture(
            fileID: fileID,
            fileTags: status == AITagSuggestionApplyStatusSnapshot.applied ? [tag] : [],
            availableTags: [tag],
            recentTags: [tag],
            updatedAt: 1_700_000_350
        ),
        undoToken: nil,
        callLogId: 7707,
        refreshTargets: ["tags", "change_log", "undo_actions", "ai_call_log"]
    )
}

func aiTagSuggestionTag(_ value: String) -> TagRecordSnapshot {
    TagRecordSnapshot.testFixture(
        value: value,
        label: value.prefix(1).uppercased() + value.dropFirst(),
        fileCount: 1,
        selected: true,
        disabled: false,
        updatedAt: 1_700_000_350
    )
}

func aiTagSuggestionProviderGateReport(
    skippedReason: AIPrivacySkippedReasonState,
    providerGateReason: AIPrivacyProviderGateReasonState
) -> AIPrivacyEvaluationReportSnapshot {
    AIPrivacyEvaluationReportSnapshot(
        decision: .skipped,
        skippedReason: skippedReason,
        providerGateReason: providerGateReason,
        matchedRules: [],
        matchedFieldType: nil,
        allowedFields: [],
        blockedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
        sentFields: [],
        message: "Provider gate blocked AI tag suggestions before any fields were sent."
    )
}
