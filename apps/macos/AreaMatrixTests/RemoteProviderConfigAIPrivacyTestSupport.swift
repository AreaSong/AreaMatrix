@testable import AreaMatrix
import AreaMatrixFeatureAI
import XCTest

struct AIPrivacyRemoteProviderStatusExpectation: Equatable {
    let providerStatus: String
    let verifiedStatus: String
    let enabledStatus: String
    let featureScope: String
    let allowsPrivacyGateEnable: Bool

    static let configured = AIPrivacyRemoteProviderStatusExpectation(
        providerStatus: "Configured",
        verifiedStatus: "Connection tested",
        enabledStatus: "Remote provider enabled",
        featureScope: "Auto summaries, Semantic search",
        allowsPrivacyGateEnable: true
    )

    static let needsConnectionTest = AIPrivacyRemoteProviderStatusExpectation(
        providerStatus: "Remote provider needs connection test.",
        verifiedStatus: "Connection test required",
        enabledStatus: "Remote provider enabled",
        featureScope: "Auto summaries, Semantic search",
        allowsPrivacyGateEnable: false
    )

    static let disabled = AIPrivacyRemoteProviderStatusExpectation(
        providerStatus: "Remote provider is disabled in AI settings.",
        verifiedStatus: "Connection tested",
        enabledStatus: "Remote provider disabled",
        featureScope: "Auto summaries, Semantic search",
        allowsPrivacyGateEnable: false
    )

    static let unavailable = AIPrivacyRemoteProviderStatusExpectation(
        providerStatus: "Remote provider state unavailable",
        verifiedStatus: "Loading",
        enabledStatus: "Loading",
        featureScope: "Loading",
        allowsPrivacyGateEnable: false
    )
}

@MainActor
func assertRemoteProviderConfigEnabledPageIntegration(
    remoteModel: RemoteProviderConfigModel,
    privacyModel: RemotePrivacyGateModel,
    providerBridge: RemoteProviderConfigBridge,
    privacyBridge: RemotePrivacyRulesBridge,
    store: RemoteProviderTestCredentialStore,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let expectedScopes: [AISettingsFeatureKind] = [.classificationSuggestions, .autoSummaries]
    let expectedCoreScopes = expectedScopes
    await providerBridge.assertLoadCount(1, file: file, line: line)
    await providerBridge.assertTestRequest(keyReference: "keychain:openAi-managed", file: file, line: line)
    await providerBridge.assertEnableRequest(
        featureScope: expectedScopes,
        dataFlowConfirmed: true,
        file: file,
        line: line
    )
    XCTAssertEqual(remoteModel.snapshot?.providerConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.providerVerified, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.remoteProviderEnabled, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.credentialConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(privacyModel.snapshot?.privacyGateEnabled, true, file: file, line: line)
    await privacyBridge.assertUpdate(at: 0, privacyGateEnabled: true, file: file, line: line)
    await privacyBridge.assertProviderScope(
        at: 0,
        remoteProviderEnabled: true,
        featureScope: expectedCoreScopes,
        file: file,
        line: line
    )
    XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "integration-api-key"], file: file, line: line)
}

@MainActor
func assertRemoteProviderConfigDisabledPageIntegration(
    remoteModel: RemoteProviderConfigModel,
    privacyModel: RemotePrivacyGateModel,
    providerBridge: RemoteProviderConfigBridge,
    privacyBridge: RemotePrivacyRulesBridge,
    store: RemoteProviderTestCredentialStore,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let expectedScopes: [AISettingsFeatureKind] = [.classificationSuggestions, .autoSummaries]
    await providerBridge.assertDisableRequest(removeStoredCredential: false, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.remoteProviderEnabled, false, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.credentialConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(privacyModel.snapshot?.privacyGateEnabled, false, file: file, line: line)
    await privacyBridge.assertUpdate(at: 1, privacyGateEnabled: false, file: file, line: line)
    await privacyBridge.assertProviderScope(at: 1, remoteProviderEnabled: false, file: file, line: line)
    XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "integration-api-key"], file: file, line: line)
    XCTAssertEqual(store.removedReferences(), [], file: file, line: line)
}

@MainActor
func assertAIPrivacyRemoteProviderStatus(
    _ snapshot: RemoteProviderConfigState,
    _ expected: AIPrivacyRemoteProviderStatusExpectation,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let model = AIPrivacyRemoteProviderStateModel(
        repoPath: "/tmp/aiPrivacyRules",
        providerReader: RemoteProviderConfigBridge(initial: snapshot),
        errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
    )

    await model.load()

    assertAIPrivacyRemoteProviderStatus(model, expected, file: file, line: line)
}

@MainActor
func assertAIPrivacyRemoteProviderStatus(
    _ model: AIPrivacyRemoteProviderStateModel,
    _ expected: AIPrivacyRemoteProviderStatusExpectation,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(model.providerStatusText, expected.providerStatus, file: file, line: line)
    XCTAssertEqual(model.verifiedStatusText, expected.verifiedStatus, file: file, line: line)
    XCTAssertEqual(model.enabledStatusText, expected.enabledStatus, file: file, line: line)
    XCTAssertEqual(model.featureScopeText, expected.featureScope, file: file, line: line)
    XCTAssertEqual(model.allowsPrivacyGateEnable, expected.allowsPrivacyGateEnable, file: file, line: line)
}
