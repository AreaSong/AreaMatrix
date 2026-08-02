import Foundation

enum AISummaryEditorPresentationSupport {
    static func privacyUnavailableNotice(_ mapping: AISettingsError) -> AISummaryEditorNotice {
        notice(
            title: L10n.string("AI privacy rules could not be checked"),
            detail: mapping.detail,
            recovery: mapping.recovery,
            reason: .privacyUnavailable,
            opensAISettings: false,
            capability: "ai-privacy-rules-core"
        )
    }

    static func privacyBlockedNotice(_ skip: AISummaryPrivacySkip) -> AISummaryEditorNotice {
        let reason: AISummaryEditorGateReason = skip.skippedReason == .noEligibleInput ?
            .noEligibleInput(skip) : .privacyBlocked(skip)
        return notice(
            title: skip.reasonLabel,
            detail: skip.message,
            recovery: L10n.message("Review privacy rules before generating this summary."),
            reason: reason,
            opensAISettings: false,
            capability: "ai-privacy-rules-core",
            privacyRuleID: skip.ruleID,
            privacyField: skip.matchedField
        )
    }

    static func notice(for reason: AISummarySkipReasonState) -> AISummaryEditorNotice {
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
                detail: L10n.string("No content was sent because the summary was skipped by privacy rules."),
                recovery: L10n.message("Review privacy rules before generating this summary."),
                reason: .privacyBlocked(AISummaryPrivacySkip(summaryReason: reason)),
                opensAISettings: false,
                capability: "ai-privacy-rules-core"
            )
        case .noEligibleInput:
            notice(
                title: aiSummarySkipReasonLabel(reason),
                detail: L10n.string("This file has no eligible metadata or extracted text for AI summaries."),
                recovery: L10n.message("Return to detail or choose a file with readable summary input."),
                reason: .noEligibleInput(AISummaryPrivacySkip(summaryReason: reason)),
                opensAISettings: false,
                capability: "ai-privacy-rules-core"
            )
        case .callLogUnavailable:
            notice(
                title: aiSummarySkipReasonLabel(reason),
                detail: L10n.string("Summary generation cannot proceed because AI call logging is unavailable."),
                recovery: L10n.message("Retry after repository metadata is writable."),
                reason: .callLogUnavailable,
                opensAISettings: false
            )
        }
    }

    static func error(
        for error: Error,
        message: LocalizedMessage,
        errorMapper: any CoreErrorMapping
    ) async -> AISettingsError {
        guard let mapping = await errorMapper.mapCoreErrorIfPresent(error) else {
            return AISettingsError(
                message: message,
                recovery: L10n.message("Retry or return to detail."),
                detail: error.localizedDescription
            )
        }
        return AISettingsError(
            message: message,
            recovery: mapping.recoveryMessage(fallback: L10n.message("Retry or return to detail.")),
            detail: mapping.userMessage
        )
    }

    private static func notice(
        title: String,
        detail: String,
        recovery: LocalizedMessage,
        reason: AISummaryEditorGateReason,
        opensAISettings: Bool,
        capability: String = "ai-summary-core",
        privacyRuleID: String? = nil,
        privacyField: AIPrivacyInputFieldState? = nil
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
