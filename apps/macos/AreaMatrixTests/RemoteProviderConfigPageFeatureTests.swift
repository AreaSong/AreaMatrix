@testable import AreaMatrix
import XCTest

final class RemoteProviderConfigFeatureTests: XCTestCase {
    @MainActor
    func testAIPrivacyRulesLoadsRemoteProviderConfigCoreProviderStatusForPrivacyRulesGate() async {
        let bridge = RemoteProviderConfigBridge(initial: .remoteProviderConfigAIPrivacyRemoteProviderConfigured())
        let model = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/aiPrivacyRules",
            providerReader: bridge,
            errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
        )

        await model.load()

        await bridge.assertLoadCount(1)
        XCTAssertEqual(model.loadState, .loaded)
        assertAIPrivacyRemoteProviderStatus(model, .configured)
    }

    @MainActor
    func testAIPrivacyRulesProviderStatusExplainsMissingVerificationAndDisabledProvider() async {
        var unverified = RemoteProviderConfigState.remoteProviderConfigAIPrivacyRemoteProviderConfigured()
        unverified.providerVerified = false
        await assertAIPrivacyRemoteProviderStatus(
            unverified,
            .needsConnectionTest
        )

        var disabled = RemoteProviderConfigState.remoteProviderConfigAIPrivacyRemoteProviderConfigured()
        disabled.remoteProviderEnabled = false
        await assertAIPrivacyRemoteProviderStatus(
            disabled,
            .disabled
        )
    }

    @MainActor
    func testAIPrivacyRulesProviderLoadFailureMapsCoreErrorWithoutMockingReadyState() async {
        let bridge = RemoteProviderConfigBridge(loadError: CoreError.PermissionDenied(path: "remote provider"))
        let model = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/aiPrivacyRules",
            providerReader: bridge,
            errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
        )

        await model.load()

        XCTAssertEqual(
            model.loadState,
            .failed(AISettingsError(
                message: L10n.message("Remote provider state could not be loaded."),
                recovery: L10n.message(
                    "error.unmapped.action",
                    fallback: "Configure remote AI",
                    technicalDetail: "Configure remote AI"
                ),
                detail: L10n.string("error.unmapped.message")
            ))
        )
        XCTAssertNil(model.snapshot)
        assertAIPrivacyRemoteProviderStatus(model, .unavailable)
    }

    @MainActor
    func testAIPrivacyRulesBlocksPrivacyGateWithoutTouchingRemoteProviderConfigCoreProviderConfig() async {
        let updater = RecordingAISettingsUpdater()
        let model = AISettingsModel(
            repoPath: "/tmp/aiPrivacyRules",
            loader: StaticAISettingsLoader(
                snapshot: .remoteProviderConfigAIPrivacyRemoteReady(repoPath: "/tmp/aiPrivacyRules")
            ),
            updater: updater,
            errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
        )
        let providerBridge = RemoteProviderConfigBridge(
            initial: .remoteProviderConfigAIPrivacyRemoteProviderConfigured()
        )
        let providerModel = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/aiPrivacyRules",
            providerReader: providerBridge,
            errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
        )

        await model.load()
        await providerModel.load()
        let result = await model.blockRemoteAIWithPrivacyGate()

        XCTAssertEqual(result, .saved)
        await updater.assertRequestCount(1)
        await updater.assertRequestedConfigValue(at: 0, \.privacyGateEnabled, false)
        await updater.assertRequestedConfigValue(at: 0, \.remoteAIAllowed, true)
        await providerBridge.assertLoadCount(1)
        await providerBridge.assertNoDisableRequest()
        assertAIPrivacyRemoteProviderStatus(providerModel, .configured)
    }

    @MainActor
    func testAIPrivacyRulesAIPrivacyRulesCoreLoadsPrivacyRulesSnapshotFromCoreBridge() async {
        let bridge = RemotePrivacyRulesBridge(
            snapshot: .remoteProviderConfigAIPrivacyRules(privacyGateEnabled: true)
        )
        let model = AIPrivacyRulesModel(
            repoPath: "/tmp/aiPrivacyRules",
            rulesManager: bridge,
            evaluator: bridge,
            errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
        )

        await model.load()

        await bridge.assertLoadCount(1)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.rules.first?.pattern, "finance/private/")
        XCTAssertTrue(model.canEditRemoteFields)
    }

    @MainActor
    func testAIPrivacyRulesAIPrivacyRulesCoreUpdatesPrivacyGateAndFieldFiltersWithoutProviderDisable() async {
        let bridge = RemotePrivacyRulesBridge(
            snapshot: .remoteProviderConfigAIPrivacyRules(privacyGateEnabled: true)
        )
        let model = AIPrivacyRulesModel(
            repoPath: "/tmp/aiPrivacyRules",
            rulesManager: bridge,
            evaluator: bridge,
            errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
        )

        await model.load()
        await model.setPrivacyGate(false)
        await model.setField(.fileName, allowRemote: false)

        await bridge.assertUpdateCount(2)
        await bridge.assertUpdate(at: 0, privacyGateEnabled: false, confirmed: true)
        await bridge.assertProviderScope(at: 0, providerConfigured: true)
        await bridge.assertUpdateFieldPolicy(at: 1, field: .fileName, allowRemote: false)
    }

    @MainActor
    func testAIPrivacyRulesAIPrivacyRulesCoreEvaluatesTestRulesWithCurrentSnapshot() async {
        let bridge = RemotePrivacyRulesBridge(
            snapshot: .remoteProviderConfigAIPrivacyRules(privacyGateEnabled: true),
            evaluationReport: .remoteProviderConfigAIPrivacyFinanceFolderBlocked()
        )
        let model = AIPrivacyRulesModel(
            repoPath: "/tmp/aiPrivacyRules",
            rulesManager: bridge,
            evaluator: bridge,
            errorMapper: StaticCoreErrorMapper(mapping: .remoteProviderConfigAIPrivacyRemoteProviderUnavailable())
        )

        await model.load()
        await model.evaluate(repoRelativePath: "finance/private/q1.pdf")

        await bridge.assertEvaluationCount(4)
        await bridge.assertEvaluationFeatures(AISettingsFeatureKind.aiPrivacyRulesCases)
        await bridge.assertEvaluation(
            at: 0,
            route: .remote,
            repoRelativePath: "finance/private/q1.pdf",
            requestedFields: [.fileName, .repoRelativePath, .extension]
        )
        XCTAssertEqual(model.evaluation?.decision, .skipped)
        XCTAssertEqual(model.evaluation?.matchedRules.first?.ruleId, "rule-finance-folder")
    }
}
