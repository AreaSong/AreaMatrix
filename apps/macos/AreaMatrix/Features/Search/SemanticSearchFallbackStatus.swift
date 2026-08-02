import SwiftUI

struct SemanticSearchFallbackActionPresentation: Identifiable, Equatable {
    var action: AIFallbackActionSnapshot
    var title: LocalizedMessage
    var accessibilityID: String

    var id: AIFallbackActionSnapshot {
        action
    }

    var accessibilityIdentifier: String {
        "ai-fallback-semantic-search-core-action-\(accessibilityID)"
    }
}

struct SemanticSearchFallbackStatus {
    var title: LocalizedMessage
    var message: LocalizedMessage
    var badge: LocalizedMessage
    var badgeTint: Color
    var retryable: Bool
    var retryDisabledReason: LocalizedMessage?
    var primaryAction: AIFallbackActionSnapshot?
    var secondaryAction: AIFallbackActionSnapshot?
    var nonAIFallbackAction: AIFallbackActionSnapshot
    var callLogID: Int64?
    var privacyRuleID: String?
    var canBuildSemanticIndex: Bool

    var actions: [AIFallbackActionSnapshot] {
        [
            primaryAction == .retry ? nil : primaryAction,
            secondaryAction,
            nonAIFallbackAction
        ].compactMap { $0 }.reduce(into: []) { actions, action in
            if isVisible(action), !actions.contains(action) { actions.append(action) }
        }
    }

    var actionPresentations: [SemanticSearchFallbackActionPresentation] {
        actions.map(presentation(for:))
    }

    static func fromCoreStatus(_ status: AIFallbackStatusSnapshot) -> SemanticSearchFallbackStatus {
        SemanticSearchFallbackStatus(
            title: titleMessage(kind: status.kind),
            message: bodyMessage(kind: status.kind),
            badge: badgeText(kind: status.kind),
            badgeTint: badgeTint(category: status.category),
            retryable: status.retryable,
            retryDisabledReason: retryDisabledReasonMessage(kind: status.kind, retryable: status.retryable),
            primaryAction: status.primaryAction,
            secondaryAction: status.secondaryAction,
            nonAIFallbackAction: status.nonAIFallbackAction,
            callLogID: status.callLogID,
            privacyRuleID: status.privacyRuleID,
            canBuildSemanticIndex: status.primaryAction == .buildSemanticIndex ||
                status.secondaryAction == .buildSemanticIndex
        )
    }

    static func fromSemanticPage(_ page: SemanticSearchResultPageSnapshot) -> SemanticSearchFallbackStatus {
        let reason = page.fallbackReason ?? .providerUnavailable
        return SemanticSearchFallbackStatus(
            title: reason.title,
            message: reason.message,
            badge: reason.badge,
            badgeTint: reason.badgeTint,
            retryable: reason.retryable,
            retryDisabledReason: reason.retryDisabledReason,
            primaryAction: reason.primaryAction,
            secondaryAction: reason.secondaryAction(callLogID: page.callLogID),
            nonAIFallbackAction: .useNormalSearch,
            callLogID: page.callLogID,
            privacyRuleID: page.privacyRuleID,
            canBuildSemanticIndex: page.canBuildIndex && reason == .semanticIndexNotReady
        )
    }

    func isVisible(_ action: AIFallbackActionSnapshot) -> Bool {
        switch action {
        case .retry, .retryLater, .openAISettings, .openLocalModelStatus, .configureRemoteAI,
             .viewPrivacyRule, .viewCallLog, .buildSemanticIndex, .useNormalSearch:
            true
        case .classifyManually:
            false
        }
    }

    func title(for action: AIFallbackActionSnapshot) -> LocalizedMessage {
        switch action {
        case .retry: L10n.message("Retry")
        case .retryLater: L10n.message("Retry later")
        case .openAISettings: L10n.message("Open AI settings")
        case .openLocalModelStatus: L10n.message("Open local model status")
        case .configureRemoteAI: L10n.message("Configure remote AI")
        case .viewPrivacyRule: L10n.message("View privacy rule")
        case .viewCallLog: L10n.message("View call log")
        case .buildSemanticIndex: L10n.message("Build semantic index")
        case .useNormalSearch: L10n.message("Use normal search")
        case .classifyManually: L10n.message("Classify manually")
        }
    }

