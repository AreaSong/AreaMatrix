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
    var privacyField: AiPrivacyInputField?
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
            title: L10n.string("AI summaries are off"),
            detail: L10n.string("AI is disabled for this repository."),
            recovery: L10n.string("Open AI settings and turn on AI features."),
            capability: "ai-summary-core",
            opensAISettings: true,
            privacyRuleID: nil,
            privacyField: nil,
            reason: .aiDisabled
        )
    }

    static func featureDisabled(_ detail: String?) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: L10n.string("Auto summaries are off"),
            detail: detail ?? L10n.string("The Auto summaries feature is disabled."),
            recovery: L10n.string("Open AI settings and enable Auto summaries."),
            capability: "ai-summary-core",
            opensAISettings: true,
            privacyRuleID: nil,
            privacyField: nil,
            reason: .featureDisabled
        )
    }

    static func providerUnavailable(_ detail: String?) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: L10n.string("AI provider is unavailable"),
            detail: detail ?? L10n.string("No local or remote AI route is enabled for summaries."),
            recovery: L10n.string("Open AI settings and enable a summary provider."),
            capability: "ai-summary-core",
            opensAISettings: true,
            privacyRuleID: nil,
            privacyField: nil,
            reason: .providerUnavailable
        )
    }

    static func remoteScopeBlocked(_ detail: String) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: L10n.string("AI provider is unavailable"),
            detail: detail,
            recovery: L10n.string("Open AI settings and configure remote summaries."),
            capability: "ai-summary-core",
            opensAISettings: true,
            privacyRuleID: nil,
            privacyField: nil,
            reason: .remoteScopeNotAllowed
        )
    }
}
