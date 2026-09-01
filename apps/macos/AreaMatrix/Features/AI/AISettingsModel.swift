import AreaMatrixFeatureAI
import Combine
import Foundation

struct AISettingsError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
    var detail: String
}

enum AISettingsActionFeedback: Equatable {
    case success(LocalizedMessage)
    case failed(AISettingsError)
}

enum AISettingsPrivacyGateUpdateResult: Equatable {
    case saved
    case unchanged
    case needsRemoteConfiguration
    case failed
}

@MainActor
protocol AIPrivacyGateSettingsSynchronizing: AnyObject {
    func syncPrivacyGateFromPrivacyRules(_ enabled: Bool) async -> AISettingsError?
}

@MainActor
final class AISettingsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(AISettingsError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var snapshot: AISettingsSnapshot?
    @Published private(set) var saveError: AISettingsError?
    @Published private(set) var actionFeedback: AISettingsActionFeedback?
    @Published private(set) var isSaving = false

    let repoPath: String
    private let loader: any CoreAISettingsLoading
    private let updater: any CoreAISettingsUpdating
    private let errorMapper: any CoreErrorMapping
    private var savedSnapshot: AISettingsSnapshot?
    private var pendingSave: AISettingsConfigSnapshot?
    private var pendingSaveFailureMessage = L10n.message("AI settings could not be saved.")
    private var pendingSavePreservesSnapshot = false
    private var pendingPause: AISettingsConfigSnapshot?

    init(
        repoPath: String,
        loader: any CoreAISettingsLoading,
        updater: any CoreAISettingsUpdating,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.errorMapper = errorMapper
    }

    var isLoaded: Bool {
        loadState == .loaded
    }

    var hasRetryableSave: Bool {
        pendingSave != nil && !isSaving
    }

    var hasRetryablePause: Bool {
        pendingPause != nil && !isSaving
    }

    func load() async {
        loadState = .loading
        saveError = nil
        actionFeedback = nil
        pendingSave = nil
        pendingPause = nil
        do {
            let loaded = try await loader.loadAISettings(repoPath: repoPath)
            snapshot = loaded
            savedSnapshot = loaded
            loadState = .loaded
        } catch {
            snapshot = nil
            savedSnapshot = nil
            loadState = await .failed(settingsError(
                for: error,
                message: L10n.message("AI settings could not be loaded."),
                fallbackRecovery: L10n.message("Retry")
            ))
        }
    }

    func setAIEnabled(_ enabled: Bool) async {
        guard var config = editableConfig(), config.aiEnabled != enabled else { return }
        config.aiEnabled = enabled
        await persist(config, failureMessage: L10n.message("AI settings could not be saved."))
    }

    func setLocalAIEnabled(_ enabled: Bool) async {
        guard var config = editableConfig(), config.localAIEnabled != enabled else { return }
        config.localAIEnabled = enabled
        await persist(config, failureMessage: L10n.message("AI settings could not be saved."))
    }

    func setProviderPreference(_ preference: AISettingsProviderPreference) async {
        guard var config = editableConfig(), config.providerPreference != preference else { return }
        if preference == .remoteFirst, !config.remoteAIAllowed {
            actionFeedback = .failed(AISettingsError(
                message: L10n.message("Remote AI requires explicit setup."),
                recovery: L10n.message("Use Configure remote AI before selecting Remote first."),
                detail: L10n.string(
                    "Remote AI configuration manages provider setup, API key storage, and connection verification."
                )
            ))
            return
        }
        config.providerPreference = preference
        await persist(config, failureMessage: L10n.message("AI settings could not be saved."))
    }

    func setFeature(_ feature: AISettingsFeatureKind, enabled: Bool) async {
        guard var config = editableConfig() else { return }
        config.setFeature(feature, enabled: enabled)
        await persist(config, failureMessage: L10n.message("AI settings could not be saved."))
    }

    func disableRemoteAI() async {
        guard var config = editableConfig(), config.remoteAIAllowed else { return }
        config.remoteAIAllowed = false
        if config.providerPreference == .remoteFirst {
            config.providerPreference = .localFirst
        }
        await persist(config, failureMessage: L10n.message("AI settings could not be saved."))
    }

    func pauseAllAI() async {
        guard var config = editableConfig(), config.aiEnabled else { return }
        config.aiEnabled = false
        await persist(config, failureMessage: L10n.message("AI could not be paused."), restoreOnFailure: true)
    }

    func retrySave() async {
        guard let pendingSave else { return }
        await persist(
            pendingSave,
            failureMessage: pendingSaveFailureMessage,
            preserveSavedSnapshotOnFailure: pendingSavePreservesSnapshot
        )
    }

    func retryPause() async {
        guard let pendingPause else { return }
        await persist(pendingPause, failureMessage: L10n.message("AI could not be paused."), restoreOnFailure: true)
    }

    func revertChanges() {
        snapshot = savedSnapshot
        pendingSave = nil
        pendingSaveFailureMessage = L10n.message("AI settings could not be saved.")
        pendingSavePreservesSnapshot = false
        pendingPause = nil
        saveError = nil
        actionFeedback = nil
    }

    func openRemoteConfigurationEntry() {
        actionFeedback = .success(L10n.message("Open Remote AI configuration to manage providers and API keys."))
    }

    func openLocalModelStatusEntry() {
        actionFeedback = .success(L10n.message("Open Local model status to check installation and diagnostics."))
    }

    func openPrivacyRulesEntry() {
        actionFeedback = .success(L10n.message("Open Privacy rules to manage AI data boundaries."))
    }

    func openCallLogEntry() {
        actionFeedback = .success(L10n.message("Open AI call log to review recent AI activity."))
    }

    func allowRemoteAIAfterProviderConsent() async -> AISettingsPrivacyGateUpdateResult {
        guard let config = editableConfig() else { return .failed }
        guard config.remoteAIAllowed else {
            actionFeedback = .failed(AISettingsError(
                message: L10n.message("Remote AI requires provider consent."),
                recovery: L10n.message("Configure remote AI before allowing the privacy gate."),
                detail: L10n.string("ai.settings.remoteProviderConsentDetail")
            ))
            return .needsRemoteConfiguration
        }
        return await setPrivacyGateEnabled(true, successMessage: L10n.message("Remote AI privacy gate is allowed."))
    }

    func blockRemoteAIWithPrivacyGate() async -> AISettingsPrivacyGateUpdateResult {
        await setPrivacyGateEnabled(false, successMessage: L10n.message("Remote AI is blocked by the privacy gate."))
    }

    func syncPrivacyGateFromPrivacyRules(_ enabled: Bool) async -> AISettingsError? {
        if !isLoaded {
            await load()
        }
        if case let .failed(error) = loadState {
            return error
        }
        let result = await setPrivacyGateEnabled(enabled, successMessage: privacyGateSyncSuccess(enabled))
        switch result {
        case .saved, .unchanged:
            return nil
        case .needsRemoteConfiguration, .failed:
            return saveError ?? AISettingsError(
                message: L10n.message("AI settings privacy summary could not be refreshed."),
                recovery: L10n.message("Retry save before returning to AI settings."),
                detail: L10n.string("ai.settings.privacySummarySyncDetail")
            )
        }
    }

    private func editableConfig() -> AISettingsConfigSnapshot? {
        snapshot?.config.normalized()
    }

    @discardableResult
    private func persist(
        _ config: AISettingsConfigSnapshot,
        failureMessage: LocalizedMessage,
        restoreOnFailure: Bool = false,
        preserveSavedSnapshotOnFailure: Bool = false,
        successMessage: LocalizedMessage? = nil
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        saveError = nil
        actionFeedback = nil
        do {
            let updated = try await updater.updateAISettings(repoPath: repoPath, newConfig: config.normalized())
            snapshot = updated
            savedSnapshot = updated
            pendingSave = nil
            pendingSaveFailureMessage = L10n.message("AI settings could not be saved.")
            pendingSavePreservesSnapshot = false
            pendingPause = nil
            actionFeedback = successMessage.map(AISettingsActionFeedback.success) ??
                (restoreOnFailure ? .success(L10n.message("AI paused.")) : nil)
            isSaving = false
            return true
        } catch {
            let mapped = await settingsError(
                for: error,
                message: failureMessage,
                fallbackRecovery: L10n.message("Retry save")
            )
            if restoreOnFailure {
                snapshot = savedSnapshot
                pendingPause = config
            } else if preserveSavedSnapshotOnFailure {
                snapshot = savedSnapshot
                pendingSave = config
                pendingSaveFailureMessage = failureMessage
                pendingSavePreservesSnapshot = true
            } else if let current = snapshot {
                snapshot = current.withPendingConfig(config)
                pendingSave = config
                pendingSaveFailureMessage = failureMessage
                pendingSavePreservesSnapshot = false
            }
            saveError = mapped
        }
        isSaving = false
        return false
    }

    private func settingsError(
        for error: Error,
        message: LocalizedMessage,
        fallbackRecovery: LocalizedMessage
    ) async -> AISettingsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: message,
                recovery: mapping.recoveryMessage(fallback: fallbackRecovery),
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: fallbackRecovery, detail: error.localizedDescription)
    }

    private func setPrivacyGateEnabled(
        _ enabled: Bool,
        successMessage: LocalizedMessage
    ) async -> AISettingsPrivacyGateUpdateResult {
        guard var config = editableConfig() else { return .failed }
        guard config.privacyGateEnabled != enabled else { return .unchanged }
        config.privacyGateEnabled = enabled
        let saved = await persist(
            config,
            failureMessage: L10n.message("Remote AI privacy gate could not be updated."),
            preserveSavedSnapshotOnFailure: true,
            successMessage: successMessage
        )
        return saved ? .saved : .failed
    }

    private func privacyGateSyncSuccess(_ enabled: Bool) -> LocalizedMessage {
        enabled
            ? L10n.message("Remote AI privacy gate is allowed.")
            : L10n.message("Remote AI is blocked by the privacy gate.")
    }
}

extension AISettingsModel: AIPrivacyGateSettingsSynchronizing {}
