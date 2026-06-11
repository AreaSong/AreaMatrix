@testable import AreaMatrix
import XCTest

// swiftlint:disable:next type_body_length
final class RemoteProviderConfigModelTests: XCTestCase {
    @MainActor
    func testEnableUsesKeychainReferenceAndVerifiedToken() async {
        let bridge = RemoteProviderConfigBridge()
        let store = RemoteProviderTestCredentialStore()
        let model = makeModel(bridge: bridge, store: store)

        await model.load()
        model.apiKey = "  dummy-api-key  "
        model.selectedScopes = [.autoSummaries, .autoTags]
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didEnable = await model.enableRemoteAI()
        let requests = await bridge.requests()

        XCTAssertTrue(didEnable)
        XCTAssertEqual(requests.loadCount, 1)
        XCTAssertEqual(requests.test?.keyReference, "keychain:openAi-managed")
        XCTAssertEqual(requests.test?.modelID, "gpt-4.1-mini")
        XCTAssertEqual(requests.enable?.keyReference, "keychain:openAi-managed")
        XCTAssertEqual(requests.enable?.verificationToken, "verified-s303")
        XCTAssertEqual(requests.enable?.featureScope, [.autoSummaries, .autoTags])
        XCTAssertEqual(requests.enable?.dataFlowConfirmed, true)
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "dummy-api-key"])
        XCTAssertEqual(model.apiKey, "")
        XCTAssertEqual(model.snapshot?.remoteProviderEnabled, true)
        XCTAssertTrue(model.cancelEditing())
        XCTAssertEqual(store.removedReferences(), [])
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "dummy-api-key"])
    }

    @MainActor
    func testRequiresRetestAfterDraftChanges() async {
        await assertRetestAfterChange { $0.modelID = "claude-3-haiku" }
        await assertRetestAfterChange { $0.apiKey = "second-api-key" }
    }

    @MainActor
    func testRestoresCredentialWhenTestFails() async {
        await assertFailedTestRestoresSavedCredential(testMode: .coreFailure)
        await assertFailedTestRestoresSavedCredential(testMode: .rejected)
    }

    @MainActor
    func testRemovesNewCredentialWhenTestIsRejected() async {
        let bridge = RemoteProviderConfigBridge(testMode: .rejected)
        let store = RemoteProviderTestCredentialStore()
        let model = makeModel(bridge: bridge, store: store)

        model.apiKey = "dummy-api-key"
        await model.testConnection()

        XCTAssertEqual(store.storedKeys(), [:])
        XCTAssertEqual(store.removedReferences(), ["keychain:openAi-managed"])
        XCTAssertNil(model.testResult?.verificationToken)
        XCTAssertFalse(model.canEnable)
    }

    @MainActor
    func testCancelPreservesExistingSavedCredential() async {
        let store = RemoteProviderTestCredentialStore()
        let savedReference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeModel(bridge: RemoteProviderConfigBridge(), store: store)

        model.apiKey = "replacement-api-key"
        model.dataFlowConfirmed = true
        await model.testConnection()
        XCTAssertTrue(model.canEnable)
        XCTAssertTrue(model.cancelEditing())

        XCTAssertEqual(store.storedKeys(), [savedReference: "saved-api-key"])
        XCTAssertEqual(store.removedReferences(), [])
        XCTAssertFalse(model.canEnable)
    }

    @MainActor
    func testTracksUnusedCredentialWhenEnableFails() async {
        let store = RemoteProviderTestCredentialStore()
        let model = makeModel(
            bridge: RemoteProviderConfigBridge(enableFails: true),
            store: store
        )

        model.apiKey = "dummy-api-key"
        model.selectedScopes = [.autoSummaries]
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didEnable = await model.enableRemoteAI()

        XCTAssertFalse(didEnable)
        XCTAssertEqual(model.unusedCredentialReference, "keychain:openAi-managed")
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "dummy-api-key"])
        model.removeUnusedCredential()
        XCTAssertEqual(store.storedKeys(), [:])
        XCTAssertEqual(store.removedReferences(), ["keychain:openAi-managed"])
        XCTAssertFalse(model.canEnable)
    }

    @MainActor
    func testRestoresSavedCredentialWhenEnableFails() async {
        let store = RemoteProviderTestCredentialStore()
        let savedReference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeModel(
            bridge: RemoteProviderConfigBridge(enableFails: true),
            store: store
        )

        model.apiKey = "replacement-api-key"
        model.selectedScopes = [.autoSummaries]
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didEnable = await model.enableRemoteAI()

        XCTAssertFalse(didEnable)
        XCTAssertNil(model.unusedCredentialReference)
        XCTAssertEqual(store.storedKeys(), [savedReference: "saved-api-key"])
        XCTAssertEqual(store.removedReferences(), [])
        XCTAssertFalse(model.canEnable)
    }

    @MainActor
    func testDisableHonorsStoredKeyConfirmation() async {
        await assertDisable(removeStoredCredential: true, removed: ["keychain:openAi-managed"], credential: false)
        await assertDisable(removeStoredCredential: false, removed: [], credential: true)
    }

    @MainActor
    func testRejectedProviderReportsCleanupFailureWithoutEnabling() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .oneShot)
        let model = makeModel(
            bridge: RemoteProviderConfigBridge(testMode: .rejected),
            store: store
        )

        model.apiKey = "new-api-key"
        model.dataFlowConfirmed = true
        await model.testConnection()

        XCTAssertFalse(model.canEnable)
        XCTAssertEqual(model.unusedCredentialReference, "keychain:openAi-managed")
        XCTAssertEqual(
            model.outcome?.errorMessage,
            "API key draft could not be discarded after the connection test failed."
        )
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "new-api-key"])

        model.removeUnusedCredential()

        XCTAssertNil(model.unusedCredentialReference)
        XCTAssertEqual(store.storedKeys(), [:])
        XCTAssertEqual(store.removedReferences(), ["keychain:openAi-managed"])
    }

    @MainActor
    func testCancelReportsDraftRestoreFailureAndKeepsSheetOpenState() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .always)
        let reference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeModel(bridge: RemoteProviderConfigBridge(), store: store)

        model.apiKey = "replacement-api-key"
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didCancel = model.cancelEditing()

        XCTAssertFalse(didCancel)
        XCTAssertEqual(model.outcome?.errorMessage, "API key draft could not be discarded.")
        XCTAssertEqual(store.storedKeys(), [reference: "replacement-api-key"])
        XCTAssertTrue(model.canEnable)
    }

    @MainActor
    func testRetestReportsDraftCleanupFailureAndClearsVerifiedToken() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .always)
        let reference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeModel(bridge: RemoteProviderConfigBridge(), store: store)

        model.apiKey = "replacement-api-key"
        model.dataFlowConfirmed = true
        await model.testConnection()
        model.modelID = "gpt-4.1-mini-updated"

        XCTAssertFalse(model.canEnable)
        await model.testConnection()

        XCTAssertEqual(
            model.outcome?.errorMessage,
            "Previous API key draft could not be discarded before testing."
        )
        XCTAssertEqual(store.storedKeys(), [reference: "replacement-api-key"])
        XCTAssertFalse(model.canEnable)
    }

    @MainActor
    func testRemoveUnusedCredentialReportsDeleteFailureAndKeepsRetryState() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .always)
        let model = makeModel(
            bridge: RemoteProviderConfigBridge(enableFails: true),
            store: store
        )

        model.apiKey = "new-api-key"
        model.selectedScopes = [.autoSummaries]
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didEnable = await model.enableRemoteAI()
        XCTAssertFalse(didEnable)
        model.removeUnusedCredential()

        XCTAssertEqual(model.unusedCredentialReference, "keychain:openAi-managed")
        XCTAssertEqual(model.outcome?.errorMessage, "Unused API key could not be removed.")
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "new-api-key"])
    }

    @MainActor
    func testEnableFailureReportsExistingCredentialRestoreFailure() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .always)
        let reference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeModel(
            bridge: RemoteProviderConfigBridge(enableFails: true),
            store: store
        )

        model.apiKey = "replacement-api-key"
        model.selectedScopes = [.autoSummaries]
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didEnable = await model.enableRemoteAI()

        XCTAssertFalse(didEnable)
        XCTAssertNil(model.unusedCredentialReference)
        XCTAssertEqual(
            model.outcome?.errorMessage,
            "Remote AI settings could not be saved, and the API key draft could not be restored."
        )
        XCTAssertEqual(store.storedKeys(), [reference: "replacement-api-key"])
        XCTAssertTrue(model.canEnable)
    }

    @MainActor
    func testDisableWithKeyRemovalReportsKeychainFailure() async {
        let store = RemoteProviderTestCredentialStore(removeFailure: .always)
        let model = makeModel(
            bridge: RemoteProviderConfigBridge(initial: .remoteProviderConfigEnabled()),
            store: store
        )

        await model.load()
        let didDisable = await model.disableRemoteAI(removeStoredCredential: true)

        XCTAssertFalse(didDisable)
        XCTAssertEqual(model.snapshot?.remoteProviderEnabled, false)
        XCTAssertEqual(
            model.outcome?.errorMessage,
            "Remote AI was disabled, but the stored API key could not be removed."
        )
    }

    @MainActor
    func testS303C309EnableTurnsOnPrivacyGateWithProviderScope() async {
        let bridge = RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(privacyGateEnabled: false))
        let model = RemotePrivacyGateModel(
            repoPath: "/tmp/s303",
            bridge: bridge,
            errorMapper: RemoteProviderConfigErrorMapper()
        )

        let didEnable = await model.enablePrivacyGate(providerConfig: .remoteProviderConfigEnabled())
        let requests = await bridge.requests()

        XCTAssertTrue(didEnable)
        XCTAssertEqual(model.snapshot?.privacyGateEnabled, true)
        XCTAssertEqual(requests.loadCount, 1)
        XCTAssertEqual(requests.updates.count, 1)
        XCTAssertEqual(requests.updates.first?.privacyGateEnabled, true)
        XCTAssertEqual(requests.updates.first?.providerScope.remoteProviderEnabled, true)
        XCTAssertEqual(requests.updates.first?.providerScope.featureScope, [.autoSummaries])
        XCTAssertEqual(requests.updates.first?.rules.first?.name, "Block confidential")
        XCTAssertEqual(requests.updates.first?.remoteAllowedFields[1].field, .extractedTextExcerpt)
        XCTAssertEqual(requests.updates.first?.remoteAllowedFields[1].allowRemote, false)
    }

    @MainActor
    func testS303C309DisableTurnsOffPrivacyGateWithoutClearingProviderConfig() async {
        let bridge = RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(privacyGateEnabled: true))
        let model = RemotePrivacyGateModel(
            repoPath: "/tmp/s303",
            bridge: bridge,
            errorMapper: RemoteProviderConfigErrorMapper()
        )
        var disabledProvider = RemoteProviderConfigState.remoteProviderConfigEnabled()
        disabledProvider.remoteProviderEnabled = false

        let didDisableGate = await model.disablePrivacyGate(providerConfig: disabledProvider)
        let requests = await bridge.requests()

        XCTAssertTrue(didDisableGate)
        XCTAssertEqual(model.snapshot?.privacyGateEnabled, false)
        XCTAssertEqual(requests.updates.first?.privacyGateEnabled, false)
        XCTAssertEqual(requests.updates.first?.providerScope.providerConfigured, true)
        XCTAssertEqual(requests.updates.first?.providerScope.remoteProviderEnabled, false)
    }

    @MainActor
    func testS303C309PrivacyGateFailureKeepsRetryableAction() async {
        let bridge = RemotePrivacyRulesBridge(updateFails: true)
        let model = RemotePrivacyGateModel(
            repoPath: "/tmp/s303",
            bridge: bridge,
            errorMapper: RemoteProviderConfigErrorMapper()
        )

        let didEnable = await model.enablePrivacyGate(providerConfig: .remoteProviderConfigEnabled())

        XCTAssertFalse(didEnable)
        XCTAssertEqual(model.pendingAction, .enable)
        XCTAssertEqual(
            model.failure?.message,
            "Remote provider was configured, but privacy gate could not be enabled."
        )
        XCTAssertEqual(model.failure?.detail, "Remote provider save failed")
    }

    @MainActor
    func testS303PageIntegrationWiresEntryEnablePrivacyGateDisableAndExitRefresh() async {
        let providerBridge = RemoteProviderConfigBridge()
        let privacyBridge = RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(privacyGateEnabled: false))
        let store = RemoteProviderTestCredentialStore()
        let remoteModel = makeModel(bridge: providerBridge, store: store)
        let privacyModel = RemotePrivacyGateModel(
            repoPath: "/tmp/s303",
            bridge: privacyBridge,
            errorMapper: RemoteProviderConfigErrorMapper()
        )

        await remoteModel.load()
        await privacyModel.load()
        remoteModel.apiKey = "integration-api-key"
        remoteModel.selectedScopes = [.classificationSuggestions, .autoSummaries]
        remoteModel.dataFlowConfirmed = true
        await remoteModel.testConnection()
        let didEnable = await remoteModel.enableRemoteAI()
        let didEnableGate = await privacyModel.enablePrivacyGate(providerConfig: remoteModel.snapshot)
        let providerRequestsAfterEnable = await providerBridge.requests()
        let privacyRequestsAfterEnable = await privacyBridge.requests()

        XCTAssertTrue(didEnable)
        XCTAssertTrue(didEnableGate)
        assertS303EnabledPageIntegration(
            remoteModel: remoteModel,
            privacyModel: privacyModel,
            providerRequests: providerRequestsAfterEnable,
            privacyRequests: privacyRequestsAfterEnable,
            store: store
        )

        let didDisable = await remoteModel.disableRemoteAI(removeStoredCredential: false)
        let didDisableGate = await privacyModel.disablePrivacyGate(providerConfig: remoteModel.snapshot)
        let providerRequestsAfterDisable = await providerBridge.requests()
        let privacyRequestsAfterDisable = await privacyBridge.requests()

        XCTAssertTrue(didDisable)
        XCTAssertTrue(didDisableGate)
        assertS303DisabledPageIntegration(
            remoteModel: remoteModel,
            privacyModel: privacyModel,
            providerRequests: providerRequestsAfterDisable,
            privacyRequests: privacyRequestsAfterDisable,
            store: store
        )
    }

    @MainActor
    func testS303PageIntegrationKeepsProviderEnabledAndOffersRecoveryWhenPrivacyGateEnableFails() async {
        let providerBridge = RemoteProviderConfigBridge()
        let privacyBridge = RemotePrivacyRulesBridge(updateFails: true)
        let remoteModel = makeModel(bridge: providerBridge, store: RemoteProviderTestCredentialStore())
        let privacyModel = RemotePrivacyGateModel(
            repoPath: "/tmp/s303",
            bridge: privacyBridge,
            errorMapper: RemoteProviderConfigErrorMapper()
        )

        await remoteModel.load()
        remoteModel.apiKey = "integration-api-key"
        remoteModel.selectedScopes = [.autoSummaries]
        remoteModel.dataFlowConfirmed = true
        await remoteModel.testConnection()
        let didEnable = await remoteModel.enableRemoteAI()
        let didEnableGate = await privacyModel.enablePrivacyGate(providerConfig: remoteModel.snapshot)

        XCTAssertTrue(didEnable)
        XCTAssertFalse(didEnableGate)
        XCTAssertEqual(remoteModel.snapshot?.remoteProviderEnabled, true)
        XCTAssertEqual(remoteModel.snapshot?.credentialConfigured, true)
        XCTAssertEqual(privacyModel.pendingAction, .enable)
        XCTAssertEqual(
            privacyModel.failure?.message,
            "Remote provider was configured, but privacy gate could not be enabled."
        )
    }

    @MainActor
    private func makeModel(
        bridge: RemoteProviderConfigBridge,
        store: RemoteProviderTestCredentialStore
    ) -> RemoteProviderConfigModel {
        RemoteProviderConfigModel(
            repoPath: "/tmp/s303",
            bridge: bridge,
            credentialStore: store,
            errorMapper: RemoteProviderConfigErrorMapper()
        )
    }

    @MainActor
    private func assertRetestAfterChange(_ mutate: (RemoteProviderConfigModel) -> Void) async {
        let bridge = RemoteProviderConfigBridge()
        let store = RemoteProviderTestCredentialStore()
        let model = makeModel(bridge: bridge, store: store)

        model.apiKey = "dummy-api-key"
        model.dataFlowConfirmed = true
        await model.testConnection()
        XCTAssertTrue(model.canEnable)
        mutate(model)

        XCTAssertFalse(model.canEnable)
        XCTAssertEqual(store.removedReferences(), ["keychain:openAi-managed"])
        let didEnable = await model.enableRemoteAI()
        let requests = await bridge.requests()
        XCTAssertFalse(didEnable)
        XCTAssertNil(requests.enable)
    }

    @MainActor
    private func assertFailedTestRestoresSavedCredential(testMode: RemoteProviderConfigBridge.TestMode) async {
        let store = RemoteProviderTestCredentialStore()
        let savedReference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeModel(bridge: RemoteProviderConfigBridge(testMode: testMode), store: store)

        model.apiKey = "replacement-api-key"
        await model.testConnection()

        XCTAssertEqual(store.storedKeys(), [savedReference: "saved-api-key"])
        XCTAssertEqual(store.removedReferences(), [])
        XCTAssertFalse(model.canEnable)
    }

    @MainActor
    private func assertDisable(removeStoredCredential: Bool, removed: [String], credential: Bool) async {
        let bridge = RemoteProviderConfigBridge(initial: .remoteProviderConfigEnabled())
        let store = RemoteProviderTestCredentialStore()
        let model = makeModel(bridge: bridge, store: store)

        await model.load()
        let didDisable = await model.disableRemoteAI(removeStoredCredential: removeStoredCredential)
        let requests = await bridge.requests()

        XCTAssertTrue(didDisable)
        XCTAssertEqual(requests.disable?.removeStoredCredential, removeStoredCredential)
        XCTAssertEqual(store.removedReferences(), removed)
        XCTAssertEqual(model.snapshot?.remoteProviderEnabled, false)
        XCTAssertEqual(model.snapshot?.credentialConfigured, credential)
    }
}
