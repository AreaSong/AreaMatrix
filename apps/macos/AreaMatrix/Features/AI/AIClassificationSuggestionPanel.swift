import SwiftUI

struct AIClassificationSuggestionRouteView: View {
    let repoPath: String
    let file: FileEntrySnapshot?
    let moveState: MainFileCategoryMoveState
    let returnContext: AIClassificationSuggestionReturnContext?
    let onCancel: () -> Void
    let onBeginChange: (Int64, String?) -> Void
    let onPreview: (Int64, String) -> Void
    let onApply: (AIClassificationSuggestionApplyRequest) -> Void
    let onOpenAIRecoverySettings: () -> Void
    @State private var presentedRecoverySheet: AIClassificationRecoverySheet?
    @State private var callLogRoute: AIClassificationCallLogRoute?
    @StateObject private var model: AIClassificationSuggestionPanelModel

    init(
        repoPath: String,
        file: FileEntrySnapshot?,
        moveState: MainFileCategoryMoveState = .idle,
        returnContext: AIClassificationSuggestionReturnContext? = nil,
        onCancel: @escaping () -> Void,
        onBeginChange: @escaping (Int64, String?) -> Void,
        onPreview: @escaping (Int64, String) -> Void = { _, _ in },
        onApply: @escaping (AIClassificationSuggestionApplyRequest) -> Void = { _ in },
        onOpenAIRecoverySettings: @escaping () -> Void
    ) {
        self.repoPath = repoPath
        self.file = file
        self.moveState = moveState
        self.returnContext = returnContext
        self.onCancel = onCancel
        self.onBeginChange = onBeginChange
        self.onPreview = onPreview
        self.onApply = onApply
        self.onOpenAIRecoverySettings = onOpenAIRecoverySettings
        _model = StateObject(wrappedValue: AIClassificationSuggestionPanelModel(
            repoPath: repoPath,
            request: AIClassificationSuggestionRequestState(
                fileID: file?.id ?? 0,
                contextPolicy: .limitedTextSummary
            )
        ))
    }

    var body: some View {
        MainFileActionSheetContainer(title: "AI Category Suggestion", pageID: "S3-04") {
            if let file {
                AIClassificationSuggestionPanel(
                    model: model,
                    fileName: file.currentName,
                    currentPath: file.path,
                    moveState: moveState,
                    returnContext: returnContext,
                    onPreview: previewSuggestion,
                    onApply: applySuggestion,
                    onChange: changeSuggestion,
                    onClassifyManually: classifyManually,
                    onViewCall: { callLogRoute = AIClassificationCallLogRoute(callLogID: $0) },
                    onOpenAISettings: onOpenAIRecoverySettings,
                    onOpenLocalModelStatus: { presentedRecoverySheet = .localModelStatus },
                    onConfigureRemoteAI: { presentedRecoverySheet = .remoteConfig }
                )
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
        .sheet(item: $presentedRecoverySheet, content: recoverySheet)
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID
            ) {
                callLogRoute = nil
            }
        }
    }

    @ViewBuilder
    private func recoverySheet(_ sheet: AIClassificationRecoverySheet) -> some View {
        switch sheet {
        case .localModelStatus:
            LocalModelStatusView(model: LocalModelStatusModel(repoPath: repoPath)) { presentedRecoverySheet = nil }
        case .remoteConfig:
            RemoteModelConfigSheet(model: RemoteProviderConfigModel(repoPath: repoPath), onClose: {
                presentedRecoverySheet = nil
            })
        }
    }

    private func changeSuggestion() {
        guard let file else { return }
        onBeginChange(file.id, suggestedCategory)
    }

    private func classifyManually() {
        guard let file else { return }
        onBeginChange(file.id, nil)
    }

    private var suggestedCategory: String? {
        let category = model.suggestion?.suggestedCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        return category?.isEmpty == false ? category : nil
    }

    private func previewSuggestion(_ category: String) {
        guard let file else { return }
        onPreview(file.id, category)
    }

