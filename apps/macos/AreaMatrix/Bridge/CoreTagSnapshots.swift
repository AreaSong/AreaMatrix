import Foundation

struct AITagSuggestionRequestSnapshot: Equatable {
    var fileID: Int64
    var candidateTags: [String]
    var privacyPolicyRef: String?
}

enum AITagSuggestionRouteSnapshot: Equatable {
    case local
    case remote
}

enum AITagSuggestionInputFieldSnapshot: Equatable {
    case fileName
    case repoRelativePath
    case extractedTextExcerpt
    case aiSummary
    case noteSummary
    case existingTags
    case tagRegistry
}

enum AITagSuggestionReportStatusSnapshot: Equatable {
    case suggested
    case noSuggestion
    case skipped
    case unavailable
}

enum AITagSuggestionSkipReasonSnapshot: Equatable {
    case aiDisabled
    case featureDisabled
    case providerUnavailable
    case privacyRule
    case noEligibleInput
    case callLogUnavailable
}

enum AITagSuggestionCandidateStatusSnapshot: Equatable {
    case suggested
    case lowConfidence
    case alreadyApplied
    case invalid
    case blocked
}

enum AITagSuggestionMergeActionSnapshot: Equatable {
    case createTag
    case useExistingTag
    case mergeWithExistingTag
}

enum AITagSuggestionApplyStatusSnapshot: Equatable {
    case applied
    case alreadyAdded
    case failed
}

struct AITagSuggestionSnapshot: Equatable {
    var suggestionId: String
    var slug: String
    var displayName: String
    var confidence: Float
    var reason: String
    var status: AITagSuggestionCandidateStatusSnapshot
    var mergeAction: AITagSuggestionMergeActionSnapshot
    var matchedExistingSlug: String?
    var selectedByDefault: Bool
    var disabledReason: String?
}

struct AITagSuggestionReportSnapshot: Equatable {
    var fileId: Int64
    var status: AITagSuggestionReportStatusSnapshot
    var suggestions: [AITagSuggestionSnapshot]
    var route: AITagSuggestionRouteSnapshot?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AITagSuggestionInputFieldSnapshot]
    var skippedReason: AITagSuggestionSkipReasonSnapshot?
    var privacyRuleId: String?
    var callLogId: Int64?
    var requiresUserConfirmation: Bool
    var confidenceThreshold: Float
    var contentsRead: Bool
    var aiUsed: Bool
    var networkUsed: Bool
}

struct ApplyAITagSuggestionItemSnapshot: Equatable {
    var suggestionId: String
    var slug: String
    var displayName: String
    var confidence: Float
    var editedByUser: Bool
    var mergeTargetSlug: String?
}

struct ApplyAITagSuggestionsRequestSnapshot: Equatable {
    var fileId: Int64
    var suggestions: [ApplyAITagSuggestionItemSnapshot]
    var callLogId: Int64?
    var privacyRuleId: String?
    var confirmed: Bool
}

struct AITagSuggestionApplyItemResultSnapshot: Equatable {
    var suggestionId: String
    var slug: String
    var status: AITagSuggestionApplyStatusSnapshot
    var error: String?
}

struct AITagSuggestionApplyReportSnapshot: Equatable {
    var fileId: Int64
    var requestedCount: Int64
    var appliedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [AITagSuggestionApplyItemResultSnapshot]
    var tagSet: TagSetSnapshot
    var undoToken: String?
    var callLogId: Int64?
    var refreshTargets: [String]
}

struct TagRecordSnapshot: Equatable, Identifiable {
    var value: String
    var label: String
    var fileCount: Int64
    var selected: Bool
    var disabled: Bool
    var updatedAt: Int64

    var id: String {
        value
    }

    var displayName: String {
        label.isEmpty ? value : label
    }
}

struct TagSetSnapshot: Equatable {
    var fileID: Int64
    var fileTags: [TagRecordSnapshot]
    var availableTags: [TagRecordSnapshot]
    var recentTags: [TagRecordSnapshot]
    var updatedAt: Int64
}

