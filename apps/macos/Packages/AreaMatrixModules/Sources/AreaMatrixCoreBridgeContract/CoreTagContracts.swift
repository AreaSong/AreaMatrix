public struct AITagSuggestionRequestSnapshot: Equatable, Sendable {
    public var fileID: Int64
    public var candidateTags: [String]
    public var privacyPolicyRef: String?

    public init(fileID: Int64, candidateTags: [String], privacyPolicyRef: String?) {
        self.fileID = fileID
        self.candidateTags = candidateTags
        self.privacyPolicyRef = privacyPolicyRef
    }
}

public enum AITagSuggestionRouteSnapshot: Equatable, Sendable {
    case local
    case remote
}

public enum AITagSuggestionInputFieldSnapshot: Equatable, Sendable {
    case fileName
    case repoRelativePath
    case extractedTextExcerpt
    case aiSummary
    case noteSummary
    case existingTags
    case tagRegistry
}

public enum AITagSuggestionReportStatusSnapshot: Equatable, Sendable {
    case suggested
    case noSuggestion
    case skipped
    case unavailable
}

public enum AITagSuggestionSkipReasonSnapshot: Equatable, Sendable {
    case aiDisabled
    case featureDisabled
    case providerUnavailable
    case privacyRule
    case noEligibleInput
    case callLogUnavailable
}

public enum AITagSuggestionCandidateStatusSnapshot: Equatable, Sendable {
    case suggested
    case lowConfidence
    case alreadyApplied
    case invalid
    case blocked
}

public enum AITagSuggestionMergeActionSnapshot: Equatable, Sendable {
    case createTag
    case useExistingTag
    case mergeWithExistingTag
}

public enum AITagSuggestionApplyStatusSnapshot: Equatable, Sendable {
    case applied
    case alreadyAdded
    case failed
}

public struct AITagSuggestionSnapshot: Equatable, Sendable {
    public var suggestionId: String
    public var slug: String
    public var displayName: String
    public var confidence: Float
    public var reason: String
    public var status: AITagSuggestionCandidateStatusSnapshot
    public var mergeAction: AITagSuggestionMergeActionSnapshot
    public var matchedExistingSlug: String?
    public var selectedByDefault: Bool
    public var disabledReason: String?

    public init(
        suggestionId: String,
        slug: String,
        displayName: String,
        confidence: Float,
        reason: String,
        status: AITagSuggestionCandidateStatusSnapshot,
        mergeAction: AITagSuggestionMergeActionSnapshot,
        matchedExistingSlug: String?,
        selectedByDefault: Bool,
        disabledReason: String?
    ) {
        self.suggestionId = suggestionId
        self.slug = slug
        self.displayName = displayName
        self.confidence = confidence
        self.reason = reason
        self.status = status
        self.mergeAction = mergeAction
        self.matchedExistingSlug = matchedExistingSlug
        self.selectedByDefault = selectedByDefault
        self.disabledReason = disabledReason
    }
}

public struct AITagSuggestionReportSnapshot: Equatable, Sendable {
    public var fileId: Int64
    public var status: AITagSuggestionReportStatusSnapshot
    public var suggestions: [AITagSuggestionSnapshot]
    public var route: AITagSuggestionRouteSnapshot?
    public var modelName: String?
    public var generatedAt: Int64?
    public var usedContext: [AITagSuggestionInputFieldSnapshot]
    public var skippedReason: AITagSuggestionSkipReasonSnapshot?
    public var privacyRuleId: String?
    public var callLogId: Int64?
    public var requiresUserConfirmation: Bool
    public var confidenceThreshold: Float
    public var contentsRead: Bool
    public var aiUsed: Bool
    public var networkUsed: Bool

    public init(
        fileId: Int64,
        status: AITagSuggestionReportStatusSnapshot,
        suggestions: [AITagSuggestionSnapshot],
        route: AITagSuggestionRouteSnapshot?,
        modelName: String?,
        generatedAt: Int64?,
        usedContext: [AITagSuggestionInputFieldSnapshot],
        skippedReason: AITagSuggestionSkipReasonSnapshot?,
        privacyRuleId: String?,
        callLogId: Int64?,
        requiresUserConfirmation: Bool,
        confidenceThreshold: Float,
        contentsRead: Bool,
        aiUsed: Bool,
        networkUsed: Bool
    ) {
        self.fileId = fileId
        self.status = status
        self.suggestions = suggestions
        self.route = route
        self.modelName = modelName
        self.generatedAt = generatedAt
        self.usedContext = usedContext
        self.skippedReason = skippedReason
        self.privacyRuleId = privacyRuleId
        self.callLogId = callLogId
        self.requiresUserConfirmation = requiresUserConfirmation
        self.confidenceThreshold = confidenceThreshold
        self.contentsRead = contentsRead
        self.aiUsed = aiUsed
        self.networkUsed = networkUsed
    }
}

public struct ApplyAITagSuggestionItemSnapshot: Equatable, Sendable {
    public var suggestionId: String
    public var slug: String
    public var displayName: String
    public var confidence: Float
    public var editedByUser: Bool
    public var mergeTargetSlug: String?