    private func applySuggestion(_ request: AIClassificationSuggestionPanelApplyRequest) {
        guard let file else { return }
        onApply(AIClassificationSuggestionApplyRequest(
            fileID: file.id,
            targetCategory: request.targetCategory,
            moveFile: request.moveFile,
            rememberRule: request.rememberRule,
            suggestion: request.suggestion,
            preview: request.preview
        ))
    }
}

private enum AIClassificationRecoverySheet: String, Identifiable {
    case localModelStatus, remoteConfig
    var id: String { rawValue }
}

private struct AIClassificationCallLogRoute: Identifiable, Equatable {
    var callLogID: Int64
    var id: Int64 { callLogID }
}

struct AIClassificationSuggestionPanel: View {
    @ObservedObject var model: AIClassificationSuggestionPanelModel
    var fileName: String
    var currentPath: String
    var moveState: MainFileCategoryMoveState = .idle
    var returnContext: AIClassificationSuggestionReturnContext?
    var onPreview: (String) -> Void = { _ in }
    var onApply: (AIClassificationSuggestionPanelApplyRequest) -> Void = { _ in }
    var onChange: () -> Void = {}
    var onClassifyManually: () -> Void = {}
    var onViewCall: (Int64) -> Void = { _ in }
    var onOpenAISettings: () -> Void = {}
    var onOpenLocalModelStatus: () -> Void = {}
    var onConfigureRemoteAI: () -> Void = {}
    @State var privacyRuleRoute: AIPrivacyRulesRoute?
    @State var rememberRule = false
    @State var rejectedFeedback: AIClassificationSuggestionRejectedFeedback?
    @State var showApplyConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI suggested a category")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            fileSummary
            Text(model.statusText)
                .foregroundStyle(statusTint)
                .accessibilityIdentifier("S3-04-C3-04-status")
            if let returnContext {
                Label(returnContext.message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("S3-04-C3-04-return-status")
            }
            if let suggestion = model.suggestion {
                suggestionContent(suggestion)
            }
            if let fallbackStatus = model.fallbackStatus {
                fallbackContent(fallbackStatus)
            } else if model.isResolvingFallbackStatus {
                fallbackContent(.s310ResolvingClassificationStatus)
            }
            if let failure = model.failure {
                failureContent(failure)
            }
            requestControls
        }
        .padding(16)
        .background(.background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .sheet(item: $privacyRuleRoute) { route in
            AIPrivacyRulesRouteSheet(repoPath: model.repoPath, focus: route.focus) {
                privacyRuleRoute = nil
            }
        }
    }

    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File: \(fileName)")
            Text("Current path: \(currentPath)")
            Text("No files will be moved until you confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var requestControls: some View {
        HStack {
            Button("Ask AI for suggestion...") {
                Task { await model.askForSuggestion() }
            }
            .disabled(!model.canAskForSuggestion)
            .accessibilityIdentifier("S3-04-C3-04-ask-ai-suggestion")
            Button("Classify manually", action: onClassifyManually)
                .disabled(model.isResolvingFallbackStatus)
            Spacer()
        }
    }

    private var statusTint: Color {
        if model.failure != nil { return .red }
        if model.state.isLoading { return .secondary }
        return .primary
    }

    private func fallbackContent(_ status: AiFallbackStatus) -> some View {
        AIFallbackStatusRegion(
            status: status,
            isResolving: model.isResolvingFallbackStatus,
            actionTitle: actionTitle(for:),
            actionID: actionAccessibilitySuffix(for:),
            isActionDisabled: isFallbackActionDisabled(_:),
            isActionVisible: isFallbackActionVisible(_:),
            onAction: performFallbackAction(_:)
        )
    }