    func accessibilityID(for action: AIFallbackActionSnapshot) -> String {
        switch action {
        case .retry: "retry"
        case .retryLater: "retry-later"
        case .openAISettings: "open-ai-settings"
        case .openLocalModelStatus: "open-local-model-status"
        case .configureRemoteAI: "configure-remote-ai"
        case .viewPrivacyRule: "view-privacy-rule"
        case .viewCallLog: "view-call-log"
        case .buildSemanticIndex: "build-semantic-index"
        case .useNormalSearch: "use-normal-search"
        case .classifyManually: "classify-manually"
        }
    }

    func presentation(for action: AIFallbackActionSnapshot) -> SemanticSearchFallbackActionPresentation {
        SemanticSearchFallbackActionPresentation(
            action: action,
            title: title(for: action),
            accessibilityID: accessibilityID(for: action)
        )
    }

    private static func badgeText(kind: AIFallbackKindSnapshot) -> LocalizedMessage {
        switch kind {
        case .aiDisabled: L10n.message("AI disabled")
        case .featureDisabled: L10n.message("Feature disabled")
        case .localModelNotReady: L10n.message("Local not ready")
        case .remoteNotConfigured: L10n.message("Remote not configured")
        case .remoteFailed: L10n.message("Remote failed")
        case .providerUnavailable: L10n.message("Provider unavailable")
        case .privacySkipped: L10n.message("Privacy skipped")
        case .semanticIndexNotReady: L10n.message("Semantic index")
        case .noEligibleInput, .callLogUnavailable, .normalSearchUnavailable, .rateLimited, .timeout, .internalFailure:
            secondaryBadgeText(kind: kind)
        }
    }

    private static func secondaryBadgeText(kind: AIFallbackKindSnapshot) -> LocalizedMessage {
        switch kind {
        case .noEligibleInput: L10n.message("No eligible input")
        case .callLogUnavailable: L10n.message("Call log unavailable")
        case .normalSearchUnavailable: L10n.message("Normal search")
        case .rateLimited: L10n.message("Rate limited")
        case .timeout: L10n.message("Timeout")
        case .internalFailure: L10n.message("Internal failure")
        case .aiDisabled, .featureDisabled, .localModelNotReady, .remoteNotConfigured, .remoteFailed,
             .providerUnavailable, .privacySkipped, .semanticIndexNotReady:
            L10n.message("Internal failure")
        }
    }

    private static func titleMessage(kind: AIFallbackKindSnapshot) -> LocalizedMessage {
        switch kind {
        case .aiDisabled: L10n.message("AI is off")
        case .featureDisabled: L10n.message("AI feature is off")
        case .localModelNotReady: L10n.message("Local model is not ready")
        case .remoteNotConfigured: L10n.message("Remote AI is not configured")
        case .remoteFailed: L10n.message("Remote AI could not be reached")
        case .providerUnavailable: L10n.message("AI provider is unavailable")
        case .privacySkipped: L10n.message("Skipped by privacy rule")
        case .semanticIndexNotReady: L10n.message("Semantic index is not ready")
        case .noEligibleInput, .normalSearchUnavailable, .callLogUnavailable, .rateLimited, .timeout, .internalFailure:
            secondaryTitleMessage(kind: kind)
        }
    }

    private static func secondaryTitleMessage(kind: AIFallbackKindSnapshot) -> LocalizedMessage {
        switch kind {
        case .noEligibleInput: L10n.message("No eligible AI input")
        case .normalSearchUnavailable: L10n.message("Normal search is unavailable")
        case .callLogUnavailable: L10n.message("AI call log is unavailable")
        case .rateLimited: L10n.message("Provider rate limit reached")
        case .timeout: L10n.message("AI request timed out")
        case .internalFailure: L10n.message("AI fallback status is unavailable")
        case .aiDisabled, .featureDisabled, .localModelNotReady, .remoteNotConfigured, .remoteFailed,
             .providerUnavailable, .privacySkipped, .semanticIndexNotReady:
            L10n.message("AI fallback status is unavailable")
        }
    }

