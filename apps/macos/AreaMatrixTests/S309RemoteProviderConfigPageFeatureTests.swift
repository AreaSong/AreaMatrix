@testable import AreaMatrix
import XCTest

final class S309RemoteProviderConfigPageFeatureTests: XCTestCase {
    @MainActor
    func testS309LoadsC303ProviderStatusForPrivacyRulesGate() async {
        let bridge = RemoteProviderConfigBridge(initial: .s309RemoteProviderConfigured())
        let model = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/s309",
            providerReader: bridge,
            errorMapper: S309RemoteProviderErrorMapper()
        )

        await model.load()
        let requests = await bridge.requests()

        XCTAssertEqual(requests.loadCount, 1)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.providerStatusText, "Configured by S3-03")
        XCTAssertEqual(model.verifiedStatusText, "Connection tested")
        XCTAssertEqual(model.enabledStatusText, "Remote provider enabled")
        XCTAssertEqual(model.featureScopeText, "Auto summaries, Semantic search")
        XCTAssertTrue(model.allowsPrivacyGateEnable)
    }

    @MainActor
    func testS309ProviderStatusExplainsMissingVerificationAndDisabledProvider() async {
        var unverified = RemoteProviderConfigState.s309RemoteProviderConfigured()
        unverified.providerVerified = false
        await assertProviderStatus(
            unverified,
            status: "Remote provider needs connection test.",
            verified: "Connection test required",
            enabled: "Remote provider enabled",
            scope: "Auto summaries, Semantic search",
            allowsGate: false
        )

        var disabled = RemoteProviderConfigState.s309RemoteProviderConfigured()
        disabled.remoteProviderEnabled = false
        await assertProviderStatus(
            disabled,
            status: "Remote provider is disabled in AI settings.",
            verified: "Connection tested",
            enabled: "Remote provider disabled",
            scope: "Auto summaries, Semantic search",
            allowsGate: false
        )
    }

    @MainActor
    func testS309ProviderLoadFailureMapsCoreErrorWithoutMockingReadyState() async {
        let bridge = S309FailingRemoteProviderReader(error: CoreError.PermissionDenied(path: "remote provider"))
        let model = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/s309",
            providerReader: bridge,
            errorMapper: S309RemoteProviderErrorMapper()
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
    func testS309BlocksPrivacyGateWithoutTouchingC303ProviderConfig() async {
        let updater = S309RemoteProviderAISettingsUpdater()
        let model = AISettingsModel(
            repoPath: "/tmp/s309",
            loader: S309RemoteProviderAISettingsLoader(snapshot: .s309RemoteReady(repoPath: "/tmp/s309")),
            updater: updater,
            errorMapper: S309RemoteProviderErrorMapper()
        )
        let providerBridge = RemoteProviderConfigBridge(initial: .s309RemoteProviderConfigured())
        let providerModel = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/s309",
            providerReader: providerBridge,
            errorMapper: S309RemoteProviderErrorMapper()
        )

        await model.load()
        await providerModel.load()
        let result = await model.blockRemoteAIWithPrivacyGate()
        let settingsRequests = await updater.requests()
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
    private func assertProviderStatus(
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
            repoPath: "/tmp/s309",
            providerReader: RemoteProviderConfigBridge(initial: snapshot),
            errorMapper: S309RemoteProviderErrorMapper()
        )

        await model.load()

        XCTAssertEqual(model.providerStatusText, status, file: file, line: line)
        XCTAssertEqual(model.verifiedStatusText, verified, file: file, line: line)
        XCTAssertEqual(model.enabledStatusText, enabled, file: file, line: line)
        XCTAssertEqual(model.featureScopeText, scope, file: file, line: line)
        XCTAssertEqual(model.allowsPrivacyGateEnable, allowsGate, file: file, line: line)
    }
}

private actor S309FailingRemoteProviderReader: CoreRemoteProviderConfiguring {
    let error: CoreError

    init(error: CoreError) {
        self.error = error
    }

    func loadRemoteProviderConfig(repoPath _: String) async throws -> RemoteProviderConfigState {
        throw error
    }

    func testRemoteProvider(
        repoPath _: String,
        request _: RemoteProviderTestRequestState
    ) async throws -> RemoteProviderTestResultState {
        throw error
    }

    func enableRemoteProvider(
        repoPath _: String,
        request _: RemoteProviderEnableRequestState
    ) async throws -> RemoteProviderConfigState {
        throw error
    }

    func disableRemoteProvider(
        repoPath _: String,
        request _: RemoteProviderDisableRequestState
    ) async throws -> RemoteProviderConfigState {
        throw error
    }
}

private actor S309RemoteProviderAISettingsLoader: CoreAISettingsLoading {
    let snapshot: AISettingsSnapshot

    init(snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }

    func loadAISettings(repoPath _: String) async throws -> AISettingsSnapshot {
        snapshot
    }
}

private actor S309RemoteProviderAISettingsUpdater: CoreAISettingsUpdating {
    private var recorded: [AISettingsConfigSnapshot] = []

    func updateAISettings(
        repoPath _: String,
        newConfig: AISettingsConfigSnapshot
    ) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recorded.append(normalized)
        return AISettingsSnapshot.s309Snapshot(config: normalized)
    }

    func requests() -> [AISettingsConfigSnapshot] {
        recorded
    }
}

private actor S309RemoteProviderErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "Remote provider unavailable",
            severity: .medium,
            suggestedAction: "Configure remote AI",
            recoverability: .userActionRequired,
            rawContext: "S3-09 C3-03"
        )
    }
}

private extension RemoteProviderConfigState {
    static func s309RemoteProviderConfigured() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: .openAi,
            modelID: "gpt-4.1-mini",
            endpointURL: nil,
            credentialConfigured: true,
            featureScope: [.autoSummaries, .semanticSearch],
            updatedAt: 309,
            disabledReason: nil
        )
    }
}

private extension AISettingsSnapshot {
    static func s309RemoteReady(repoPath: String) -> AISettingsSnapshot {
        s309Snapshot(config: AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: true,
            providerPreference: .remoteFirst,
            localAIEnabled: true,
            remoteAIAllowed: true,
            privacyGateEnabled: true,
            privacyPolicyRef: "Default gate policy",
            featureToggles: [
                AISettingsFeatureConfigSnapshot(feature: .autoSummaries, enabled: true, allowRemote: true),
                AISettingsFeatureConfigSnapshot(feature: .semanticSearch, enabled: true, allowRemote: true)
            ]
        ))
    }

    static func s309Snapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 309
        )
    }
}
