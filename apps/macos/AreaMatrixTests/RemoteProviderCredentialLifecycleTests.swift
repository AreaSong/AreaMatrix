@testable import AreaMatrix
import XCTest

final class RemoteProviderCredentialLifecycleTests: XCTestCase {
    @MainActor
    func testRestoresCredentialWhenTestFails() async {
        await assertRemoteProviderConfigFailedTestRestoresSavedCredential(testMode: .coreFailure)
        await assertRemoteProviderConfigFailedTestRestoresSavedCredential(testMode: .rejected)
    }

    @MainActor
    func testRemovesNewCredentialWhenTestIsRejected() async {
        let bridge = RemoteProviderConfigBridge(testMode: .rejected)
        let store = RemoteProviderTestCredentialStore()
        let model = makeRemoteProviderConfigModel(bridge: bridge, store: store)

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
        let model = makeRemoteProviderConfigModel(bridge: RemoteProviderConfigBridge(), store: store)

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
        let model = makeRemoteProviderConfigModel(
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
        let model = makeRemoteProviderConfigModel(
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
        await assertRemoteProviderConfigDisable(
            removeStoredCredential: true,
            removed: ["keychain:openAi-managed"],
            credential: false
        )
        await assertRemoteProviderConfigDisable(removeStoredCredential: false, removed: [], credential: true)
    }

    @MainActor
    func testRejectedProviderReportsCleanupFailureWithoutEnabling() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .oneShot)
        let model = makeRemoteProviderConfigModel(
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
            L10n.message("API key draft could not be discarded after the connection test failed.")
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
        let model = makeRemoteProviderConfigModel(bridge: RemoteProviderConfigBridge(), store: store)

        model.apiKey = "replacement-api-key"
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didCancel = model.cancelEditing()

        XCTAssertFalse(didCancel)
        XCTAssertEqual(model.outcome?.errorMessage, L10n.message("API key draft could not be discarded."))
        XCTAssertEqual(store.storedKeys(), [reference: "replacement-api-key"])
        XCTAssertTrue(model.canEnable)
    }

    @MainActor
    func testRetestReportsDraftCleanupFailureAndClearsVerifiedToken() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .always)
        let reference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeRemoteProviderConfigModel(bridge: RemoteProviderConfigBridge(), store: store)

        model.apiKey = "replacement-api-key"
        model.dataFlowConfirmed = true
        await model.testConnection()
        model.modelID = "gpt-4.1-mini-updated"

        XCTAssertFalse(model.canEnable)
        await model.testConnection()

        XCTAssertEqual(
            model.outcome?.errorMessage,
            L10n.message("Previous API key draft could not be discarded before testing.")
        )
        XCTAssertEqual(store.storedKeys(), [reference: "replacement-api-key"])
        XCTAssertFalse(model.canEnable)
    }

    @MainActor
    func testRemoveUnusedCredentialReportsDeleteFailureAndKeepsRetryState() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .always)
        let model = makeRemoteProviderConfigModel(
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
        XCTAssertEqual(model.outcome?.errorMessage, L10n.message("Unused API key could not be removed."))
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "new-api-key"])
    }

    @MainActor
    func testEnableFailureReportsExistingCredentialRestoreFailure() async {
        let store = RemoteProviderTestCredentialStore(discardFailure: .always)
        let reference = store.seedCredential(apiKey: "saved-api-key")
        let model = makeRemoteProviderConfigModel(
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
            L10n.message("Remote AI settings could not be saved, and the API key draft could not be restored.")
        )
        XCTAssertEqual(store.storedKeys(), [reference: "replacement-api-key"])
        XCTAssertTrue(model.canEnable)
    }

    @MainActor
    func testDisableWithKeyRemovalReportsKeychainFailure() async {
        let store = RemoteProviderTestCredentialStore(removeFailure: .always)
        let model = makeRemoteProviderConfigModel(
            bridge: RemoteProviderConfigBridge(initial: .remoteProviderConfigEnabled()),
            store: store
        )

        await model.load()
        let didDisable = await model.disableRemoteAI(removeStoredCredential: true)

        XCTAssertFalse(didDisable)
        XCTAssertEqual(model.snapshot?.remoteProviderEnabled, false)
        XCTAssertEqual(
            model.outcome?.errorMessage,
            L10n.message("Remote AI was disabled, but the stored API key could not be removed.")
        )
    }
}