    private static func bodyMessage(kind: AIFallbackKindSnapshot) -> LocalizedMessage {
        switch kind {
        case .privacySkipped: L10n.message("This item matches a privacy rule, so no AI content was sent.")
        case .semanticIndexNotReady: L10n.message("Semantic index is not ready yet.")
        case .remoteFailed: L10n.message("Remote AI could not be reached. Your files were not changed.")
        case .localModelNotReady: L10n.message("The local model is not installed or still loading.")
        case .rateLimited: L10n.message("The provider asked AreaMatrix to retry later.")
        case .timeout: L10n.message("The AI request timed out. Your files were not changed.")
        case .aiDisabled: L10n.message("AI is disabled in repository settings.")
        case .featureDisabled: L10n.message("This AI feature is disabled in repository settings.")
        case .remoteNotConfigured, .providerUnavailable, .noEligibleInput, .normalSearchUnavailable,
             .callLogUnavailable, .internalFailure:
            secondaryBodyMessage(kind: kind)
        }
    }

    private static func secondaryBodyMessage(kind: AIFallbackKindSnapshot) -> LocalizedMessage {
        switch kind {
        case .remoteNotConfigured: L10n.message("Remote AI must be configured before this route can run.")
        case .providerUnavailable: L10n.message("No AI provider route is currently available.")
        case .noEligibleInput: L10n.message("There is no eligible safe input for this AI operation.")
        case .normalSearchUnavailable: L10n.message("Normal search fallback could not be loaded.")
        case .callLogUnavailable: L10n.message("AI fallback could not be recorded in the call log.")
        case .internalFailure: L10n.message("Fallback status could not be resolved from safe metadata.")
        case .privacySkipped, .semanticIndexNotReady, .remoteFailed, .localModelNotReady, .rateLimited, .timeout,
             .aiDisabled, .featureDisabled:
            L10n.message("Fallback status could not be resolved from safe metadata.")
        }
    }

    private static func retryDisabledReasonMessage(
        kind: AIFallbackKindSnapshot,
        retryable: Bool
    ) -> LocalizedMessage? {
        guard !retryable else { return nil }
        switch kind {
        case .privacySkipped:
            return L10n.message("Retry is disabled because privacy rules blocked the input")
        case .rateLimited:
            return L10n.message("Retry is disabled until the provider allows another attempt")
        case .aiDisabled, .featureDisabled:
            return L10n.message("Retry is disabled while AI is turned off")
        case .remoteNotConfigured:
            return L10n.message("Retry is disabled until remote AI is configured")
        case .semanticIndexNotReady:
            return L10n.message("Retry is disabled until the semantic index is ready")
        case .localModelNotReady, .remoteFailed, .providerUnavailable, .noEligibleInput,
             .normalSearchUnavailable, .callLogUnavailable, .timeout, .internalFailure:
            return L10n.message("Retry is unavailable for this fallback state")
        }
    }

    private static func badgeTint(category: AIFallbackCategorySnapshot) -> Color {
        switch category {
        case .skipped: .blue
        case .disabled, .unavailable: .orange
        case .error: .red
        }
    }
}

private extension SemanticSearchFallbackReasonSnapshot {
    var title: LocalizedMessage {
        switch self {
        case .aiDisabled, .featureDisabled: L10n.message("Semantic search is unavailable")
        case .providerUnavailable: L10n.message("Remote AI could not be reached")
        case .privacyRule: L10n.message("Skipped by privacy rule")
        case .semanticIndexNotReady: L10n.message("Semantic index is not ready")
        case .callLogUnavailable: L10n.message("AI call log is unavailable")
        case .noEligibleInput: L10n.message("No eligible input for semantic search")
        case .normalSearchUnavailable: L10n.message("Normal search is unavailable")
        case .rateLimited: L10n.message("Provider rate limit reached")
        case .timeout: L10n.message("AI request timed out")
        }
    }

