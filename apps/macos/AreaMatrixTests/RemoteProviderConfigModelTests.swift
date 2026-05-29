@testable import AreaMatrix
import XCTest

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
