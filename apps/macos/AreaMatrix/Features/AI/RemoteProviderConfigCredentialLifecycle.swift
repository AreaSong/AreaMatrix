import AreaMatrixFeatureAI
import Foundation

extension RemoteProviderConfigModel {
    func runProviderTest(draft: RemoteProviderCredentialDraft) async -> AISettingsError? {
        do {
            let result = try await bridge.testRemoteProvider(
                repoPath: repoPath,
                request: currentDraft.testRequest(keyReference: draft.reference)
            )
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
                    message: L10n.message("API key draft could not be discarded after the connection test failed."),
                    recovery: L10n.message("Retry Remove unused key or cancel after cleanup succeeds.")
                )
            }
            return await remoteError(
                for: error,
                message: L10n.message("Remote provider could not be tested."),
                fallbackRecovery: L10n.message("Check the key, model, endpoint, and network.")
            )
        }
    }

    func applySnapshot(_ newSnapshot: RemoteProviderConfigState) {
        isApplyingSnapshot = true
        defer {
            isApplyingSnapshot = false
            lastFingerprint = currentDraft.fingerprint
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

    func handleTestResult(_ result: RemoteProviderTestResultState, draft: RemoteProviderCredentialDraft) {
        testResult = result
        if result.providerVerified, let token = result.verificationToken {
            verifiedToken = token
            verifiedCredentialDraft = draft
            lastFingerprint = currentDraft.fingerprint
            unusedCredentialReference = nil
            outcome = .success(L10n.message("Connection verified."))
            return
        }

        do {
            try credentialStore.discardCredentialDraft(draft)
        } catch {
            retainCredentialDraftAfterCleanupFailure(draft)
            outcome = .failed(credentialCleanupError(
                for: error,
                message: L10n.message("API key draft could not be discarded after the connection test failed."),
                recovery: L10n.message("Retry Remove unused key or cancel after cleanup succeeds.")
            ))
            return
        }
        verifiedToken = nil
        verifiedCredentialDraft = nil
        outcome = .failed(AISettingsError(
            message: testFailureTitle(result.status),
            recovery: L10n.message("Edit the provider details and test again."),
            detail: result.sanitizedMessage
        ))
    }

    func resetVerificationIfChanged() {
        guard !isApplyingSnapshot, lastFingerprint != nil, currentDraft.fingerprint != lastFingerprint else { return }
        discardVerifiedDraftCredential()
        verifiedToken = nil
        testResult = nil
    }

    func storedCredentialReferenceForDisable() -> String? {
        guard let snapshot, snapshot.credentialConfigured else { return verifiedCredentialDraft?.reference }
        guard let snapshotProvider = snapshot.provider else { return verifiedCredentialDraft?.reference }
        return credentialStore.storedCredentialReference(
            provider: snapshotProvider,
            endpointURL: snapshot.endpointURL
        )
    }

    var currentDraft: RemoteProviderConfigDraft {
        RemoteProviderConfigDraft(
            provider: provider,
            modelID: modelID,
            endpointURL: endpointURL,
            apiKey: apiKey,
            selectedScopes: selectedScopes,
            dataFlowConfirmed: dataFlowConfirmed
        )
    }

    func normalizeScope() {
        if selectedScopes.isEmpty { verifiedToken = nil }
    }

    func clearUnusedCredential() throws {
        if let draft = verifiedCredentialDraft, draft.reference == unusedCredentialReference {
            try clearDraftCredential()
        } else if let reference = unusedCredentialReference {
            try credentialStore.removeCredential(reference: reference)
        } else {
            try clearDraftCredential()
        }
        unusedCredentialReference = nil
    }

    func discardVerifiedDraftCredential() {
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
                message: L10n.message("API key draft could not be discarded after provider details changed."),
                recovery: L10n.message("Retry Cancel or remove the unused key.")
            ))
        }
    }

    func discardExistingDraftBeforeTest() throws {
        guard let draft = verifiedCredentialDraft else { return }
        do {
            try clearDraftCredential()
            unusedCredentialReference = nil
        } catch {
            retainCredentialDraftAfterCleanupFailure(draft)
            throw error
        }
    }

    func clearDraftCredential() throws {
        guard let draft = verifiedCredentialDraft else {
            verifiedToken = nil
            testResult = nil
            return
        }
        try credentialStore.discardCredentialDraft(draft)
        clearVerifiedDraftState()
    }

    func testFailureTitle(_ status: RemoteProviderTestStatusState) -> LocalizedMessage {
        RemoteProviderConfigErrorFactory.testFailureTitle(status)
    }

    func remoteError(
        for error: Error,
        message: LocalizedMessage,
        fallbackRecovery: LocalizedMessage
    ) async -> AISettingsError {
        await RemoteProviderConfigErrorFactory.remoteError(
            for: error,
            errorMapper: errorMapper,
            message: message,
            fallbackRecovery: fallbackRecovery
        )
    }

    func credentialCleanupError(
        for error: Error,
        message: LocalizedMessage,
        recovery: LocalizedMessage
    ) -> AISettingsError {
        RemoteProviderConfigErrorFactory.credentialCleanupError(
            for: error,
            message: message,
            recovery: recovery
        )
    }

    func retainCredentialDraftAfterCleanupFailure(_ draft: RemoteProviderCredentialDraft) {
        verifiedCredentialDraft = draft
        verifiedToken = nil
        testResult = nil
        if !draft.replacesExistingCredential {
            unusedCredentialReference = draft.reference
        }
    }

    func clearVerifiedDraftState() {
        verifiedCredentialDraft = nil
        verifiedToken = nil
        testResult = nil
    }
}
