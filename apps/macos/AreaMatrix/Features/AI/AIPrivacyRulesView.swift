import Combine
import SwiftUI

enum AIPrivacyRemoteProviderLoadState: Equatable {
    case loading
    case loaded
    case failed(AISettingsError)
}

@MainActor
final class AIPrivacyRemoteProviderStateModel: ObservableObject {
    @Published private(set) var loadState: AIPrivacyRemoteProviderLoadState = .loading
    @Published private(set) var snapshot: RemoteProviderConfigState?

    let repoPath: String
    private let providerReader: any CoreRemoteProviderConfiguring
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        providerReader: any CoreRemoteProviderConfiguring = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.providerReader = providerReader
        self.errorMapper = errorMapper
    }

    var allowsPrivacyGateEnable: Bool {
        guard let snapshot else { return false }
        return snapshot.providerConfigured &&
            snapshot.providerVerified &&
            snapshot.remoteProviderEnabled &&
            !snapshot.featureScope.isEmpty
    }

    var providerStatusText: String {
        switch loadState {
        case .loading:
            "Loading remote provider..."
        case .failed:
            "Remote provider state unavailable"
        case .loaded:
            loadedProviderStatusText
        }
    }

    var verifiedStatusText: String {
        guard let snapshot else { return "Loading" }
        return snapshot.providerVerified ? "Connection tested" : "Connection test required"
    }

    var enabledStatusText: String {
        guard let snapshot else { return "Loading" }
        return snapshot.remoteProviderEnabled ? "Remote provider enabled" : "Remote provider disabled"
    }

    var featureScopeText: String {
        guard let snapshot else { return "Loading" }
        guard !snapshot.featureScope.isEmpty else { return "No remote usage scope selected" }
        return snapshot.featureScope.map(\.title).joined(separator: ", ")
    }

    func load() async {
        loadState = .loading
        do {
            snapshot = try await providerReader.loadRemoteProviderConfig(repoPath: repoPath)
            loadState = .loaded
        } catch {
            snapshot = nil
            loadState = .failed(await providerError(for: error))
        }
    }

    private var loadedProviderStatusText: String {
        guard let snapshot else { return "Remote provider state unavailable" }
        if !snapshot.providerConfigured { return "Configure remote AI required" }
        if !snapshot.providerVerified { return "Remote provider needs connection test." }
        if !snapshot.remoteProviderEnabled { return "Remote provider is disabled in AI settings." }
        if snapshot.featureScope.isEmpty { return "Remote scope is not selected." }
        return "Configured by S3-03"
    }

    private func providerError(for error: Error) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: "Remote provider state could not be loaded.",
                recovery: mapping.suggestedAction.isEmpty ? "Retry or configure remote AI." : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: "Remote provider state could not be loaded.",
            recovery: "Retry or configure remote AI.",
            detail: error.localizedDescription
        )
    }
}

struct AIPrivacyRulesView: View {
    @ObservedObject var model: AISettingsModel
    @StateObject private var providerModel: AIPrivacyRemoteProviderStateModel
    let onConfigureRemoteAI: () -> Void
    let onClose: () -> Void

