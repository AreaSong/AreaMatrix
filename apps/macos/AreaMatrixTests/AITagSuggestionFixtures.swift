@testable import AreaMatrix

func aiTagSuggestionAITagReport(
    fileID: Int64,
    status: AiTagSuggestionReportStatus = .suggested,
    skippedReason: AiTagSuggestionSkipReason? = nil,
    suggestions: [AiTagSuggestion] = []
) -> AiTagSuggestionReport {
    AiTagSuggestionReport(
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
    status: AiTagSuggestionCandidateStatus = .suggested,
    mergeAction: AiTagSuggestionMergeAction = .createTag,
    matchedExistingSlug: String? = nil,
    disabledReason: String? = nil
) -> AiTagSuggestion {
    AiTagSuggestion(
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

func aiTagSuggestionApplyReport(fileID: Int64) -> AiTagSuggestionApplyReport {
    let tag = aiTagSuggestionTag("finance")
    return AiTagSuggestionApplyReport(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: 1,
        skippedCount: 0,
        failedCount: 0,
        itemResults: [
            AiTagSuggestionApplyItemResult(
                suggestionId: "ai-tag-finance",
                slug: "finance",
                status: .applied,
                error: nil
            )
        ],
        tagSet: TagSet(
            fileId: fileID,
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
    status: AiTagSuggestionApplyStatus = .applied,
    error: String? = nil
) -> AiTagSuggestionApplyReport {
    let tag = aiTagSuggestionTag(slug)
    return AiTagSuggestionApplyReport(
        fileId: fileID,
        requestedCount: 1,
        appliedCount: status == AiTagSuggestionApplyStatus.applied ? 1 : 0,
        skippedCount: status == AiTagSuggestionApplyStatus.alreadyAdded ? 1 : 0,
        failedCount: status == AiTagSuggestionApplyStatus.failed ? 1 : 0,
        itemResults: [
            AiTagSuggestionApplyItemResult(
                suggestionId: suggestionID,
                slug: slug,
                status: status,
                error: error
            )
        ],
        tagSet: TagSet(
            fileId: fileID,
            fileTags: status == AiTagSuggestionApplyStatus.applied ? [tag] : [],
            availableTags: [tag],
            recentTags: [tag],
            updatedAt: 1_700_000_350
        ),
        undoToken: nil,
        callLogId: 7707,
        refreshTargets: ["tags", "change_log", "undo_actions", "ai_call_log"]
    )
}

func aiTagSuggestionTag(_ value: String) -> TagRecord {
    TagRecord(
        value: value,
        label: value.prefix(1).uppercased() + value.dropFirst(),
        fileCount: 1,
        selected: true,
        disabled: false,
        updatedAt: 1_700_000_350
    )
}

func aiTagSuggestionProviderGateReport(
    skippedReason: AiPrivacySkippedReason,
    providerGateReason: AiPrivacyProviderGateReason
) -> AiPrivacyEvaluationReport {
    AiPrivacyEvaluationReport(
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
