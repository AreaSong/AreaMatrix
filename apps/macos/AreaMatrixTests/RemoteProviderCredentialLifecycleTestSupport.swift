@testable import AreaMatrix
import XCTest

@MainActor
func assertRemoteProviderConfigFailedTestRestoresSavedCredential(
    testMode: RemoteProviderConfigBridge.TestMode,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let store = RemoteProviderTestCredentialStore()
    let savedReference = store.seedCredential(apiKey: "saved-api-key")
    let model = makeRemoteProviderConfigModel(
        bridge: RemoteProviderConfigBridge(testMode: testMode),
        store: store
    )

    model.apiKey = "replacement-api-key"
    await model.testConnection()

    XCTAssertEqual(store.storedKeys(), [savedReference: "saved-api-key"], file: file, line: line)
    XCTAssertEqual(store.removedReferences(), [], file: file, line: line)
    XCTAssertFalse(model.canEnable, file: file, line: line)
}

@MainActor
func assertRemoteProviderConfigDisable(
    removeStoredCredential: Bool,
    removed: [String],
    credential: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let bridge = RemoteProviderConfigBridge(initial: .remoteProviderConfigEnabled())
    let store = RemoteProviderTestCredentialStore()
    let model = makeRemoteProviderConfigModel(bridge: bridge, store: store)

    await model.load()
    let didDisable = await model.disableRemoteAI(removeStoredCredential: removeStoredCredential)

    XCTAssertTrue(didDisable, file: file, line: line)
    await bridge.assertDisableRequest(removeStoredCredential: removeStoredCredential, file: file, line: line)
    XCTAssertEqual(store.removedReferences(), removed, file: file, line: line)
    XCTAssertEqual(model.snapshot?.remoteProviderEnabled, false, file: file, line: line)
    XCTAssertEqual(model.snapshot?.credentialConfigured, credential, file: file, line: line)
}
