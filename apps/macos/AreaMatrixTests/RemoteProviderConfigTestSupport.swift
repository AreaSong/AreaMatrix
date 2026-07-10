@testable import AreaMatrix
import XCTest

extension RemoteProviderOutcome {
    var errorMessage: String? {
        switch self {
        case let .failed(error): error.message
        case .success: nil
        }
    }
}

func remoteProviderConfigErrorMapper() -> StaticCoreErrorMapper {
    StaticCoreErrorMapper(mapping: CoreErrorMappingSnapshot.testFixture(
        kind: .internal,
        userMessage: "Remote provider save failed",
        severity: .medium,
        suggestedAction: "Retry",
        recoverability: .retryable,
        rawContext: "remote-provider-config remote provider"
    ))
}

@MainActor
func makeRemoteProviderConfigModel(
    bridge: RemoteProviderConfigBridge,
    store: RemoteProviderTestCredentialStore
) -> RemoteProviderConfigModel {
    RemoteProviderConfigModel(
        repoPath: "/tmp/remoteProviderConfig",
        bridge: bridge,
        credentialStore: store,
        errorMapper: remoteProviderConfigErrorMapper()
    )
}

@MainActor
func assertRemoteProviderConfigRetestAfterChange(
    _ mutate: (RemoteProviderConfigModel) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let bridge = RemoteProviderConfigBridge()
    let store = RemoteProviderTestCredentialStore()
    let model = makeRemoteProviderConfigModel(bridge: bridge, store: store)

    model.apiKey = "dummy-api-key"
    model.dataFlowConfirmed = true
    await model.testConnection()
    XCTAssertTrue(model.canEnable, file: file, line: line)
    mutate(model)

    XCTAssertFalse(model.canEnable, file: file, line: line)
    XCTAssertEqual(store.removedReferences(), ["keychain:openAi-managed"], file: file, line: line)
    let didEnable = await model.enableRemoteAI()
    XCTAssertFalse(didEnable, file: file, line: line)
    await bridge.assertNoEnableRequest(file: file, line: line)
}
