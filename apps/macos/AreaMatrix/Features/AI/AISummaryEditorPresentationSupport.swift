import Foundation

enum AISummaryEditorPresentationSupport {
    static func privacyUnavailableNotice(_ mapping: AISettingsError) -> AISummaryEditorNotice {
        notice(
            title: "AI privacy rules could not be checked",
            detail: mapping.detail,
            recovery: mapping.recovery,
            reason: .privacyUnavailable,
            opensAISettings: false,
            capability: "ai-privacy-rules-core"
        )
    }

    static func privacyBlockedNotice(_ skip: AISummaryPrivacySkip) -> AISummaryEditorNotice {
        let reason: AISummaryEditorGateReason = skip.reasonLabel == "No eligible summary input" ?
            .noEligibleInput(skip) : .privacyBlocked(skip)
        return notice(
            title: skip.reasonLabel,
            detail: skip.message,
            recovery: "Review privacy rules before generating this summary.",
            reason: reason,
            opensAISettings: false,
            capability: "ai-privacy-rules-core",
            privacyRuleID: skip.ruleID,
            privacyField: skip.matchedField
        )
    }

    static func notice(for reason: AiSummarySkipReason) -> AISummaryEditorNotice {
        switch reason {
        case .aiDisabled:
            .aiDisabled()
        case .featureDisabled:
            .featureDisabled(nil)
        case .providerUnavailable:
            .providerUnavailable(nil)
        case .privacyRule:
            notice(
                title: aiSummarySkipReasonLabel(reason),
                detail: "No content was sent because the summary was skipped by privacy rules.",
                recovery: "Review privacy rules before generating this summary.",
                reason: .privacyBlocked(AISummaryPrivacySkip(summaryReason: reason)),
                opensAISettings: false,
                capability: "ai-privacy-rules-core"
            )
        case .noEligibleInput:
            notice(
                title: aiSummarySkipReasonLabel(reason),
                detail: "This file has no eligible metadata or extracted text for AI summaries.",
                recovery: "Return to detail or choose a file with readable summary input.",
                reason: .noEligibleInput(AISummaryPrivacySkip(summaryReason: reason)),
                opensAISettings: false,
                capability: "ai-privacy-rules-core"
            )
        case .callLogUnavailable:
            notice(
                title: aiSummarySkipReasonLabel(reason),
                detail: "Summary generation cannot proceed because AI call logging is unavailable.",
                recovery: "Retry after repository metadata is writable.",
                reason: .callLogUnavailable,
                opensAISettings: false
            )
        }
    }

    static func error(
        for error: Error,
        message: String,
        errorMapper: any CoreErrorMapping
    ) async -> AISettingsError {
        guard let coreError = error as? CoreError else {
            return AISettingsError(
                message: message,
                recovery: "Retry or return to detail.",
                detail: error.localizedDescription
            )
        }
        let mapping = await errorMapper.mapCoreError(coreError)
        return AISettingsError(
            message: message,
            recovery: mapping.suggestedAction.isEmpty ? "Retry or return to detail." : mapping.suggestedAction,
            detail: mapping.userMessage
        )
    }

    private static func notice(
        title: String,
        detail: String,
        recovery: String,
        reason: AISummaryEditorGateReason,
        opensAISettings: Bool,
        capability: String = "ai-summary-core",
        privacyRuleID: String? = nil,
        privacyField: AiPrivacyInputField? = nil
    ) -> AISummaryEditorNotice {
        AISummaryEditorNotice(
            title: title,
            detail: detail,
            recovery: recovery,
            capability: capability,
            opensAISettings: opensAISettings,
            privacyRuleID: privacyRuleID,
            privacyField: privacyField,
            reason: reason
        )
    }
}
