@testable import AreaMatrix
import XCTest

final class RemoteProviderConfigAIPrivacyModelTests: XCTestCase {
    @MainActor
    func testRemoteProviderConfigAIPrivacyRulesCoreEnableTurnsOnPrivacyGateWithProviderScope() async {
        let bridge = RemotePrivacyRulesBridge(snapshot: .remoteProviderConfigPrivacyRules(privacyGateEnabled: false))
        let model = RemotePrivacyGateModel(
            repoPath: "/tmp/remoteProviderConfig",
            bridge: bridge,
            errorMapper: remoteProviderConfigErrorMapper()
        )

        let didEnable = await model.enablePrivacyGate(providerConfig: .remoteProviderConfigEnabled())

        XCTAssertTrue(didEnable)
        XCTAssertEqual(model.snapshot?.privacyGateEnabled, true)
        await bridge.assertLoadCount(1)
        await bridge.assertUpdateCount(1)
        await bridge.assertUpdate(at: 0, privacyGateEnabled: true)
        await bridge.assertProviderScope(at: 0, remoteProviderEnabled: true, featureScope: [.autoSummaries])
        await bridge.assertUpdateRule(at: 0, position: .first, name: "Block confidential")
        await bridge.assertUpdateFieldPolicy(
            at: 0,
            fieldIndex: 1,
            field: .extractedTextExcerpt,
            allowRemote: false
        )
    }

    @MainActor
    func testRemoteProviderConfigAIPrivacyRulesCoreDisableTurnsOffPrivacyGateWithoutClearingProviderConfig() async {
        let bridge = RemotePrivacyRulesBridge(snapshot: .remoteProviderConfigPrivacyRules(privacyGateEnabled: true))
        let model = RemotePrivacyGateModel(
            repoPath: "/tmp/remoteProviderConfig",
            bridge: bridge,
            errorMapper: remoteProviderConfigErrorMapper()
        )
        var disabledProvider = RemoteProviderConfigState.remoteProviderConfigEnabled()
        disabledProvider.remoteProviderEnabled = false

        let didDisableGate = await model.disablePrivacyGate(providerConfig: disabledProvider)

        XCTAssertTrue(didDisableGate)
        XCTAssertEqual(model.snapshot?.privacyGateEnabled, false)
        await bridge.assertUpdate(at: 0, privacyGateEnabled: false)
        await bridge.assertProviderScope(at: 0, providerConfigured: true, remoteProviderEnabled: false)
    }

    @MainActor
    func testRemoteProviderConfigAIPrivacyRulesCorePrivacyGateFailureKeepsRetryableAction() async {
        let bridge = RemotePrivacyRulesBridge(updateFails: true)
        let model = RemotePrivacyGateModel(
            repoPath: "/tmp/remoteProviderConfig",
            bridge: bridge,
            errorMapper: remoteProviderConfigErrorMapper()
        )

        let didEnable = await model.enablePrivacyGate(providerConfig: .remoteProviderConfigEnabled())

        XCTAssertFalse(didEnable)
        XCTAssertEqual(model.pendingAction, .enable)
        XCTAssertEqual(
            model.failure?.message,
            L10n.message("Remote provider was configured, but privacy gate could not be enabled.")
        )
        XCTAssertEqual(model.failure?.detail, L10n.string("error.unmapped.message"))
    }

    @MainActor
    func testRemoteProviderConfigPageIntegrationWiresEntryEnablePrivacyGateDisableAndExitRefresh() async {
        let providerBridge = RemoteProviderConfigBridge()
        let privacyBridge =
            RemotePrivacyRulesBridge(snapshot: .remoteProviderConfigPrivacyRules(privacyGateEnabled: false))
        let store = RemoteProviderTestCredentialStore()
        let remoteModel = makeRemoteProviderConfigModel(bridge: providerBridge, store: store)
        let privacyModel = RemotePrivacyGateModel(
            repoPath: "/tmp/remoteProviderConfig",
            bridge: privacyBridge,
            errorMapper: remoteProviderConfigErrorMapper()
        )

        await remoteModel.load()
        await privacyModel.load()
        remoteModel.apiKey = "integration-api-key"
        remoteModel.selectedScopes = [.classificationSuggestions, .autoSummaries]
        remoteModel.dataFlowConfirmed = true
        await remoteModel.testConnection()
        let didEnable = await remoteModel.enableRemoteAI()
        let didEnableGate = await privacyModel.enablePrivacyGate(providerConfig: remoteModel.snapshot)

        XCTAssertTrue(didEnable)
        XCTAssertTrue(didEnableGate)
        await assertRemoteProviderConfigEnabledPageIntegration(
            remoteModel: remoteModel,
            privacyModel: privacyModel,
            providerBridge: providerBridge,
            privacyBridge: privacyBridge,
            store: store
        )

        let didDisable = await remoteModel.disableRemoteAI(removeStoredCredential: false)
        let didDisableGate = await privacyModel.disablePrivacyGate(providerConfig: remoteModel.snapshot)

        XCTAssertTrue(didDisable)
        XCTAssertTrue(didDisableGate)
        await assertRemoteProviderConfigDisabledPageIntegration(
            remoteModel: remoteModel,
            privacyModel: privacyModel,
            providerBridge: providerBridge,
            privacyBridge: privacyBridge,
            store: store
        )
    }

    @MainActor
    func testRemoteProviderConfigKeepsProviderEnabledWhenPrivacyGateEnableFails() async {
        let providerBridge = RemoteProviderConfigBridge()
        let privacyBridge = RemotePrivacyRulesBridge(updateFails: true)
        let remoteModel = makeRemoteProviderConfigModel(
            bridge: providerBridge,
            store: RemoteProviderTestCredentialStore()
        )
        let privacyModel = RemotePrivacyGateModel(
            repoPath: "/tmp/remoteProviderConfig",
            bridge: privacyBridge,
            errorMapper: remoteProviderConfigErrorMapper()
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
            L10n.message("Remote provider was configured, but privacy gate could not be enabled.")
        )
    }
}
