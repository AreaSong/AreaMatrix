import Foundation

enum AIClassificationSuggestionRuleReturnStatus: Equatable {
    case cancelled
    case saved
}

struct AIClassificationSuggestionReturnContext: Equatable {
    var appliedCategory: String
    var callLogID: Int64?
    var ruleStatus: AIClassificationSuggestionRuleReturnStatus?

    var message: String {
        switch ruleStatus {
        case .saved:
            "Classification applied to \(appliedCategory). Rule saved for future imports."
        case .cancelled:
            "Classification applied to \(appliedCategory). Rule was not saved."
        case nil:
            "Classification applied to \(appliedCategory)."
        }
    }
}

struct AIClassificationSuggestionApplyRequest: Equatable {
    var fileID: Int64
    var targetCategory: String
    var moveFile: Bool
    var rememberRule: Bool
    var suggestion: AIClassificationSuggestionState
    var preview: MoveToCategoryPreviewSnapshot
}

struct ClassifierRuleAIProvenance: Equatable {
    var suggestedCategory: String
    var finalCategory: String
    var confidence: Float
    var reason: String?
    var usedContext: [String]
    var callLogID: Int64?
    var route: String?
}

extension ClassifierRuleAIProvenance {
    init?(suggestion: AIClassificationSuggestionState, finalCategory: String) {
        guard let suggestedCategory = suggestion.suggestedCategory?.trimmingCharacters(in: .whitespacesAndNewlines),
              !suggestedCategory.isEmpty else { return nil }
        self.suggestedCategory = suggestedCategory
        self.finalCategory = finalCategory
        confidence = suggestion.confidence
        reason = suggestion.reason
        usedContext = suggestion.usedContext.map(\.label)
        callLogID = suggestion.callLogID
        route = suggestion.route?.label
    }

    var confidencePercent: Int {
        Int((min(max(confidence, 0), 1) * 100).rounded())
    }

    var usedContextSummary: String {
        usedContext.isEmpty ? "None" : usedContext.joined(separator: ", ")
    }
}