    init(
        model: AISettingsModel,
        providerModel: AIPrivacyRemoteProviderStateModel? = nil,
        onConfigureRemoteAI: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        _providerModel = StateObject(wrappedValue: providerModel ??
            AIPrivacyRemoteProviderStateModel(repoPath: model.repoPath))
        self.onConfigureRemoteAI = onConfigureRemoteAI
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    bodyContent
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
        .task {
            await loadPage()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Privacy Rules")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(model.repoPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(24)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.loadState {
        case .loading:
            ProgressView("Loading privacy rules...")
        case let .failed(error):
            AISettingsInlineBanner(error: error, tint: .red) {
                Button("Retry", action: retryLoad)
                Button("Back to AI settings", action: onClose)
            }
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            feedbackBanner
            providerLoadFailureBanner
            AdvancedSettingsSection(title: "Remote AI privacy gate") {
                AdvancedSettingsKeyValueRow(label: "Status", value: remoteGateStatus)
                AdvancedSettingsKeyValueRow(label: "Remote provider", value: providerModel.providerStatusText)
                AdvancedSettingsKeyValueRow(label: "Provider verified", value: providerModel.verifiedStatusText)
                AdvancedSettingsKeyValueRow(label: "Remote provider enabled", value: providerModel.enabledStatusText)
                AdvancedSettingsKeyValueRow(label: "Feature scope", value: providerModel.featureScopeText)
                AdvancedSettingsKeyValueRow(label: "Privacy policy", value: privacyPolicyStatus)
                Text(
                    "This control only updates the C3-01 privacy gate. Provider credentials, connection tests, " +
                        "scope, and disabling remote provider remain in S3-03."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Allow remote AI after provider consent", action: allowRemoteGate)
                        .disabled(allowRemoteGateDisabled)
                        .accessibilityIdentifier("S3-09-C3-03-allow-remote-ai-after-provider-consent")
                        .accessibilityHint(allowRemoteGateDisabledReason)
                    Button("Block remote AI with privacy gate", action: blockRemoteGate)
                        .disabled(model.isSaving || model.snapshot?.config.privacyGateEnabled == false)
                        .accessibilityIdentifier("S3-09-C3-03-block-remote-ai-privacy-gate")
                }
                Button("Configure remote AI", action: onConfigureRemoteAI)
                    .accessibilityIdentifier("S3-09-C3-03-configure-remote-ai")
            }
        }
    }

    @ViewBuilder
    private var feedbackBanner: some View {
        if let error = model.saveError {
            AISettingsInlineBanner(error: error, tint: .red) {
                if model.hasRetryableSave {
                    Button("Retry save", action: retrySave)
                    Button("Revert changes", action: model.revertChanges)
                }
            }
        } else if let feedback = model.actionFeedback {
            switch feedback {
            case let .success(message):
                Label(message, systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case let .failed(error):
                AISettingsInlineBanner(error: error, tint: .orange) {
                    Button("Configure remote AI", action: onConfigureRemoteAI)
                }
            }
        }
    }

    @ViewBuilder
    private var providerLoadFailureBanner: some View {
        if case let .failed(error) = providerModel.loadState {
            AISettingsInlineBanner(error: error, tint: .red) {
                Button("Retry", action: retryProviderLoad)
                Button("Configure remote AI", action: onConfigureRemoteAI)
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Saving remote AI privacy gate")
            }
            Spacer()
            Button("Close", action: onClose)
        }
        .padding(16)
    }

    private var remoteGateStatus: String {
        model.snapshot?.config.privacyGateEnabled == true ? "Remote AI allowed" : "Remote AI blocked"
    }

    private var privacyPolicyStatus: String {
        guard let config = model.snapshot?.config else { return "Loading" }
        return config.privacyPolicyRef ?? "Default gate policy"
    }

    private var allowRemoteGateDisabled: Bool {
        model.isSaving || !providerModel.allowsPrivacyGateEnable
    }

    private var allowRemoteGateDisabledReason: String {
        guard !model.isSaving else { return "Saving privacy gate." }
        if case .loading = providerModel.loadState { return "Remote provider state is loading." }
        if case .failed = providerModel.loadState { return "Remote provider state could not be loaded." }
        guard let snapshot = providerModel.snapshot else { return "Remote provider state is unavailable." }
        if !snapshot.providerConfigured { return "Configure remote AI before allowing the privacy gate." }
        if !snapshot.providerVerified { return "Remote provider needs connection test." }
        if !snapshot.remoteProviderEnabled { return "Remote provider is disabled in AI settings." }
        if snapshot.featureScope.isEmpty { return "Select a remote usage scope in S3-03." }
        return ""
    }

    private func loadPage() async {
        if !model.isLoaded {
            await model.load()
        }
        await providerModel.load()
    }

    private func retryLoad() {
        Task {
            await loadPage()
        }
    }

    private func retryProviderLoad() {
        Task {
            await providerModel.load()
        }
    }

    private func retrySave() {
        Task {
            await model.retrySave()
        }
    }

    private func allowRemoteGate() {
        Task {
            guard providerModel.allowsPrivacyGateEnable else {
                onConfigureRemoteAI()
                return
            }
            let result = await model.allowRemoteAIAfterProviderConsent()
            if result == .needsRemoteConfiguration {
                onConfigureRemoteAI()
            }
        }
    }

    private func blockRemoteGate() {
        Task {
            await model.blockRemoteAIWithPrivacyGate()
        }
    }
}
