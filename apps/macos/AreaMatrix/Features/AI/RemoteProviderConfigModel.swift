import Combine
import Foundation

@MainActor
final class RemoteProviderConfigModel: ObservableObject {
    @Published private(set) var loadState: RemoteProviderLoadState = .idle
    @Published var snapshot: RemoteProviderConfigState?
    @Published var testResult: RemoteProviderTestResultState?
    @Published var outcome: RemoteProviderOutcome?
    @Published var unusedCredentialReference: String?

    @Published var provider: RemoteProviderKindState = .openAi {
        didSet { resetVerificationIfChanged() }
    }

    @Published var modelID = "gpt-4.1-mini" {
        didSet { resetVerificationIfChanged() }
    }

    @Published var endpointURL = "" {
        didSet { resetVerificationIfChanged() }
    }

    @Published var apiKey = "" {
        didSet { resetVerificationIfChanged() }
    }

    @Published var selectedScopes: Set<AISettingsFeatureKind> = [.autoSummaries] {
        didSet { normalizeScope() }
    }

    @Published var dataFlowConfirmed = false

    let repoPath: String
    let bridge: any CoreRemoteProviderConfiguring
    let credentialStore: any RemoteProviderCredentialStoring
    let errorMapper: any CoreErrorMapping
    var verifiedCredentialDraft: RemoteProviderCredentialDraft?
    var verifiedToken: String?
    var lastFingerprint: RemoteProviderDraftFingerprint?
    var isApplyingSnapshot = false

    init(
        repoPath: String,
        bridge: any CoreRemoteProviderConfiguring = CoreBridge(),
        credentialStore: any RemoteProviderCredentialStoring = RemoteProviderKeychainCredentialStore(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.bridge = bridge
        self.credentialStore = credentialStore
        self.errorMapper = errorMapper
    }

    var canTestConnection: Bool {
        !loadState.isBusy && currentDraft.canTestConnection
    }

    var canEnable: Bool {
        !loadState.isBusy && currentDraft.canEnable(verifiedToken: verifiedToken)
    }

    var canRetryEnable: Bool {
        unusedCredentialReference != nil && canEnable
    }

    var enableDisabledReason: String {
        currentDraft.enableDisabledReason(verifiedToken: verifiedToken)
    }

    func load() async {
        guard !loadState.isBusy else { return }
        loadState = .loading
        outcome = nil
        do {
            let loaded = try await bridge.loadRemoteProviderConfig(repoPath: repoPath)
            applySnapshot(loaded)
            loadState = .loaded
        } catch {
            loadState = await .failed(remoteError(
                for: error,
                message: "Remote AI settings could not be loaded.",
                fallbackRecovery: "Retry"
            ))
        }
    }

    func testConnection() async {
        guard canTestConnection else { return }
        loadState = .testing
        outcome = nil
        do {
            try discardExistingDraftBeforeTest()
        } catch {
            loadState = .loaded
            outcome = .failed(credentialCleanupError(
                for: error,
                message: "Previous API key draft could not be discarded before testing.",
                recovery: "Retry Test connection or cancel without saving."
            ))
            return
        }

        do {
            let draft = try credentialStore.storeCredential(
                provider: provider,
                endpointURL: currentDraft.normalizedEndpointURL,
                apiKey: currentDraft.trimmedAPIKey
            )
            if let failure = await runProviderTest(draft: draft) {
                outcome = .failed(failure)
            }
            loadState = .loaded
        } catch {
            loadState = await .failed(remoteError(
                for: error,
                message: "Remote provider could not be tested.",
                fallbackRecovery: "Check the key, model, endpoint, and network."
            ))
        }
    }

    @discardableResult
    func enableRemoteAI() async -> Bool {
        guard canEnable, let token = verifiedToken, let draft = verifiedCredentialDraft else { return false }
        loadState = .enabling
        outcome = nil
        do {
            let enabled = try await bridge.enableRemoteProvider(
                repoPath: repoPath,
                request: currentDraft.enableRequest(token: token, keyReference: draft.reference)
            )
            credentialStore.commitCredentialDraft(draft)
            applySnapshot(enabled)
            outcome = .success("Remote AI enabled.")
            loadState = .loaded
            return true
        } catch {
            if draft.replacesExistingCredential {
                do {
                    try clearDraftCredential()
                } catch {
                    loadState = .loaded
                    outcome = .failed(credentialCleanupError(
                        for: error,
                        message: "Remote AI settings could not be saved, and the API key draft could not be restored.",
                        recovery: "Retry save or cancel after restoring the stored key."
                    ))
                    return false
                }
            } else {
                unusedCredentialReference = draft.reference
            }
            loadState = await .failed(remoteError(
                for: error,
                message: "Remote AI settings could not be saved.",
                fallbackRecovery: "Retry save or remove the unused key."
            ))
            return false
        }
    }

    @discardableResult
    func disableRemoteAI(removeStoredCredential: Bool) async -> Bool {
        guard snapshot?.remoteProviderEnabled == true else { return false }
        loadState = .disabling
        outcome = nil
        let keyReference = storedCredentialReferenceForDisable()
        do {
            let disabled = try await bridge.disableRemoteProvider(
                repoPath: repoPath,
                request: RemoteProviderDisableRequestState(removeStoredCredential: removeStoredCredential)
            )
            if removeStoredCredential, let keyReference {
                do {
                    try credentialStore.removeCredential(reference: keyReference)
                } catch {
                    applySnapshot(disabled)
                    outcome = .failed(credentialCleanupError(
                        for: error,
                        message: "Remote AI was disabled, but the stored API key could not be removed.",
                        recovery: "Retry disable with key removal or remove the key from Keychain."
                    ))
                    loadState = .loaded
                    return false
                }
            }
            applySnapshot(disabled)
            outcome = .success("Remote AI disabled.")
            loadState = .loaded
            return true
        } catch {
            loadState = await .failed(remoteError(
                for: error,
                message: "Remote AI could not be disabled.",
                fallbackRecovery: "Retry disable."
            ))
            return false
        }
    }

    @discardableResult
    func cancelEditing() -> Bool {
        do {
            try clearDraftCredential()
            return true
        } catch {
            outcome = .failed(credentialCleanupError(
                for: error,
                message: "API key draft could not be discarded.",
                recovery: "Retry Cancel or remove the stored key from Keychain."
            ))
            return false
        }
    }

    func removeUnusedCredential() {
        do {
            try clearUnusedCredential()
        } catch {
            outcome = .failed(credentialCleanupError(
                for: error,
                message: "Unused API key could not be removed.",
                recovery: "Retry Remove unused key before closing this sheet."
            ))
        }
    }

    func retryEnable() async {
        await enableRemoteAI()
    }
}
