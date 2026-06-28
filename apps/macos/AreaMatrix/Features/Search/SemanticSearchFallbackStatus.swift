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
            title: status.title,
            message: status.message,
            badge: badgeText(kind: status.kind),
            badgeTint: badgeTint(category: status.category),
            retryable: status.retryable,
            retryDisabledReason: status.retryDisabledReason,
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
        case .retry: "Retry"
        case .retryLater: "Retry later"
        case .openAiSettings: "Open AI settings"
        case .openLocalModelStatus: "Open local model status"
        case .configureRemoteAi: "Configure remote AI"
        case .viewPrivacyRule: "View privacy rule"
        case .viewCallLog: "View call log"
        case .buildSemanticIndex: "Build semantic index"
        case .useNormalSearch: "Use normal search"
        case .classifyManually: "Classify manually"
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
        case .aiDisabled: "AI disabled"
        case .featureDisabled: "Feature disabled"
        case .localModelNotReady: "Local not ready"
        case .remoteNotConfigured: "Remote not configured"
        case .remoteFailed: "Remote failed"
        case .providerUnavailable: "Provider unavailable"
        case .privacySkipped: "Privacy skipped"
        case .semanticIndexNotReady: "Semantic index"
        case .noEligibleInput: "No eligible input"
        case .callLogUnavailable: "Call log unavailable"
        case .normalSearchUnavailable: "Normal search"
        case .rateLimited: "Rate limited"
        case .timeout: "Timeout"
        case .internalFailure: "Internal failure"
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
        case .aiDisabled, .featureDisabled: "Semantic search is unavailable"
        case .providerUnavailable: "Remote AI could not be reached"
        case .privacyRule: "Skipped by privacy rule"
        case .semanticIndexNotReady: "Semantic index is not ready"
        case .callLogUnavailable: "AI call log is unavailable"
        case .noEligibleInput: "No eligible input for semantic search"
        case .normalSearchUnavailable: "Normal search is unavailable"
        case .rateLimited: "Provider rate limit reached"
        case .timeout: "AI request timed out"
        }
    }

    var message: String {
        switch self {
        case .aiDisabled:
            "AI is disabled for this repository. Your files were not changed."
        case .featureDisabled:
            "Semantic search is disabled. Your files were not changed."
        case .providerUnavailable:
            "Remote AI could not be reached. Your files were not changed."
        case .privacyRule:
            "This query matches a privacy rule, so AI was skipped."
        case .semanticIndexNotReady:
            "Semantic index is not ready yet."
        case .callLogUnavailable:
            "AreaMatrix could not record the AI call log. Use normal search while logs recover."
        case .noEligibleInput:
            "No files in this scope are eligible for semantic search."
        case .normalSearchUnavailable:
            "Normal search fallback could not be loaded."
        case .rateLimited:
            "Try again later or use normal search."
        case .timeout:
            "The semantic search request timed out. Your files were not changed."
        }
    }

    var badge: String {
        switch self {
        case .aiDisabled: "AI disabled"
        case .featureDisabled: "Feature disabled"
        case .providerUnavailable: "Provider unavailable"
        case .privacyRule: "Privacy skipped"
        case .semanticIndexNotReady: "Semantic index"
        case .callLogUnavailable: "Call log unavailable"
        case .noEligibleInput: "No eligible input"
        case .normalSearchUnavailable: "Normal search"
        case .rateLimited: "Rate limited"
        case .timeout: "Timeout"
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
            "Open AI settings before retrying semantic search."
        case .featureDisabled:
            "Enable Semantic search before retrying."
        case .privacyRule:
            "Retry is disabled because this input was skipped by a privacy rule."
        case .semanticIndexNotReady:
            "Build the semantic index or use normal search."
        case .callLogUnavailable:
            "Retry is disabled until call logging is available."
        case .noEligibleInput:
            "Adjust the query or filters before retrying."
        case .normalSearchUnavailable:
            "Normal search must recover before fallback results can be shown."
        case .rateLimited:
            "Try again later."
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