    var message: LocalizedMessage {
        switch self {
        case .aiDisabled:
            L10n.message("AI is disabled for this repository. Your files were not changed.")
        case .featureDisabled:
            L10n.message("Semantic search is disabled. Your files were not changed.")
        case .providerUnavailable:
            L10n.message("Remote AI could not be reached. Your files were not changed.")
        case .privacyRule:
            L10n.message("This query matches a privacy rule, so AI was skipped.")
        case .semanticIndexNotReady:
            L10n.message("Semantic index is not ready yet.")
        case .callLogUnavailable:
            L10n.message("AreaMatrix could not record the AI call log. Use normal search while logs recover.")
        case .noEligibleInput:
            L10n.message("No files in this scope are eligible for semantic search.")
        case .normalSearchUnavailable:
            L10n.message("Normal search fallback could not be loaded.")
        case .rateLimited:
            L10n.message("Try again later or use normal search.")
        case .timeout:
            L10n.message("The semantic search request timed out. Your files were not changed.")
        }
    }

    var badge: LocalizedMessage {
        switch self {
        case .aiDisabled: L10n.message("AI disabled")
        case .featureDisabled: L10n.message("Feature disabled")
        case .providerUnavailable: L10n.message("Provider unavailable")
        case .privacyRule: L10n.message("Privacy skipped")
        case .semanticIndexNotReady: L10n.message("Semantic index")
        case .callLogUnavailable: L10n.message("Call log unavailable")
        case .noEligibleInput: L10n.message("No eligible input")
        case .normalSearchUnavailable: L10n.message("Normal search")
        case .rateLimited: L10n.message("Rate limited")
        case .timeout: L10n.message("Timeout")
        }
    }

    var badgeTint: Color {
        switch self {
        case .privacyRule:
            .blue
        case .providerUnavailable, .normalSearchUnavailable, .timeout:
            .red
        case .aiDisabled, .featureDisabled, .semanticIndexNotReady, .callLogUnavailable,
             .noEligibleInput, .rateLimited:
            .orange
        }
    }

    var retryable: Bool {
        switch self {
        case .providerUnavailable, .timeout:
            true
        case .aiDisabled, .featureDisabled, .privacyRule, .semanticIndexNotReady, .callLogUnavailable,
             .noEligibleInput, .normalSearchUnavailable, .rateLimited:
            false
        }
    }

    var retryDisabledReason: LocalizedMessage? {
        switch self {
        case .aiDisabled:
            L10n.message("Open AI settings before retrying semantic search.")
        case .featureDisabled:
            L10n.message("Enable Semantic search before retrying.")
        case .privacyRule:
            L10n.message("Retry is disabled because this input was skipped by a privacy rule.")
        case .semanticIndexNotReady:
            L10n.message("Build the semantic index or use normal search.")
        case .callLogUnavailable:
            L10n.message("Retry is disabled until call logging is available.")
        case .noEligibleInput:
            L10n.message("Adjust the query or filters before retrying.")
        case .normalSearchUnavailable:
            L10n.message("Normal search must recover before fallback results can be shown.")
        case .rateLimited:
            L10n.message("Try again later.")
        case .providerUnavailable, .timeout:
            nil
        }
    }

    var primaryAction: AIFallbackActionSnapshot? {
        switch self {
        case .aiDisabled, .featureDisabled:
            .openAISettings
        case .providerUnavailable, .timeout:
            .retry
        case .privacyRule:
            .viewPrivacyRule
        case .semanticIndexNotReady:
            .buildSemanticIndex
        case .callLogUnavailable:
            .viewCallLog
        case .rateLimited:
            .retryLater
        case .noEligibleInput, .normalSearchUnavailable:
            nil
        }
    }

    func secondaryAction(callLogID: Int64?) -> AIFallbackActionSnapshot? {
        switch self {
        case .providerUnavailable, .timeout, .callLogUnavailable:
            callLogID == nil ? nil : .viewCallLog
        case .aiDisabled, .featureDisabled, .privacyRule, .semanticIndexNotReady, .noEligibleInput,
             .normalSearchUnavailable, .rateLimited:
            nil
        }
    }
}
