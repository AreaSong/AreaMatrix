import Combine
import Foundation

enum RemoteProviderLoadState: Equatable {
    case idle, loading, loaded, testing, enabling, disabling, failed(AISettingsError)

    var isBusy: Bool {
        switch self {
        case .loading, .testing, .enabling, .disabling: true
        default: false
        }
    }
}

enum RemoteProviderOutcome: Equatable {
    case success(String)
    case failed(AISettingsError)
}

@MainActor
final class RemoteProviderConfigModel: ObservableObject {
    @Published private(set) var loadState: RemoteProviderLoadState = .idle
    @Published private(set) var snapshot: RemoteProviderConfigState?
    @Published private(set) var testResult: RemoteProviderTestResultState?
    @Published private(set) var outcome: RemoteProviderOutcome?
    @Published private(set) var unusedCredentialReference: String?

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
    private let bridge: any CoreRemoteProviderConfiguring
    private let credentialStore: any RemoteProviderCredentialStoring
    private let errorMapper: any CoreErrorMapping
    private var verifiedCredentialDraft: RemoteProviderCredentialDraft?
    private var verifiedToken: String?
    private var lastFingerprint: RemoteProviderDraftFingerprint?
    private var isApplyingSnapshot = false

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
        !loadState.isBusy && !trimmedModelID.isEmpty && !trimmedAPIKey.isEmpty && isEndpointValid
    }

    var canEnable: Bool {
        canTestConnection && verifiedToken != nil && !selectedScopes.isEmpty && dataFlowConfirmed
    }

    var canRetryEnable: Bool {
        unusedCredentialReference != nil && canEnable
    }

    var enableDisabledReason: String {
        if trimmedAPIKey.isEmpty { return "API key is required." }
        if selectedScopes.isEmpty { return "Select at least one usage scope." }
        if !dataFlowConfirmed { return "Confirm the remote data flow." }
        if verifiedToken == nil { return "Verify the connection before enabling remote AI." }
        return ""
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
                endpointURL: normalizedEndpointURL,
                apiKey: trimmedAPIKey
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
                request: enableRequest(token: token, keyReference: draft.reference)
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

private extension RemoteProviderConfigModel {
    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedModelID: String {
        modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEndpointURL: String? {
        let trimmed = endpointURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isEndpointValid: Bool {
        provider != .other || normalizedEndpointURL != nil
    }

    private func runProviderTest(draft: RemoteProviderCredentialDraft) async -> AISettingsError? {
        do {
            let result = try await bridge.testRemoteProvider(repoPath: repoPath, request: testRequest(draft.reference))
            handleTestResult(result, draft: draft)
            return nil
        } catch {
            do {
                try credentialStore.discardCredentialDraft(draft)
                clearVerifiedDraftState()
            } catch {
                retainCredentialDraftAfterCleanupFailure(draft)
                return credentialCleanupError(
                    for: error,
                    message: "API key draft could not be discarded after the connection test failed.",
                    recovery: "Retry Remove unused key or cancel after cleanup succeeds."
                )
            }
            return await remoteError(
                for: error,
                message: "Remote provider could not be tested.",
                fallbackRecovery: "Check the key, model, endpoint, and network."
            )
        }
    }

    private func testRequest(_ keyReference: String) -> RemoteProviderTestRequestState {
        RemoteProviderTestRequestState(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            keyReference: keyReference
        )
    }

    private func enableRequest(token: String, keyReference: String) -> RemoteProviderEnableRequestState {
        RemoteProviderEnableRequestState(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            keyReference: keyReference,
            featureScope: AISettingsFeatureKind.allCases.filter { selectedScopes.contains($0) },
            verificationToken: token,
            dataFlowConfirmed: dataFlowConfirmed
        )
    }

    private func applySnapshot(_ newSnapshot: RemoteProviderConfigState) {
        isApplyingSnapshot = true
        defer {
            isApplyingSnapshot = false
            lastFingerprint = currentFingerprint
        }
        snapshot = newSnapshot
        provider = newSnapshot.provider ?? provider
        modelID = newSnapshot.modelID ?? modelID
        endpointURL = newSnapshot.endpointURL ?? ""
        selectedScopes = Set(newSnapshot.featureScope)
        apiKey = ""
        verifiedCredentialDraft = nil
        verifiedToken = nil
        testResult = nil
        unusedCredentialReference = nil
    }

    private func handleTestResult(_ result: RemoteProviderTestResultState, draft: RemoteProviderCredentialDraft) {
        testResult = result
        if result.providerVerified, let token = result.verificationToken {
            verifiedToken = token
            verifiedCredentialDraft = draft
            lastFingerprint = currentFingerprint
            unusedCredentialReference = nil
            outcome = .success("Connection verified.")
            return
        }

        do {
            try credentialStore.discardCredentialDraft(draft)
        } catch {
            retainCredentialDraftAfterCleanupFailure(draft)
            outcome = .failed(credentialCleanupError(
                for: error,
                message: "API key draft could not be discarded after the connection test failed.",
                recovery: "Retry Remove unused key or cancel after cleanup succeeds."
            ))
            return
        }
        verifiedToken = nil
        verifiedCredentialDraft = nil
        outcome = .failed(AISettingsError(
            message: testFailureTitle(result.status),
            recovery: "Edit the provider details and test again.",
            detail: result.sanitizedMessage
        ))
    }

    private func resetVerificationIfChanged() {
        guard !isApplyingSnapshot, lastFingerprint != nil, currentFingerprint != lastFingerprint else { return }
        discardVerifiedDraftCredential()
        verifiedToken = nil
        testResult = nil
    }

    private func storedCredentialReferenceForDisable() -> String? {
        guard let snapshot, snapshot.credentialConfigured else { return verifiedCredentialDraft?.reference }
        guard let snapshotProvider = snapshot.provider else { return verifiedCredentialDraft?.reference }
        return credentialStore.storedCredentialReference(
            provider: snapshotProvider,
            endpointURL: snapshot.endpointURL
        )
    }

    private var currentFingerprint: RemoteProviderDraftFingerprint {
        RemoteProviderDraftFingerprint(
            provider: provider,
            modelID: trimmedModelID,
            endpointURL: provider == .other ? normalizedEndpointURL : nil,
            apiKey: trimmedAPIKey
        )
    }

    private func normalizeScope() {
        if selectedScopes.isEmpty { verifiedToken = nil }
    }

    private func clearUnusedCredential() throws {
        if let draft = verifiedCredentialDraft, draft.reference == unusedCredentialReference {
            try clearDraftCredential()
        } else if let reference = unusedCredentialReference {
            try credentialStore.removeCredential(reference: reference)
        } else {
            try clearDraftCredential()
        }
        unusedCredentialReference = nil
    }

    private func discardVerifiedDraftCredential() {
        guard let draft = verifiedCredentialDraft else {
            unusedCredentialReference = nil
            return
        }
        do {
            try clearDraftCredential()
            unusedCredentialReference = nil
        } catch {
            retainCredentialDraftAfterCleanupFailure(draft)
            outcome = .failed(credentialCleanupError(
                for: error,
                message: "API key draft could not be discarded after provider details changed.",
                recovery: "Retry Cancel or remove the unused key."
            ))
        }
    }

    private func discardExistingDraftBeforeTest() throws {
        guard let draft = verifiedCredentialDraft else { return }
        do {
            try clearDraftCredential()
            unusedCredentialReference = nil
        } catch {
            retainCredentialDraftAfterCleanupFailure(draft)
            throw error
        }
    }

    private func clearDraftCredential() throws {
        guard let draft = verifiedCredentialDraft else {
            verifiedToken = nil
            testResult = nil
            return
        }
        try credentialStore.discardCredentialDraft(draft)
        clearVerifiedDraftState()
    }

    private func testFailureTitle(_ status: RemoteProviderTestStatusState) -> String {
        switch status {
        case .providerRejected: "The API key was rejected by the provider."
        case .connectionFailed: "Connection failed. Check your network or endpoint URL."
        case .unsupportedProvider: "This provider is not supported yet."
        case .succeeded: "Remote provider could not be verified."
        }
    }

    private func remoteError(for error: Error, message: String, fallbackRecovery: String) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: message,
                recovery: mapping.suggestedAction.isEmpty ? fallbackRecovery : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: fallbackRecovery, detail: error.localizedDescription)
    }

    private func credentialCleanupError(for error: Error, message: String, recovery: String) -> AISettingsError {
        AISettingsError(message: message, recovery: recovery, detail: error.localizedDescription)
    }

    private func retainCredentialDraftAfterCleanupFailure(_ draft: RemoteProviderCredentialDraft) {
        verifiedCredentialDraft = draft
        verifiedToken = nil
        testResult = nil
        if !draft.replacesExistingCredential {
            unusedCredentialReference = draft.reference
        }
    }

    private func clearVerifiedDraftState() {
        verifiedCredentialDraft = nil
        verifiedToken = nil
        testResult = nil
    }
}

private struct RemoteProviderDraftFingerprint: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var apiKey: String
}
