import SwiftUI

@MainActor
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
    let aiDependencies: AIFeatureDependencies
    let errorMapper: any CoreErrorMapping
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
        onOpenAIRecoverySettings: @escaping () -> Void,
        aiDependencies: AIFeatureDependencies,
        errorMapper: any CoreErrorMapping
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
        self.aiDependencies = aiDependencies
        self.errorMapper = errorMapper
        _model = StateObject(wrappedValue: AIClassificationSuggestionPanelModel(
            repoPath: repoPath,
            request: AIClassificationSuggestionRequestState(
                fileID: file?.id ?? 0,
                contextPolicy: .limitedTextSummary
            ),
            suggester: aiDependencies.aiClassificationSuggester,
            fallbackReader: aiDependencies.aiClassificationFallbackReader,
            errorMapper: errorMapper
        ))
    }

    var body: some View {
        MainFileActionSheetContainer(title: L10n.string("AI Category Suggestion"), pageID: "ai-category-suggestion") {
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
                    onConfigureRemoteAI: { presentedRecoverySheet = .remoteConfig },
                    aiDependencies: aiDependencies,
                    errorMapper: errorMapper
                )
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
        .sheet(item: $presentedRecoverySheet, content: recoverySheet)
        .sheet(item: $callLogRoute) { route in
            AIClassificationCallLogDetailSheet(
                repoPath: repoPath,
                callLogID: route.callLogID,
                lister: aiDependencies.aiCallLogLister,
                errorMapper: errorMapper,
                onClose: {
                    callLogRoute = nil
                }
            )
        }
    }

    @ViewBuilder
    private func recoverySheet(_ sheet: AIClassificationRecoverySheet) -> some View {
        switch sheet {
        case .localModelStatus:
            LocalModelStatusView(
                model: LocalModelStatusModel(
                    repoPath: repoPath,
                    storageLocationProvider: aiDependencies.localModelStorageLocationProvider,
                    statusReader: aiDependencies.localModelStatusReader,
                    installHelpOpener: aiDependencies.localModelInstallHelpOpener,
                    folderOpener: aiDependencies.localModelFolderOpener,
                    diagnosticsCopier: aiDependencies.localModelDiagnosticsCopier,
                    errorMapper: errorMapper
                ),
                onClose: { presentedRecoverySheet = nil }
            )
        case .remoteConfig:
            RemoteModelConfigSheet(
                model: RemoteProviderConfigModel(
                    repoPath: repoPath,
                    bridge: aiDependencies.remoteProviderConfigurer,
                    credentialStore: aiDependencies.remoteProviderCredentialStore,
                    errorMapper: errorMapper
                ),
                privacyModel: RemotePrivacyGateModel(
                    repoPath: repoPath,
                    bridge: aiDependencies.aiPrivacyRulesManager,
                    errorMapper: errorMapper
                ),
                onClose: {
                    presentedRecoverySheet = nil
                }
            )
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
    var id: String {
        rawValue
    }
}

private struct AIClassificationCallLogRoute: Identifiable, Equatable {
    var callLogID: Int64
    var id: Int64 {
        callLogID
    }
}

struct AIClassificationSuggestionPanel: View {
    @EnvironmentObject private var localizer: AppLocalizer
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
    var aiDependencies: AIFeatureDependencies?
    var errorMapper: (any CoreErrorMapping)?
    @State var privacyRuleRoute: AIPrivacyRulesRoute?
    @State var rememberRule = false
    @State var rejectedFeedback: AIClassificationSuggestionRejectedFeedback?
    @State var showApplyConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.string("AI suggested a category"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            fileSummary
            Text(model.statusText)
                .foregroundStyle(statusTint)
                .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-status")
            if let returnContext {
                Label(returnContext.message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-return-status")
            }
            if let suggestion = model.suggestion {
                suggestionContent(suggestion)
            }
            if let fallbackStatus = model.fallbackStatus {
                fallbackContent(fallbackStatus)
            } else if model.isResolvingFallbackStatus {
                fallbackContent(.aiFallbackResolvingClassificationStatus)
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
            if let aiDependencies, let errorMapper {
                AIPrivacyRulesRouteSheet(
                    repoPath: model.repoPath,
                    featureDependencies: aiDependencies,
                    errorMapper: errorMapper,
                    registryReader: aiDependencies.privacyRuleRegistryReader,
                    focus: route.focus,
                    onClose: {
                        privacyRuleRoute = nil
                    }
                )
            } else {
                Text(L10n.string("AI provider is unavailable."))
                    .padding(24)
                    .frame(width: 560)
            }
        }
    }

    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File: \(fileName)")
            Text("Current path: \(currentPath)")
            Text(L10n.string("No files will be moved until you confirm."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var requestControls: some View {
        HStack {
            Button(L10n.string("Ask AI for suggestion...")) {
                Task { await model.askForSuggestion() }
            }
            .disabled(!model.canAskForSuggestion)
            .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-ask-ai-suggestion")
            Button(L10n.string("Classify manually"), action: onClassifyManually)
                .disabled(model.isResolvingFallbackStatus)
            Spacer()
        }
    }

    private var statusTint: Color {
        if model.failure != nil { return .red }
        if model.state.isLoading { return .secondary }
        return .primary
    }

    private func fallbackContent(_ status: AIFallbackStatusSnapshot) -> some View {
        AIClassificationFallbackStatusRegion(
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
            Text(localizer.resolve(failure.message))
            Text(failure.detail)
                .foregroundStyle(.secondary)
            Text(localizer.resolve(failure.recovery))
                .font(.caption)
        }
        .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-error")
    }

    func performFallbackAction(_ action: AIFallbackActionSnapshot) {
        switch action {
        case .retry:
            Task { await model.retryFallbackSuggestion() }
        case .openAISettings:
            onOpenAISettings()
        case .openLocalModelStatus:
            onOpenLocalModelStatus()
        case .configureRemoteAI:
            onConfigureRemoteAI()
        case .viewPrivacyRule:
            privacyRuleRoute = aiPrivacyRulesPrivacyRuleRoute(ruleID: model.fallbackStatus?.privacyRuleID)
        case .viewCallLog:
            if let callLogID = model.fallbackStatus?.callLogID {
                onViewCall(callLogID)
            }
        case .classifyManually:
            onClassifyManually()
        case .retryLater, .buildSemanticIndex, .useNormalSearch:
            break
        }
    }

    func aiPrivacyRulesPrivacyRuleRoute(ruleID: String?) -> AIPrivacyRulesRoute? {
        let normalizedRuleID = ruleID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedRuleID.isEmpty else { return nil }
        return AIPrivacyRulesRoute(repoPath: model.repoPath, focus: .rule(ruleID: normalizedRuleID))
    }

    func isFallbackActionDisabled(_ action: AIFallbackActionSnapshot) -> Bool {
        switch action {
        case .retry:
            model.fallbackStatus?.retryable != true
        case .viewPrivacyRule:
            model.fallbackStatus?.privacyRuleID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        case .viewCallLog:
            model.fallbackStatus?.callLogID == nil
        case .openAISettings, .openLocalModelStatus, .configureRemoteAI, .classifyManually:
            false
        case .retryLater, .buildSemanticIndex, .useNormalSearch:
            true
        }
    }

    private func isFallbackActionVisible(_ action: AIFallbackActionSnapshot) -> Bool {
        switch action {
        case .retry, .retryLater, .openAISettings, .openLocalModelStatus, .configureRemoteAI, .viewPrivacyRule,
             .viewCallLog, .classifyManually:
            true
        case .buildSemanticIndex, .useNormalSearch:
            false
        }
    }

    private func actionTitle(for action: AIFallbackActionSnapshot) -> String {
        switch action {
        case .retry: L10n.string("Retry")
        case .retryLater: L10n.string("Retry later")
        case .openAISettings: L10n.string("Open AI settings")
        case .openLocalModelStatus: L10n.string("Open local model status")
        case .configureRemoteAI: L10n.string("Configure remote AI")
        case .viewPrivacyRule: L10n.string("View privacy rule")
        case .viewCallLog: L10n.string("View call log")
        case .buildSemanticIndex: L10n.string("Build semantic index")
        case .useNormalSearch: L10n.string("Use normal search")
        case .classifyManually: L10n.string("Classify manually")
        }
    }

    private func actionAccessibilitySuffix(for action: AIFallbackActionSnapshot) -> String {
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
}

struct AIClassificationPrivacyRuleRoute: Identifiable, Equatable {
    var ruleID: String
    var id: String {
        ruleID
    }
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

    private var label: String {
        lowConfidence
            ? L10n.format("ai.classification.lowConfidencePercent", percent)
            : L10n.format("ai.classification.confidencePercent", percent)
    }

    private var percent: Int {
        Int((min(max(confidence, 0), 1) * 100).rounded())
    }

    private var lowConfidence: Bool {
        confidence < 0.6
    }
}
