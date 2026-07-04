@testable import AreaMatrix
import XCTest

@MainActor
func assertRemoteProviderConfigEnabledPageIntegration(
    remoteModel: RemoteProviderConfigModel,
    privacyModel: RemotePrivacyGateModel,
    providerRequests: RemoteProviderConfigBridge.Requests,
    privacyRequests: RemotePrivacyRulesBridge.Requests,
    store: RemoteProviderTestCredentialStore,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let expectedScopes: [AISettingsFeatureKind] = [.classificationSuggestions, .autoSummaries]
    let expectedCoreScopes = expectedScopes.map(AiFeatureKind.init(snapshotFeature:))
    XCTAssertEqual(providerRequests.loadCount, 1, file: file, line: line)
    XCTAssertEqual(providerRequests.test?.keyReference, "keychain:openAi-managed", file: file, line: line)
    XCTAssertEqual(providerRequests.enable?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(providerRequests.enable?.dataFlowConfirmed, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.providerConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.providerVerified, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.remoteProviderEnabled, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.credentialConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(privacyModel.snapshot?.privacyGateEnabled, true, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.first?.privacyGateEnabled, true, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.first?.providerScope.remoteProviderEnabled, true, file: file, line: line)
    XCTAssertEqual(
        privacyRequests.updates.first?.providerScope.featureScope,
        expectedCoreScopes,
        file: file,
        line: line
    )
    XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "integration-api-key"], file: file, line: line)
}

@MainActor
func assertRemoteProviderConfigDisabledPageIntegration(
    remoteModel: RemoteProviderConfigModel,
    privacyModel: RemotePrivacyGateModel,
    providerRequests: RemoteProviderConfigBridge.Requests,
    privacyRequests: RemotePrivacyRulesBridge.Requests,
    store: RemoteProviderTestCredentialStore,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let expectedScopes: [AISettingsFeatureKind] = [.classificationSuggestions, .autoSummaries]
    XCTAssertEqual(providerRequests.disable?.removeStoredCredential, false, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.remoteProviderEnabled, false, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.credentialConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(privacyModel.snapshot?.privacyGateEnabled, false, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.last?.privacyGateEnabled, false, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.last?.providerScope.remoteProviderEnabled, false, file: file, line: line)
    XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "integration-api-key"], file: file, line: line)
    XCTAssertEqual(store.removedReferences(), [], file: file, line: line)
}

@MainActor
// swiftlint:disable:next function_parameter_count
func assertAIPrivacyRemoteProviderStatus(
    _ snapshot: RemoteProviderConfigState,
    status: String,
    verified: String,
    enabled: String,
    scope: String,
    allowsGate: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let model = AIPrivacyRemoteProviderStateModel(
        repoPath: "/tmp/aiPrivacyRules",
        providerReader: RemoteProviderConfigBridge(initial: snapshot),
        errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
    )

    await model.load()

    XCTAssertEqual(model.providerStatusText, status, file: file, line: line)
    XCTAssertEqual(model.verifiedStatusText, verified, file: file, line: line)
    XCTAssertEqual(model.enabledStatusText, enabled, file: file, line: line)
    XCTAssertEqual(model.featureScopeText, scope, file: file, line: line)
    XCTAssertEqual(model.allowsPrivacyGateEnable, allowsGate, file: file, line: line)
}
