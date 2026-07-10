@testable import AreaMatrix
import XCTest

final class RemoteProviderConfigModelTests: XCTestCase {
    @MainActor
    func testEnableUsesKeychainReferenceAndVerifiedToken() async {
        let bridge = RemoteProviderConfigBridge()
        let store = RemoteProviderTestCredentialStore()
        let model = makeRemoteProviderConfigModel(bridge: bridge, store: store)

        await model.load()
        model.apiKey = "  dummy-api-key  "
        model.selectedScopes = [.autoSummaries, .autoTags]
        model.dataFlowConfirmed = true
        await model.testConnection()
        let didEnable = await model.enableRemoteAI()

        XCTAssertTrue(didEnable)
        await bridge.assertLoadCount(1)
        await bridge.assertTestRequest(keyReference: "keychain:openAi-managed", modelID: "gpt-4.1-mini")
        await bridge.assertEnableRequest(
            keyReference: "keychain:openAi-managed",
            verificationToken: "verified-remoteProviderConfig",
            featureScope: [.autoSummaries, .autoTags],
            dataFlowConfirmed: true
        )
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "dummy-api-key"])
        XCTAssertEqual(model.apiKey, "")
        XCTAssertEqual(model.snapshot?.remoteProviderEnabled, true)
        XCTAssertTrue(model.cancelEditing())
        XCTAssertEqual(store.removedReferences(), [])
        XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "dummy-api-key"])
    }

    @MainActor
    func testRequiresRetestAfterDraftChanges() async {
        await assertRemoteProviderConfigRetestAfterChange { $0.modelID = "claude-3-haiku" }
        await assertRemoteProviderConfigRetestAfterChange { $0.apiKey = "second-api-key" }
    }
}
