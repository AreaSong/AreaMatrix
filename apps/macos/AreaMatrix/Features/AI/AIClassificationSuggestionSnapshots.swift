import Foundation

enum AIClassificationContextPolicyState: Equatable {
    case fileNameOnly
    case fileNameAndPath
    case limitedTextSummary
}

enum AIClassificationSuggestionStatusState: Equatable {
    case suggested
    case noSuggestion
    case skipped
    case unavailable
}

enum AIClassificationSuggestionRouteState: Equatable {
    case local
    case remote

    var label: String {
        switch self {
        case .local: L10n.string("Local")
        case .remote: L10n.string("Remote")
        }
    }
}

// swiftlint:disable:next type_name
enum AIClassificationSuggestionContextFieldState: Equatable {
    case fileName
    case `extension`
    case repoRelativePath
    case limitedTextSummary

    var label: String {
        switch self {
        case .fileName: L10n.string("filename")
        case .extension: L10n.string("extension")
        case .repoRelativePath: L10n.string("repo-relative path")
        case .limitedTextSummary: L10n.string("limited text summary")
        }
    }
}

// swiftlint:disable:next type_name
enum AIClassificationSuggestionSkipReasonState: Equatable {
    case aiDisabled
    case featureDisabled
    case ruleResultConfident
    case noEligibleContext
    case privacyRule
    case providerUnavailable
}

struct AIClassificationSuggestionRequestState: Equatable {
    var fileID: Int64
    var contextPolicy: AIClassificationContextPolicyState
    var privacyPolicyRef: String?
}

struct AIClassificationSuggestionState: Equatable {
    var fileID: Int64
    var status: AIClassificationSuggestionStatusState
    var currentCategory: String?
    var suggestedCategory: String?
    var confidence: Float
    var reason: String?
    var route: AIClassificationSuggestionRouteState?
    var usedContext: [AIClassificationSuggestionContextFieldState]
    var skippedReason: AIClassificationSuggestionSkipReasonState?
    var privacyRuleID: String?
    var callLogID: Int64?
    var requiresUserConfirmation: Bool
}
