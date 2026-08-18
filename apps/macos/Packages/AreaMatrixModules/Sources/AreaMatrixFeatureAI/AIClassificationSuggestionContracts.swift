public enum AIClassificationSuggestionRouteState: Equatable, Sendable {
    case local
    case remote
}

// swiftlint:disable:next type_name
public enum AIClassificationSuggestionContextFieldState: Equatable, Sendable {
    case fileName
    case `extension`
    case repoRelativePath
    case limitedTextSummary
}

public struct AIClassificationSuggestionState: Equatable, Sendable {
    public var fileID: Int64
    public var status: AIClassificationSuggestionStatusState
    public var currentCategory: String?
    public var suggestedCategory: String?
    public var confidence: Float
    public var reason: String?
    public var route: AIClassificationSuggestionRouteState?
    public var usedContext: [AIClassificationSuggestionContextFieldState]
    public var skippedReason: AIClassificationSuggestionSkipReasonState?
    public var privacyRuleID: String?
    public var callLogID: Int64?
    public var requiresUserConfirmation: Bool

    public init(
        fileID: Int64,
        status: AIClassificationSuggestionStatusState,
        currentCategory: String?,
        suggestedCategory: String?,
        confidence: Float,
        reason: String?,
        route: AIClassificationSuggestionRouteState?,
        usedContext: [AIClassificationSuggestionContextFieldState],
        skippedReason: AIClassificationSuggestionSkipReasonState?,
        privacyRuleID: String?,
        callLogID: Int64?,
        requiresUserConfirmation: Bool
    ) {
        self.fileID = fileID
        self.status = status
        self.currentCategory = currentCategory
        self.suggestedCategory = suggestedCategory
        self.confidence = confidence
        self.reason = reason
        self.route = route
        self.usedContext = usedContext
        self.skippedReason = skippedReason
        self.privacyRuleID = privacyRuleID
        self.callLogID = callLogID
        self.requiresUserConfirmation = requiresUserConfirmation
    }
}