    public init(
        suggestionId: String,
        slug: String,
        displayName: String,
        confidence: Float,
        editedByUser: Bool,
        mergeTargetSlug: String?
    ) {
        self.suggestionId = suggestionId
        self.slug = slug
        self.displayName = displayName
        self.confidence = confidence
        self.editedByUser = editedByUser
        self.mergeTargetSlug = mergeTargetSlug
    }
}

public struct ApplyAITagSuggestionsRequestSnapshot: Equatable, Sendable {
    public var fileId: Int64
    public var suggestions: [ApplyAITagSuggestionItemSnapshot]
    public var callLogId: Int64?
    public var privacyRuleId: String?
    public var confirmed: Bool

    public init(
        fileId: Int64,
        suggestions: [ApplyAITagSuggestionItemSnapshot],
        callLogId: Int64?,
        privacyRuleId: String?,
        confirmed: Bool
    ) {
        self.fileId = fileId
        self.suggestions = suggestions
        self.callLogId = callLogId
        self.privacyRuleId = privacyRuleId
        self.confirmed = confirmed
    }
}

public struct AITagSuggestionApplyItemResultSnapshot: Equatable, Sendable {
    public var suggestionId: String
    public var slug: String
    public var status: AITagSuggestionApplyStatusSnapshot
    public var error: String?

    public init(
        suggestionId: String,
        slug: String,
        status: AITagSuggestionApplyStatusSnapshot,
        error: String?
    ) {
        self.suggestionId = suggestionId
        self.slug = slug
        self.status = status
        self.error = error
    }
}

public struct AITagSuggestionApplyReportSnapshot: Equatable, Sendable {
    public var fileId: Int64
    public var requestedCount: Int64
    public var appliedCount: Int64
    public var skippedCount: Int64
    public var failedCount: Int64
    public var itemResults: [AITagSuggestionApplyItemResultSnapshot]
    public var tagSet: TagSetSnapshot
    public var undoToken: String?
    public var callLogId: Int64?
    public var refreshTargets: [String]

    public init(
        fileId: Int64,
        requestedCount: Int64,
        appliedCount: Int64,
        skippedCount: Int64,
        failedCount: Int64,
        itemResults: [AITagSuggestionApplyItemResultSnapshot],
        tagSet: TagSetSnapshot,
        undoToken: String?,
        callLogId: Int64?,
        refreshTargets: [String]
    ) {
        self.fileId = fileId
        self.requestedCount = requestedCount
        self.appliedCount = appliedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.itemResults = itemResults
        self.tagSet = tagSet
        self.undoToken = undoToken
        self.callLogId = callLogId
        self.refreshTargets = refreshTargets
    }
}

public struct TagRecordSnapshot: Equatable, Identifiable, Sendable {
    public var value: String
    public var label: String
    public var fileCount: Int64
    public var selected: Bool
    public var disabled: Bool
    public var updatedAt: Int64

    public init(value: String, label: String, fileCount: Int64, selected: Bool, disabled: Bool, updatedAt: Int64) {
        self.value = value
        self.label = label
        self.fileCount = fileCount
        self.selected = selected
        self.disabled = disabled
        self.updatedAt = updatedAt
    }

    public var id: String {
        value
    }

    public var displayName: String {
        label.isEmpty ? value : label
    }
}

public struct TagSetSnapshot: Equatable, Sendable {
    public var fileID: Int64
    public var fileTags: [TagRecordSnapshot]
    public var availableTags: [TagRecordSnapshot]
    public var recentTags: [TagRecordSnapshot]
    public var updatedAt: Int64

    public init(
        fileID: Int64,
        fileTags: [TagRecordSnapshot],
        availableTags: [TagRecordSnapshot],
        recentTags: [TagRecordSnapshot],
        updatedAt: Int64
    ) {
        self.fileID = fileID
        self.fileTags = fileTags
        self.availableTags = availableTags
        self.recentTags = recentTags
        self.updatedAt = updatedAt
    }
}

public enum BatchMutationStatusSnapshot: Equatable, Sendable {
    case added
    case alreadyHadTag
    case failed
}

public struct BatchMutationItemResultSnapshot: Equatable, Identifiable, Sendable {
    public var fileID: Int64
    public var tag: String
    public var status: BatchMutationStatusSnapshot
    public var error: String?

    public init(fileID: Int64, tag: String, status: BatchMutationStatusSnapshot, error: String?) {
        self.fileID = fileID
        self.tag = tag
        self.status = status
        self.error = error
    }

    public var id: String {
        "\(fileID):\(tag):\(status)"
    }
}

public struct BatchMutationReportSnapshot: Equatable, Sendable {
    public var requestedFileCount: Int64
    public var requestedTagCount: Int64
    public var addedCount: Int64
    public var skippedCount: Int64
    public var failedCount: Int64
    public var itemResults: [BatchMutationItemResultSnapshot]
    public var undoToken: String?

    public init(
        requestedFileCount: Int64,
        requestedTagCount: Int64,
        addedCount: Int64,
        skippedCount: Int64,
        failedCount: Int64,
        itemResults: [BatchMutationItemResultSnapshot],
        undoToken: String?
    ) {
        self.requestedFileCount = requestedFileCount
        self.requestedTagCount = requestedTagCount
        self.addedCount = addedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.itemResults = itemResults
        self.undoToken = undoToken
    }
}
