import Foundation

enum AISummaryEditorGateReason: Equatable {
    case aiDisabled
    case featureDisabled
    case providerUnavailable
    case remoteScopeNotAllowed
    case privacyBlocked(AISummaryPrivacySkip)
    case noEligibleInput(AISummaryPrivacySkip)
    case callLogUnavailable
    case privacyUnavailable
}

struct AISummaryEditorNotice: Equatable {
    var title: String
    var detail: String
    var recovery: String
    var capability: String
    var opensAISettings: Bool
    var privacyRuleID: String?
    var reason: AISummaryEditorGateReason
}

enum AISummaryEditorGateState: Equatable {
    case unknown
    case checking
    case allowed
    case blocked(AISummaryEditorNotice)
    case failed(AISettingsError)

    var allowsGeneration: Bool {
        self == .allowed
    }
}

extension AISummaryEditorNotice {
    static func aiDisabled() -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "AI summaries are off",
            detail: "AI is disabled for this repository.",
            recovery: "Open AI settings and turn on AI features.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .aiDisabled
        )
    }

    static func featureDisabled(_ detail: String?) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "Auto summaries are off",
            detail: detail ?? "The Auto summaries feature is disabled.",
            recovery: "Open AI settings and enable Auto summaries.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .featureDisabled
        )
    }

    static func providerUnavailable(_ detail: String?) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "AI provider is unavailable",
            detail: detail ?? "No local or remote AI route is enabled for summaries.",
            recovery: "Open AI settings and enable a summary provider.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .providerUnavailable
        )
    }

    static func remoteScopeBlocked(_ detail: String) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: "AI provider is unavailable",
            detail: detail,
            recovery: "Open AI settings and configure remote summaries.",
            capability: "C3-06",
            opensAISettings: true,
            privacyRuleID: nil,
            reason: .remoteScopeNotAllowed
        )
    }
}