    private func failureContent(_ failure: AISettingsError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.message)
            Text(failure.detail)
                .foregroundStyle(.secondary)
            Text(failure.recovery)
                .font(.caption)
        }
        .accessibilityIdentifier("S3-04-C3-04-error")
    }

    func performFallbackAction(_ action: AiFallbackAction) {
        switch action {
        case .retry:
            Task { await model.retryFallbackSuggestion() }
        case .openAiSettings:
            onOpenAISettings()
        case .openLocalModelStatus:
            onOpenLocalModelStatus()
        case .configureRemoteAi:
            onConfigureRemoteAI()
        case .viewPrivacyRule:
            privacyRuleRoute = s309PrivacyRuleRoute(ruleID: model.fallbackStatus?.privacyRuleId)
        case .viewCallLog:
            if let callLogID = model.fallbackStatus?.callLogId {
                onViewCall(callLogID)
            }
        case .classifyManually:
            onClassifyManually()
        case .retryLater, .buildSemanticIndex, .useNormalSearch:
            break
        }
    }

    func s309PrivacyRuleRoute(ruleID: String?) -> AIPrivacyRulesRoute? {
        let normalizedRuleID = ruleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedRuleID.isEmpty else { return nil }
        return AIPrivacyRulesRoute(repoPath: model.repoPath, focus: .rule(ruleID: normalizedRuleID))
    }

    func isFallbackActionDisabled(_ action: AiFallbackAction) -> Bool {
        switch action {
        case .retry:
            model.fallbackStatus?.retryable != true
        case .viewPrivacyRule:
            model.fallbackStatus?.privacyRuleId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        case .viewCallLog:
            model.fallbackStatus?.callLogId == nil
        case .openAiSettings, .openLocalModelStatus, .configureRemoteAi, .classifyManually:
            false
        case .retryLater, .buildSemanticIndex, .useNormalSearch:
            true
        }
    }

    private func isFallbackActionVisible(_ action: AiFallbackAction) -> Bool {
        switch action {
        case .retry, .retryLater, .openAiSettings, .openLocalModelStatus, .configureRemoteAi, .viewPrivacyRule,
             .viewCallLog, .classifyManually:
            true
        case .buildSemanticIndex, .useNormalSearch:
            false
        }
    }

    private func actionTitle(for action: AiFallbackAction) -> String {
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

    private func actionAccessibilitySuffix(for action: AiFallbackAction) -> String {
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
}

private extension AiFallbackStatus {
    static let s310ResolvingClassificationStatus = AiFallbackStatus(
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

private struct AIFallbackStatusRegion: View {
    var status: AiFallbackStatus
    var isResolving: Bool
    var actionTitle: (AiFallbackAction) -> String
    var actionID: (AiFallbackAction) -> String
    var isActionDisabled: (AiFallbackAction) -> Bool
    var isActionVisible: (AiFallbackAction) -> Bool
    var onAction: (AiFallbackAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                reasonBadge
                Text(isResolving ? "Resolving AI status..." : status.title)
                    .font(.subheadline.weight(.semibold))
            }
            Text(isResolving ? resolvingMessage : status.message)
                .foregroundStyle(.secondary)
            actionRow
        }
        .padding(10)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S3-10-C3-04-ai-fallback")
    }

    private var reasonBadge: some View {
        Text(isResolving ? "Resolving" : badgeText)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeTint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityIdentifier("S3-10-C3-04-reason-badge")
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
        .accessibilityIdentifier("S3-10-C3-04-action-\(actionID(action))")
    }

    private func resolvingActionButton(_ action: AiFallbackAction) -> some View {
        Button(actionTitle(action)) {}
            .disabled(true)
            .accessibilityIdentifier("S3-10-C3-04-action-\(actionID(action))-resolving")
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

struct AIClassificationPrivacyRuleRoute: Identifiable, Equatable {
    var ruleID: String
    var id: String { ruleID }
}

struct AISuggestionConfidenceBadge: View {
    var confidence: Float

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(lowConfidence ? Color.orange.opacity(0.14) : Color.green.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(label)
    }

    private var label: String { lowConfidence ? "Low confidence \(percent)%" : "Confidence \(percent)%" }
    private var percent: Int { Int((min(max(confidence, 0), 1) * 100).rounded()) }
    private var lowConfidence: Bool { confidence < 0.6 }
}
