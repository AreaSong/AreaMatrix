import SwiftUI

struct SemanticSearchFallbackActionPresentation: Identifiable, Equatable {
    var action: AiFallbackAction
    var title: String
    var accessibilityID: String

    var id: AiFallbackAction {
        action
    }
}

struct SemanticSearchFallbackStatus {
    var title: String
    var message: String
    var badge: String
    var badgeTint: Color
    var retryable: Bool
    var retryDisabledReason: String?
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
            title: L10n.string(status.title),
            message: L10n.string(status.message),
            badge: badgeText(kind: status.kind),
            badgeTint: badgeTint(category: status.category),
            retryable: status.retryable,
            retryDisabledReason: status.retryDisabledReason.map { L10n.string($0) },
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
            message: page.fallbackMessage ?? reason.message,
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

    func title(for action: AiFallbackAction) -> String {
        switch action {
        case .retry: L10n.string("Retry")
        case .retryLater: L10n.string("Retry later")
        case .openAiSettings: L10n.string("Open AI settings")
        case .openLocalModelStatus: L10n.string("Open local model status")
        case .configureRemoteAi: L10n.string("Configure remote AI")
        case .viewPrivacyRule: L10n.string("View privacy rule")
        case .viewCallLog: L10n.string("View call log")
        case .buildSemanticIndex: L10n.string("Build semantic index")
        case .useNormalSearch: L10n.string("Use normal search")
        case .classifyManually: L10n.string("Classify manually")
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
    private static func badgeText(kind: AiFallbackKind) -> String {
        switch kind {
        case .aiDisabled: L10n.string("AI disabled")
        case .featureDisabled: L10n.string("Feature disabled")
        case .localModelNotReady: L10n.string("Local not ready")
        case .remoteNotConfigured: L10n.string("Remote not configured")
        case .remoteFailed: L10n.string("Remote failed")
        case .providerUnavailable: L10n.string("Provider unavailable")
        case .privacySkipped: L10n.string("Privacy skipped")
        case .semanticIndexNotReady: L10n.string("Semantic index")
        case .noEligibleInput: L10n.string("No eligible input")
        case .callLogUnavailable: L10n.string("Call log unavailable")
        case .normalSearchUnavailable: L10n.string("Normal search")
        case .rateLimited: L10n.string("Rate limited")
        case .timeout: L10n.string("Timeout")
        case .internalFailure: L10n.string("Internal failure")
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
    var title: String {
        switch self {
        case .aiDisabled, .featureDisabled: L10n.string("Semantic search is unavailable")
        case .providerUnavailable: L10n.string("Remote AI could not be reached")
        case .privacyRule: L10n.string("Skipped by privacy rule")
        case .semanticIndexNotReady: L10n.string("Semantic index is not ready")
        case .callLogUnavailable: L10n.string("AI call log is unavailable")
        case .noEligibleInput: L10n.string("No eligible input for semantic search")
        case .normalSearchUnavailable: L10n.string("Normal search is unavailable")
        case .rateLimited: L10n.string("Provider rate limit reached")
        case .timeout: L10n.string("AI request timed out")
        }
    }

    var message: String {
        switch self {
        case .aiDisabled:
            L10n.string("AI is disabled for this repository. Your files were not changed.")
        case .featureDisabled:
            L10n.string("Semantic search is disabled. Your files were not changed.")
        case .providerUnavailable:
            L10n.string("Remote AI could not be reached. Your files were not changed.")
        case .privacyRule:
            L10n.string("This query matches a privacy rule, so AI was skipped.")
        case .semanticIndexNotReady:
            L10n.string("Semantic index is not ready yet.")
        case .callLogUnavailable:
            L10n.string("AreaMatrix could not record the AI call log. Use normal search while logs recover.")
        case .noEligibleInput:
            L10n.string("No files in this scope are eligible for semantic search.")
        case .normalSearchUnavailable:
            L10n.string("Normal search fallback could not be loaded.")
        case .rateLimited:
            L10n.string("Try again later or use normal search.")
        case .timeout:
            L10n.string("The semantic search request timed out. Your files were not changed.")
        }
    }

    var badge: String {
        switch self {
        case .aiDisabled: L10n.string("AI disabled")
        case .featureDisabled: L10n.string("Feature disabled")
        case .providerUnavailable: L10n.string("Provider unavailable")
        case .privacyRule: L10n.string("Privacy skipped")
        case .semanticIndexNotReady: L10n.string("Semantic index")
        case .callLogUnavailable: L10n.string("Call log unavailable")
        case .noEligibleInput: L10n.string("No eligible input")
        case .normalSearchUnavailable: L10n.string("Normal search")
        case .rateLimited: L10n.string("Rate limited")
        case .timeout: L10n.string("Timeout")
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

    var retryDisabledReason: String? {
        switch self {
        case .aiDisabled:
            L10n.string("Open AI settings before retrying semantic search.")
        case .featureDisabled:
            L10n.string("Enable Semantic search before retrying.")
        case .privacyRule:
            L10n.string("Retry is disabled because this input was skipped by a privacy rule.")
        case .semanticIndexNotReady:
            L10n.string("Build the semantic index or use normal search.")
        case .callLogUnavailable:
            L10n.string("Retry is disabled until call logging is available.")
        case .noEligibleInput:
            L10n.string("Adjust the query or filters before retrying.")
        case .normalSearchUnavailable:
            L10n.string("Normal search must recover before fallback results can be shown.")
        case .rateLimited:
            L10n.string("Try again later.")
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
