import SwiftUI

extension AiFallbackStatus {
    static let aiFallbackResolvingClassificationStatus = AiFallbackStatus(
        operation: .classificationSuggestion,
        kind: .internalFailure,
        category: .unavailable,
        title: L10n.string("Resolving AI status..."),
        message: L10n.string("AreaMatrix is mapping the AI category fallback reason."),
        retryable: false,
        retryDisabledReason: L10n.string("Recovery actions are disabled until status mapping completes."),
        primaryAction: .retry,
        secondaryAction: nil,
        nonAiFallbackAction: .classifyManually,
        route: nil,
        callLogId: nil,
        privacyRuleId: nil,
        retryAfter: nil
    )
}

struct AIClassificationFallbackStatusRegion: View {
    var status: AiFallbackStatus
    var isResolving: Bool
    var actionTitle: (AiFallbackAction) -> String
    var actionID: (AiFallbackAction) -> String
    var isActionDisabled: (AiFallbackAction) -> Bool
    var isActionVisible: (AiFallbackAction) -> Bool
    var onAction: (AiFallbackAction) -> Void

    var body: some View {
        ReasonStatusCard(
            badge: isResolving ? L10n.string("Resolving") : badgeText,
            badgeTint: badgeTint,
            accessibilityIdentifier: "ai-fallback-ai-classification-suggestion-ai-fallback",
            badgeAccessibilityIdentifier: "ai-fallback-ai-classification-suggestion-reason-badge"
        ) {
            Text(isResolving ? L10n.string("Resolving AI status...") : status.title)
                .font(.subheadline.weight(.semibold))
        } message: {
            Text(isResolving ? resolvingMessage : status.message)
                .foregroundStyle(.secondary)
        } actions: {
            actionRow
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if isResolving {
                resolvingActionButton(.retry)
                resolvingActionButton(.classifyManually)
            } else {
                if status.retryable {
                    actionButton(.retry)
                } else if let retryDisabledReason = status.retryDisabledReason {
                    Text(retryDisabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(fallbackActions, id: \.self, content: actionButton(_:))
            }
        }
    }

    private var fallbackActions: [AiFallbackAction] {
        [
            status.primaryAction == .retry ? nil : status.primaryAction,
            status.secondaryAction,
            status.nonAiFallbackAction
        ].compactMap { $0 }.reduce(into: []) { actions, action in
            if isActionVisible(action), !actions.contains(action) {
                actions.append(action)
            }
        }
    }

    private func actionButton(_ action: AiFallbackAction) -> some View {
        Button(actionTitle(action)) {
            onAction(action)
        }
        .disabled(isActionDisabled(action))
        .accessibilityIdentifier("ai-fallback-ai-classification-suggestion-action-\(actionID(action))")
    }

    private func resolvingActionButton(_ action: AiFallbackAction) -> some View {
        Button(actionTitle(action)) {}
            .disabled(true)
            .accessibilityIdentifier("ai-fallback-ai-classification-suggestion-action-\(actionID(action))-resolving")
    }

    private var resolvingMessage: String {
        L10n.string(
            "AreaMatrix is mapping the AI category fallback reason. Recovery actions are disabled until it completes."
        )
    }

    private var badgeText: String {
        switch status.kind {
        case .aiDisabled: L10n.string("AI disabled")
        case .featureDisabled: L10n.string("Feature disabled")
        case .localModelNotReady: L10n.string("Local not ready")
        case .remoteNotConfigured: L10n.string("Remote not configured")
        case .remoteFailed: L10n.string("Remote failed")
        case .providerUnavailable: L10n.string("Provider unavailable")
        case .privacySkipped: L10n.string("Privacy skipped")
        case .noEligibleInput: L10n.string("No eligible input")
        case .callLogUnavailable: L10n.string("Call log unavailable")
        case .rateLimited: L10n.string("Rate limited")
        case .timeout: L10n.string("Timeout")
        case .internalFailure: L10n.string("Internal failure")
        case .semanticIndexNotReady, .normalSearchUnavailable: L10n.string("Not available")
        }
    }

    private var badgeTint: Color {
        switch status.category {
        case .skipped: .blue
        case .disabled, .unavailable: .orange
        case .error: .red
        }
    }
}
