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
        let requests = await bridge.requests()

        XCTAssertTrue(didDisableGate)
        XCTAssertEqual(model.snapshot?.privacyGateEnabled, false)
        XCTAssertEqual(requests.updates.first?.privacyGateEnabled, false)
        XCTAssertEqual(requests.updates.first?.providerScope.providerConfigured, true)
        XCTAssertEqual(requests.updates.first?.providerScope.remoteProviderEnabled, false)
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
            "Remote provider was configured, but privacy gate could not be enabled."
        )
        XCTAssertEqual(model.failure?.detail, "Remote provider save failed")
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
        let providerRequestsAfterEnable = await providerBridge.requests()
        let privacyRequestsAfterEnable = await privacyBridge.requests()

        XCTAssertTrue(didEnable)
        XCTAssertTrue(didEnableGate)
        assertRemoteProviderConfigEnabledPageIntegration(
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
        assertRemoteProviderConfigDisabledPageIntegration(
            remoteModel: remoteModel,
            privacyModel: privacyModel,
            providerRequests: providerRequestsAfterDisable,
            privacyRequests: privacyRequestsAfterDisable,
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
            "Remote provider was configured, but privacy gate could not be enabled."
        )
    }
}
