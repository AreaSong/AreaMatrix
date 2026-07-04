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
        let requests = await bridge.requests()

        XCTAssertTrue(didEnable)
        XCTAssertEqual(requests.loadCount, 1)
        XCTAssertEqual(requests.test?.keyReference, "keychain:openAi-managed")
        XCTAssertEqual(requests.test?.modelID, "gpt-4.1-mini")
        XCTAssertEqual(requests.enable?.keyReference, "keychain:openAi-managed")
        XCTAssertEqual(requests.enable?.verificationToken, "verified-remoteProviderConfig")
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
        await assertRemoteProviderConfigRetestAfterChange { $0.modelID = "claude-3-haiku" }
        await assertRemoteProviderConfigRetestAfterChange { $0.apiKey = "second-api-key" }
    }
}
