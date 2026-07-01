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
        let requests = await bridge.requests()

        XCTAssertEqual(requests.loadCount, 1)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.providerStatusText, "Configured")
        XCTAssertEqual(model.verifiedStatusText, "Connection tested")
        XCTAssertEqual(model.enabledStatusText, "Remote provider enabled")
        XCTAssertEqual(model.featureScopeText, "Auto summaries, Semantic search")
        XCTAssertTrue(model.allowsPrivacyGateEnable)
    }

    @MainActor
    func testAIPrivacyRulesProviderStatusExplainsMissingVerificationAndDisabledProvider() async {
        var unverified = RemoteProviderConfigState.remoteProviderConfigAIPrivacyRemoteProviderConfigured()
        unverified.providerVerified = false
        await assertAIPrivacyRemoteProviderStatus(
            unverified,
            status: "Remote provider needs connection test.",
            verified: "Connection test required",
            enabled: "Remote provider enabled",
            scope: "Auto summaries, Semantic search",
            allowsGate: false
        )

        var disabled = RemoteProviderConfigState.remoteProviderConfigAIPrivacyRemoteProviderConfigured()
        disabled.remoteProviderEnabled = false
        await assertAIPrivacyRemoteProviderStatus(
            disabled,
            status: "Remote provider is disabled in AI settings.",
            verified: "Connection tested",
            enabled: "Remote provider disabled",
            scope: "Auto summaries, Semantic search",
            allowsGate: false
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
                message: "Remote provider state could not be loaded.",
                recovery: "Configure remote AI",
                detail: "Remote provider unavailable"
            ))
        )
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.providerStatusText, "Remote provider state unavailable")
        XCTAssertFalse(model.allowsPrivacyGateEnable)
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
        let settingsRequests = await updater.requestedConfigs()
        let providerRequests = await providerBridge.requests()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(settingsRequests.count, 1)
        XCTAssertEqual(settingsRequests[0].privacyGateEnabled, false)
        XCTAssertEqual(settingsRequests[0].remoteAIAllowed, true)
        XCTAssertEqual(providerRequests.loadCount, 1)
        XCTAssertNil(providerRequests.disable)
        XCTAssertTrue(providerModel.allowsPrivacyGateEnable)
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
        let requests = await bridge.requests()

        XCTAssertEqual(requests.loadCount, 1)
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
        let requests = await bridge.requests()

        XCTAssertEqual(requests.updates.count, 2)
        XCTAssertFalse(requests.updates[0].privacyGateEnabled)
        XCTAssertTrue(requests.updates[0].confirmed)
        XCTAssertEqual(requests.updates[0].providerScope.providerConfigured, true)
        XCTAssertFalse(requests.updates[1].remoteAllowedFields.first { $0.field == .fileName }?.allowRemote ?? true)
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
        let requests = await bridge.requests()

        XCTAssertEqual(requests.evaluations.count, 4)
        XCTAssertEqual(requests.evaluations.map(\.feature), AiFeatureKind.aiPrivacyRulesCases)
        XCTAssertEqual(requests.evaluations[0].route, .remote)
        XCTAssertEqual(requests.evaluations[0].context.repoRelativePath, "finance/private/q1.pdf")
        XCTAssertEqual(requests.evaluations[0].requestedFields, [.fileName, .repoRelativePath, .extension])
        XCTAssertEqual(model.evaluation?.decision, .skipped)
        XCTAssertEqual(model.evaluation?.matchedRules.first?.ruleId, "rule-finance-folder")
    }
}
