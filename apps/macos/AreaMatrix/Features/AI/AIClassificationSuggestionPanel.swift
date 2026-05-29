import SwiftUI

struct AIClassificationSuggestionRouteView: View {
    let repoPath: String
    let file: FileEntrySnapshot?
    let onCancel: () -> Void
    let onBeginChange: (Int64, String?) -> Void
    let onViewCall: (Int64) -> Void
    let onOpenAIRecoverySettings: () -> Void
    @State private var presentedRecoverySheet: AIClassificationRecoverySheet?
    @StateObject private var model: AIClassificationSuggestionPanelModel

    init(
        repoPath: String,
        file: FileEntrySnapshot?,
        onCancel: @escaping () -> Void,
        onBeginChange: @escaping (Int64, String?) -> Void,
        onViewCall: @escaping (Int64) -> Void,
        onOpenAIRecoverySettings: @escaping () -> Void
    ) {
        self.repoPath = repoPath
        self.file = file
        self.onCancel = onCancel
        self.onBeginChange = onBeginChange
        self.onViewCall = onViewCall
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
                    onAccept: acceptSuggestion,
                    onChange: changeSuggestion,
                    onReject: onCancel,
                    onClassifyManually: classifyManually,
                    onViewCall: onViewCall,
                    onOpenAISettings: onOpenAIRecoverySettings,
                    onOpenLocalModelStatus: { presentedRecoverySheet = .localModelStatus },
                    onConfigureRemoteAI: { presentedRecoverySheet = .remoteConfig }
                )
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
        .sheet(item: $presentedRecoverySheet, content: recoverySheet)
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

    private func acceptSuggestion() {
        guard let file, let category = suggestedCategory else { return }
        onBeginChange(file.id, category)
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
}

private enum AIClassificationRecoverySheet: String, Identifiable {
    case localModelStatus, remoteConfig
    var id: String { rawValue }
}

struct AIClassificationSuggestionPanel: View {
    @ObservedObject var model: AIClassificationSuggestionPanelModel
    var fileName: String
    var currentPath: String
    var onAccept: () -> Void = {}
    var onChange: () -> Void = {}
    var onReject: () -> Void = {}
    var onClassifyManually: () -> Void = {}
    var onViewCall: (Int64) -> Void = { _ in }
    var onOpenAISettings: () -> Void = {}
    var onOpenLocalModelStatus: () -> Void = {}
    var onConfigureRemoteAI: () -> Void = {}
    @State private var privacyRuleRoute: AIClassificationPrivacyRuleRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI suggested a category")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            fileSummary
            Text(model.statusText)
                .foregroundStyle(statusTint)
                .accessibilityIdentifier("S3-04-C3-04-status")
            if let suggestion = model.suggestion {
                suggestionContent(suggestion)
            }
            if let fallbackStatus = model.fallbackStatus {
                fallbackContent(fallbackStatus)
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
            AIClassificationPrivacyRuleReferenceSheet(
                repoPath: model.repoPath,
                ruleID: route.ruleID
            ) {
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
            Spacer()
        }
    }

    private var statusTint: Color {
        if model.failure != nil { return .red }
        if model.state.isLoading { return .secondary }
        return .primary
    }

    @ViewBuilder
    private func suggestionContent(_ suggestion: AIClassificationSuggestionState) -> some View {
        switch suggestion.status {
        case .suggested:
            suggestedCard(suggestion)
        case .noSuggestion, .skipped, .unavailable:
            skippedOrUnavailableCard(suggestion)
        }
    }