enum BatchMutationStatusSnapshot: Equatable {
    case added
    case alreadyHadTag
    case failed
}

struct BatchMutationItemResultSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var tag: String
    var status: BatchMutationStatusSnapshot
    var error: String?

    var id: String {
        "\(fileID):\(tag):\(status)"
    }
}

struct BatchMutationReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var requestedTagCount: Int64
    var addedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [BatchMutationItemResultSnapshot]
    var undoToken: String?
}

extension AITagSuggestionReportSnapshot {
    init(coreReport: AiTagSuggestionReport) {
        fileId = coreReport.fileId
        status = AITagSuggestionReportStatusSnapshot(coreStatus: coreReport.status)
        suggestions = coreReport.suggestions.map(AITagSuggestionSnapshot.init(coreSuggestion:))
        route = coreReport.route.map(AITagSuggestionRouteSnapshot.init(coreRoute:))
        modelName = coreReport.modelName
        generatedAt = coreReport.generatedAt
        usedContext = coreReport.usedContext.map(AITagSuggestionInputFieldSnapshot.init(coreField:))
        skippedReason = coreReport.skippedReason.map(AITagSuggestionSkipReasonSnapshot.init(coreReason:))
        privacyRuleId = coreReport.privacyRuleId
        callLogId = coreReport.callLogId
        requiresUserConfirmation = coreReport.requiresUserConfirmation
        confidenceThreshold = coreReport.confidenceThreshold
        contentsRead = coreReport.contentsRead
        aiUsed = coreReport.aiUsed
        networkUsed = coreReport.networkUsed
    }
}

private extension AITagSuggestionSnapshot {
    init(coreSuggestion: AiTagSuggestion) {
        suggestionId = coreSuggestion.suggestionId
        slug = coreSuggestion.slug
        displayName = coreSuggestion.displayName
        confidence = coreSuggestion.confidence
        reason = coreSuggestion.reason
        status = AITagSuggestionCandidateStatusSnapshot(coreStatus: coreSuggestion.status)
        mergeAction = AITagSuggestionMergeActionSnapshot(coreAction: coreSuggestion.mergeAction)
        matchedExistingSlug = coreSuggestion.matchedExistingSlug
        selectedByDefault = coreSuggestion.selectedByDefault
        disabledReason = coreSuggestion.disabledReason
    }
}

extension ApplyAiTagSuggestionsRequest {
    init(snapshot: ApplyAITagSuggestionsRequestSnapshot) {
        self.init(
            fileId: snapshot.fileId,
            suggestions: snapshot.suggestions.map(ApplyAiTagSuggestionItem.init(snapshot:)),
            callLogId: snapshot.callLogId,
            privacyRuleId: snapshot.privacyRuleId,
            confirmed: snapshot.confirmed
        )
    }
}

private extension ApplyAiTagSuggestionItem {
    init(snapshot: ApplyAITagSuggestionItemSnapshot) {
        self.init(
            suggestionId: snapshot.suggestionId,
            slug: snapshot.slug,
            displayName: snapshot.displayName,
            confidence: snapshot.confidence,
            editedByUser: snapshot.editedByUser,
            mergeTargetSlug: snapshot.mergeTargetSlug
        )
    }
}

extension AITagSuggestionApplyReportSnapshot {
    init(coreReport: AiTagSuggestionApplyReport) {
        fileId = coreReport.fileId
        requestedCount = coreReport.requestedCount
        appliedCount = coreReport.appliedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(AITagSuggestionApplyItemResultSnapshot.init(coreResult:))
        tagSet = TagSetSnapshot(coreTagSet: coreReport.tagSet)
        undoToken = coreReport.undoToken
        callLogId = coreReport.callLogId
        refreshTargets = coreReport.refreshTargets
    }
}

