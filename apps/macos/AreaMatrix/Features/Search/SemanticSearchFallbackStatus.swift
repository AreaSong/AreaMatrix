import SwiftUI

struct SemanticSearchFallbackActionPresentation: Identifiable, Equatable {
    var action: AiFallbackAction
    var title: LocalizedMessage
    var accessibilityID: String

    var id: AiFallbackAction {
        action
    }
}

struct SemanticSearchFallbackStatus {
    var title: LocalizedMessage
    var message: LocalizedMessage
    var badge: LocalizedMessage
    var badgeTint: Color
    var retryable: Bool
    var retryDisabledReason: LocalizedMessage?
    var primaryAction: AiFallbackAction?
    var secondaryAction: AiFallbackAction?
    var nonAiFallbackAction: AiFallbackAction
    var callLogID: Int64?
    var privacyRuleID: String?
    var canBuildSemanticIndex: Bool

    var actions: [AiFallbackAction] {
        [
            primaryAction == .retry ? nil : primaryAction,
            secondaryAction,
            nonAiFallbackAction
        ].compactMap { $0 }.reduce(into: []) { actions, action in
            if isVisible(action), !actions.contains(action) { actions.append(action) }
        }
    }

    var actionPresentations: [SemanticSearchFallbackActionPresentation] {
        actions.map(presentation(for:))
    }

    static func fromCoreStatus(_ status: AiFallbackStatus) -> SemanticSearchFallbackStatus {
        SemanticSearchFallbackStatus(
            title: titleMessage(kind: status.kind),
            message: bodyMessage(kind: status.kind),
            badge: badgeText(kind: status.kind),
            badgeTint: badgeTint(category: status.category),
            retryable: status.retryable,
            retryDisabledReason: retryDisabledReasonMessage(kind: status.kind, retryable: status.retryable),
            primaryAction: status.primaryAction,
            secondaryAction: status.secondaryAction,
            nonAiFallbackAction: status.nonAiFallbackAction,
            callLogID: status.callLogId,
            privacyRuleID: status.privacyRuleId,
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
            nonAiFallbackAction: .useNormalSearch,
            callLogID: page.callLogID,
            privacyRuleID: page.privacyRuleID,
            canBuildSemanticIndex: page.canBuildIndex && reason == .semanticIndexNotReady
        )
    }

    func isVisible(_ action: AiFallbackAction) -> Bool {
        switch action {
        case .retry, .retryLater, .openAiSettings, .openLocalModelStatus, .configureRemoteAi,
             .viewPrivacyRule, .viewCallLog, .buildSemanticIndex, .useNormalSearch:
            true
        case .classifyManually:
            false
        }
    }

    func title(for action: AiFallbackAction) -> LocalizedMessage {
        switch action {
        case .retry: L10n.message("Retry")
        case .retryLater: L10n.message("Retry later")
        case .openAiSettings: L10n.message("Open AI settings")
        case .openLocalModelStatus: L10n.message("Open local model status")
        case .configureRemoteAi: L10n.message("Configure remote AI")
        case .viewPrivacyRule: L10n.message("View privacy rule")
        case .viewCallLog: L10n.message("View call log")
        case .buildSemanticIndex: L10n.message("Build semantic index")
        case .useNormalSearch: L10n.message("Use normal search")
        case .classifyManually: L10n.message("Classify manually")
        }
    }

    func accessibilityID(for action: AiFallbackAction) -> String {
        switch action {
        case .retry: "retry"
        case .retryLater: "retry-later"
        case .openAiSettings: "open-ai-settings"
        case .openLocalModelStatus: "open-local-model-status"
        case .configureRemoteAi: "configure-remote-ai"
        case .viewPrivacyRule: "view-privacy-rule"
        case .viewCallLog: "view-call-log"
        case .buildSemanticIndex: "build-semantic-index"
        case .useNormalSearch: "use-normal-search"
        case .classifyManually: "classify-manually"
        }
    }

