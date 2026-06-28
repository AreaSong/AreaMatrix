import SwiftUI

extension AiFallbackStatus {
    static let aiFallbackResolvingClassificationStatus = AiFallbackStatus(
        operation: .classificationSuggestion,
        kind: .internalFailure,
        category: .unavailable,
        title: "Resolving AI status...",
        message: "AreaMatrix is mapping the AI category fallback reason.",
        retryable: false,
        retryDisabledReason: "Recovery actions are disabled until status mapping completes.",
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
            badge: isResolving ? "Resolving" : badgeText,
            badgeTint: badgeTint,
            accessibilityIdentifier: "ai-fallback-ai-classification-suggestion-ai-fallback",
            badgeAccessibilityIdentifier: "ai-fallback-ai-classification-suggestion-reason-badge"
        ) {
            Text(isResolving ? "Resolving AI status..." : status.title)
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
        "AreaMatrix is mapping the AI category fallback reason. Recovery actions are disabled until it completes."
    }

    private var badgeText: String {
        switch status.kind {
        case .aiDisabled: "AI disabled"
        case .featureDisabled: "Feature disabled"
        case .localModelNotReady: "Local not ready"
        case .remoteNotConfigured: "Remote not configured"
        case .remoteFailed: "Remote failed"
        case .providerUnavailable: "Provider unavailable"
        case .privacySkipped: "Privacy skipped"
        case .noEligibleInput: "No eligible input"
        case .callLogUnavailable: "Call log unavailable"
        case .rateLimited: "Rate limited"
        case .timeout: "Timeout"
        case .internalFailure: "Internal failure"
        case .semanticIndexNotReady, .normalSearchUnavailable: "Not available"
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