    private func suggestedCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Suggested category: \(suggestion.suggestedCategory ?? "Unknown")")
                    .font(.subheadline.weight(.semibold))
                AISuggestionConfidenceBadge(confidence: suggestion.confidence)
                if let route = suggestion.route {
                    Text(route.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Current category: \(suggestion.currentCategory ?? "None")")
            Text("Reason: \(suggestion.reason ?? "No reason provided.")")
            Text("Used: \(usedContextText(for: suggestion))")
                .foregroundStyle(.secondary)
            Text("Target category: \(suggestion.suggestedCategory ?? "Unknown")")
            HStack {
                Button("Accept", action: onAccept)
                    .disabled(model.acceptDisabledReason != nil || model.state.isLoading)
                Button("Change...", action: onChange)
                    .disabled(model.state.isLoading)
                Button("Reject", action: onReject)
                    .disabled(model.state.isLoading)
            }
            if let acceptDisabledReason = model.acceptDisabledReason {
                Text(acceptDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let callLogID = suggestion.callLogID {
                Button("View AI call") {
                    onViewCall(callLogID)
                }
                .buttonStyle(.link)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S3-04-C3-04-suggestion-card")
    }

    private func skippedOrUnavailableCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = suggestion.skippedReason {
                Text("Reason: \(skipReasonText(reason))")
            }
            if let ruleID = privacyRuleID(for: suggestion) {
                Text("Privacy rule: \(ruleID)")
                    .foregroundStyle(.secondary)
                Button("View privacy rule") {
                    privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("S3-04-C3-09-view-privacy-rule")
            }
            if let callLogID = suggestion.callLogID {
                Button("View AI call") {
                    onViewCall(callLogID)
                }
                .buttonStyle(.link)
            }
        }
        .accessibilityIdentifier("S3-04-C3-04-skipped-card")
    }

    private func fallbackContent(_ status: AiFallbackStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status.message)
                .foregroundStyle(.secondary)
            HStack {
                if status.retryable {
                    Button(actionTitle(for: .retry)) {
                        Task { await model.retryFallbackSuggestion() }
                    }
                    .accessibilityIdentifier("S3-04-C3-10-retry")
                } else if let retryDisabledReason = status.retryDisabledReason {
                    Text(retryDisabledReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(fallbackActions(for: status), id: \.self) { action in
                    fallbackActionButton(action)
                }
            }
        }
        .accessibilityIdentifier("S3-04-C3-10-fallback-status")
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

    private func privacyRuleID(for suggestion: AIClassificationSuggestionState) -> String? {
        guard suggestion.skippedReason == .privacyRule else { return nil }
        let ruleID = suggestion.privacyRuleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ruleID?.isEmpty == false ? ruleID : nil
    }

    private func usedContextText(for suggestion: AIClassificationSuggestionState) -> String {
        suggestion.usedContext.isEmpty ? "none" : suggestion.usedContext.map(\.label).joined(separator: ", ")
    }

    private func skipReasonText(_ reason: AIClassificationSuggestionSkipReasonState) -> String {
        switch reason {
        case .aiDisabled: "AI classification suggestions are off"
        case .featureDisabled: "AI classification feature is off"
        case .ruleResultConfident: "rule classification is already confident"
        case .noEligibleContext: "no eligible context"
        case .privacyRule: "skipped by privacy rule"
        case .providerUnavailable: "provider unavailable"
        }
    }

    @ViewBuilder
    private func fallbackActionButton(_ action: AiFallbackAction?) -> some View {
        if let action, isFallbackActionVisible(action) {
            Button(actionTitle(for: action)) {
                performFallbackAction(action)
            }
            .disabled(isFallbackActionDisabled(action))
            .accessibilityIdentifier("S3-04-C3-10-action-\(actionAccessibilitySuffix(for: action))")
        }
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
            if let ruleID = model.fallbackStatus?.privacyRuleId?.trimmingCharacters(in: .whitespacesAndNewlines),
               !ruleID.isEmpty {
                privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
            }
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
        case .retry, .openAiSettings, .openLocalModelStatus, .configureRemoteAi, .viewPrivacyRule,
             .viewCallLog, .classifyManually:
            true
        case .retryLater, .buildSemanticIndex, .useNormalSearch:
            false
        }
    }

    private func fallbackActions(for status: AiFallbackStatus) -> [AiFallbackAction] {
        [
            status.primaryAction == .retry ? nil : status.primaryAction,
            status.secondaryAction,
            status.nonAiFallbackAction
        ].compactMap { $0 }.reduce(into: []) { actions, action in
            if isFallbackActionVisible(action), !actions.contains(action) {
                actions.append(action)
            }
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
        case .viewCallLog: "View AI call"
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

private struct AIClassificationPrivacyRuleRoute: Identifiable, Equatable {
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