    func presentation(for action: AiFallbackAction) -> SemanticSearchFallbackActionPresentation {
        SemanticSearchFallbackActionPresentation(
            action: action,
            title: title(for: action),
            accessibilityID: accessibilityID(for: action)
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func badgeText(kind: AiFallbackKind) -> LocalizedMessage {
        switch kind {
        case .aiDisabled: L10n.message("AI disabled")
        case .featureDisabled: L10n.message("Feature disabled")
        case .localModelNotReady: L10n.message("Local not ready")
        case .remoteNotConfigured: L10n.message("Remote not configured")
        case .remoteFailed: L10n.message("Remote failed")
        case .providerUnavailable: L10n.message("Provider unavailable")
        case .privacySkipped: L10n.message("Privacy skipped")
        case .semanticIndexNotReady: L10n.message("Semantic index")
        case .noEligibleInput: L10n.message("No eligible input")
        case .callLogUnavailable: L10n.message("Call log unavailable")
        case .normalSearchUnavailable: L10n.message("Normal search")
        case .rateLimited: L10n.message("Rate limited")
        case .timeout: L10n.message("Timeout")
        case .internalFailure: L10n.message("Internal failure")
        }
    }

    private static func titleMessage(kind: AiFallbackKind) -> LocalizedMessage {
        switch kind {
        case .aiDisabled: L10n.message("AI is off")
        case .featureDisabled: L10n.message("AI feature is off")
        case .localModelNotReady: L10n.message("Local model is not ready")
        case .remoteNotConfigured: L10n.message("Remote AI is not configured")
        case .remoteFailed: L10n.message("Remote AI could not be reached")
        case .providerUnavailable: L10n.message("AI provider is unavailable")
        case .privacySkipped: L10n.message("Skipped by privacy rule")
        case .semanticIndexNotReady: L10n.message("Semantic index is not ready")
        case .noEligibleInput: L10n.message("No eligible AI input")
        case .normalSearchUnavailable: L10n.message("Normal search is unavailable")
        case .callLogUnavailable: L10n.message("AI call log is unavailable")
        case .rateLimited: L10n.message("Provider rate limit reached")
        case .timeout: L10n.message("AI request timed out")
        case .internalFailure: L10n.message("AI fallback status is unavailable")
        }
    }

    private static func bodyMessage(kind: AiFallbackKind) -> LocalizedMessage {
        switch kind {
        case .privacySkipped: L10n.message("This item matches a privacy rule, so no AI content was sent.")
        case .semanticIndexNotReady: L10n.message("Semantic index is not ready yet.")
        case .remoteFailed: L10n.message("Remote AI could not be reached. Your files were not changed.")
        case .localModelNotReady: L10n.message("The local model is not installed or still loading.")
        case .rateLimited: L10n.message("The provider asked AreaMatrix to retry later.")
        case .timeout: L10n.message("The AI request timed out. Your files were not changed.")
        case .aiDisabled: L10n.message("AI is disabled in repository settings.")
        case .featureDisabled: L10n.message("This AI feature is disabled in repository settings.")
        case .remoteNotConfigured: L10n.message("Remote AI must be configured before this route can run.")
        case .providerUnavailable: L10n.message("No AI provider route is currently available.")
        case .noEligibleInput: L10n.message("There is no eligible safe input for this AI operation.")
        case .normalSearchUnavailable: L10n.message("Normal search fallback could not be loaded.")
        case .callLogUnavailable: L10n.message("AI fallback could not be recorded in the call log.")
        case .internalFailure: L10n.message("Fallback status could not be resolved from safe metadata.")
        }
    }

    private static func retryDisabledReasonMessage(
        kind: AiFallbackKind,
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

    private static func badgeTint(category: AiFallbackCategory) -> Color {
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

    var primaryAction: AiFallbackAction? {
        switch self {
        case .aiDisabled, .featureDisabled:
            .openAiSettings
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

    func secondaryAction(callLogID: Int64?) -> AiFallbackAction? {
        switch self {
        case .providerUnavailable, .timeout, .callLogUnavailable:
            callLogID == nil ? nil : .viewCallLog
        case .aiDisabled, .featureDisabled, .privacyRule, .semanticIndexNotReady, .noEligibleInput,
             .normalSearchUnavailable, .rateLimited:
            nil
        }
    }
}