private extension AITagSuggestionApplyItemResultSnapshot {
    init(coreResult: AiTagSuggestionApplyItemResult) {
        suggestionId = coreResult.suggestionId
        slug = coreResult.slug
        status = AITagSuggestionApplyStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension AITagSuggestionRouteSnapshot {
    init(coreRoute: AiTagSuggestionRoute) {
        switch coreRoute {
        case .local: self = .local
        case .remote: self = .remote
        }
    }
}

private extension AITagSuggestionInputFieldSnapshot {
    init(coreField: AiTagSuggestionInputField) {
        switch coreField {
        case .fileName: self = .fileName
        case .repoRelativePath: self = .repoRelativePath
        case .extractedTextExcerpt: self = .extractedTextExcerpt
        case .aiSummary: self = .aiSummary
        case .noteSummary: self = .noteSummary
        case .existingTags: self = .existingTags
        case .tagRegistry: self = .tagRegistry
        }
    }
}

private extension AITagSuggestionReportStatusSnapshot {
    init(coreStatus: AiTagSuggestionReportStatus) {
        switch coreStatus {
        case .suggested: self = .suggested
        case .noSuggestion: self = .noSuggestion
        case .skipped: self = .skipped
        case .unavailable: self = .unavailable
        }
    }
}

private extension AITagSuggestionSkipReasonSnapshot {
    init(coreReason: AiTagSuggestionSkipReason) {
        switch coreReason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .providerUnavailable: self = .providerUnavailable
        case .privacyRule: self = .privacyRule
        case .noEligibleInput: self = .noEligibleInput
        case .callLogUnavailable: self = .callLogUnavailable
        }
    }
}

private extension AITagSuggestionCandidateStatusSnapshot {
    init(coreStatus: AiTagSuggestionCandidateStatus) {
        switch coreStatus {
        case .suggested: self = .suggested
        case .lowConfidence: self = .lowConfidence
        case .alreadyApplied: self = .alreadyApplied
        case .invalid: self = .invalid
        case .blocked: self = .blocked
        }
    }
}

private extension AITagSuggestionMergeActionSnapshot {
    init(coreAction: AiTagSuggestionMergeAction) {
        switch coreAction {
        case .createTag: self = .createTag
        case .useExistingTag: self = .useExistingTag
        case .mergeWithExistingTag: self = .mergeWithExistingTag
        }
    }
}

private extension AITagSuggestionApplyStatusSnapshot {
    init(coreStatus: AiTagSuggestionApplyStatus) {
        switch coreStatus {
        case .applied: self = .applied
        case .alreadyAdded: self = .alreadyAdded
        case .failed: self = .failed
        }
    }
}

extension TagSetSnapshot {
    init(coreTagSet: TagSet) {
        fileID = coreTagSet.fileId
        fileTags = coreTagSet.fileTags.map(TagRecordSnapshot.init(coreRecord:))
        availableTags = coreTagSet.availableTags.map(TagRecordSnapshot.init(coreRecord:))
        recentTags = coreTagSet.recentTags.map(TagRecordSnapshot.init(coreRecord:))
        updatedAt = coreTagSet.updatedAt
    }
}

private extension TagRecordSnapshot {
    init(coreRecord: TagRecord) {
        value = coreRecord.value
        label = coreRecord.label
        fileCount = coreRecord.fileCount
        selected = coreRecord.selected
        disabled = coreRecord.disabled
        updatedAt = coreRecord.updatedAt
    }
}

extension BatchMutationReportSnapshot {
    init(coreReport: BatchMutationReport) {
        requestedFileCount = coreReport.requestedFileCount
        requestedTagCount = coreReport.requestedTagCount
        addedCount = coreReport.addedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(BatchMutationItemResultSnapshot.init(coreResult:))
        undoToken = coreReport.undoToken
    }
}

private extension BatchMutationItemResultSnapshot {
    init(coreResult: BatchMutationItemResult) {
        fileID = coreResult.fileId
        tag = coreResult.tag
        status = BatchMutationStatusSnapshot(coreStatus: coreResult.status)
        error = coreResult.error
    }
}

private extension BatchMutationStatusSnapshot {
    init(coreStatus: BatchMutationStatus) {
        switch coreStatus {
        case .added:
            self = .added
        case .alreadyHadTag:
            self = .alreadyHadTag
        case .failed:
            self = .failed
        }
    }
}
