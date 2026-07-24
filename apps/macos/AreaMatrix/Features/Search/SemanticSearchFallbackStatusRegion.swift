import SwiftUI

@MainActor
struct SemanticSearchFallbackStatusRegion: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let page: SemanticSearchResultPageSnapshot
    let state: SemanticFallbackState
    let repoPath: String?
    let isIndexBuildBusy: Bool
    let isPrivacyGateChecking: Bool
    let onAction: (AiFallbackAction) -> Void
    @State private var recoverySheet: SemanticSearchFallbackRecoverySheet?

    init(
        page: SemanticSearchResultPageSnapshot,
        state: SemanticFallbackState,
        repoPath: String? = nil,
        isIndexBuildBusy: Bool,
        isPrivacyGateChecking: Bool,
        onAction: @escaping (AiFallbackAction) -> Void
    ) {
        self.page = page
        self.state = state
        self.repoPath = repoPath
        self.isIndexBuildBusy = isIndexBuildBusy
        self.isPrivacyGateChecking = isPrivacyGateChecking
        self.onAction = onAction
    }

    var body: some View {
        fallbackContent
            .sheet(item: $recoverySheet, content: recoverySheetContent)
    }

    @ViewBuilder
    private var fallbackContent: some View {
        switch presentation {
        case .none:
            EmptyView()
        case .resolving:
            Text("Resolving AI status...")
                .accessibilityIdentifier("ai-fallback-semantic-search-core-resolving-fallback-status")
        case let .status(status):
            statusContent(status)
        case let .coreStatusError(error):
            HStack(spacing: 10) {
                Text("AI fallback status could not be loaded: \(error.userMessage)")
                let status = SemanticSearchFallbackStatus.fromSemanticPage(page)
                fallbackActionButton(status.presentation(for: .useNormalSearch), status: status)
            }
            .accessibilityIdentifier("ai-fallback-semantic-search-core-fallback-status-error")
        }
    }

    private var presentation: SemanticSearchFallbackPresentation {
        if case .loading = state { return .resolving }
        if let status = state.status, status.operation == .semanticSearch { return .status(.fromCoreStatus(status)) }
        if let error = state.errorMapping {
            return .coreStatusError(error)
        }
        guard page.fallbackReason != nil else { return .none }
        return .status(.fromSemanticPage(page))
    }

    private func statusContent(_ status: SemanticSearchFallbackStatus) -> some View {
        ReasonStatusCard(
            badge: localizer.resolve(status.badge),
            badgeTint: status.badgeTint,
            accessibilityIdentifier: "ai-fallback-semantic-search-core-fallback-status",
            badgeAccessibilityIdentifier: "ai-fallback-semantic-search-core-reason-badge",
            spacing: 6
        ) {
            Text(localizer.resolve(status.title))
                .fontWeight(.semibold)
        } message: {
            Text(localizer.resolve(status.message))
        } actions: {
            actionRow(status)
        }
    }

    private func actionRow(_ status: SemanticSearchFallbackStatus) -> some View {
        HStack(spacing: 10) {
            if status.retryable {
                fallbackActionButton(status.presentation(for: .retry), status: status)
            } else if let retryDisabledReason = status.retryDisabledReason {
                Text(localizer.resolve(retryDisabledReason))
                    .font(.caption)
            }
            ForEach(status.actionPresentations) { action in
                fallbackActionButton(action, status: status)
            }
        }
    }

    @ViewBuilder
    private func fallbackActionButton(
        _ presentation: SemanticSearchFallbackActionPresentation,
        status: SemanticSearchFallbackStatus
    ) -> some View {
        if status.isVisible(presentation.action) {
            Button(localizer.resolve(presentation.title)) {
                performAction(presentation.action)
            }
            .disabled(isDisabled(presentation.action, status: status))
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
        }
    }

    private func performAction(_ action: AiFallbackAction) {
        switch action {
        case .openLocalModelStatus where hasRepoPath:
            recoverySheet = .localModelStatus
        case .configureRemoteAi where hasRepoPath:
            recoverySheet = .remoteConfig
        default:
            onAction(action)
        }
    }

    private var hasRepoPath: Bool {
        repoPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @ViewBuilder
    private func recoverySheetContent(_ sheet: SemanticSearchFallbackRecoverySheet) -> some View {
        if let repoPath = repoPath?.trimmingCharacters(in: .whitespacesAndNewlines), !repoPath.isEmpty {
            switch sheet {
            case .localModelStatus:
                LocalModelStatusView(model: LocalModelStatusModel(repoPath: repoPath), onClose: {
                    recoverySheet = nil
                })
            case .remoteConfig:
                RemoteModelConfigSheet(model: RemoteProviderConfigModel(repoPath: repoPath), onClose: {
                    recoverySheet = nil
                })
            }
        }
    }

    private func isDisabled(_ action: AiFallbackAction, status: SemanticSearchFallbackStatus) -> Bool {
        switch action {
        case .retry:
            !status.retryable
        case .retryLater:
            true
        case .viewPrivacyRule:
            status.privacyRuleID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        case .viewCallLog:
            status.callLogID == nil
        case .buildSemanticIndex:
            isIndexBuildBusy || isPrivacyGateChecking || !status.canBuildSemanticIndex
        case .openAiSettings, .openLocalModelStatus, .configureRemoteAi, .useNormalSearch:
            false
        case .classifyManually:
            true
        }
    }
}

private enum SemanticSearchFallbackPresentation {
    case none
    case resolving
    case status(SemanticSearchFallbackStatus)
    case coreStatusError(CoreErrorMappingSnapshot)
}

private enum SemanticSearchFallbackRecoverySheet: String, Identifiable {
    case localModelStatus, remoteConfig

    var id: String {
        rawValue
    }
}
