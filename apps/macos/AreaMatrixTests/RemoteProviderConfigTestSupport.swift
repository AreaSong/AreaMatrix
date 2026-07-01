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

actor RemoteProviderConfigBridge: CoreRemoteProviderConfiguring {
    enum TestMode {
        case success, rejected, coreFailure
    }

    struct Requests: Equatable {
        var loadCount = 0
        var test: RemoteProviderTestRequestState?
        var enable: RemoteProviderEnableRequestState?
        var disable: RemoteProviderDisableRequestState?
    }

    private var initial: RemoteProviderConfigState
    private let testMode: TestMode
    private let enableFails: Bool
    private let loadError: CoreError?
    private var recorded = Requests()

    init(
        initial: RemoteProviderConfigState = .remoteProviderConfigDisabled(),
        testMode: TestMode = .success,
        enableFails: Bool = false,
        loadError: CoreError? = nil
    ) {
        self.initial = initial
        self.testMode = testMode
        self.enableFails = enableFails
        self.loadError = loadError
    }

    func loadRemoteProviderConfig(repoPath _: String) async throws -> RemoteProviderConfigState {
        recorded.loadCount += 1
        if let loadError {
            throw loadError
        }
        return initial
    }

    func testRemoteProvider(repoPath _: String,
                            request: RemoteProviderTestRequestState) async throws -> RemoteProviderTestResultState {
        recorded.test = request
        switch testMode {
        case .coreFailure:
            throw CoreError.PermissionDenied(path: "remote provider credential")
        case .rejected:
            return RemoteProviderTestResultState(
                provider: request.provider,
                modelID: request.modelID,
                endpointURL: request.endpointURL,
                status: .providerRejected,
                providerVerified: false,
                verificationToken: nil,
                sanitizedMessage: "The API key was rejected by the provider."
            )
        case .success:
            break
        }

        return RemoteProviderTestResultState(
            provider: request.provider,
            modelID: request.modelID,
            endpointURL: request.endpointURL,
            status: .succeeded,
            providerVerified: true,
            verificationToken: "verified-remoteProviderConfig",
            sanitizedMessage: "Connection verified"
        )
    }

    func enableRemoteProvider(repoPath _: String,
                              request: RemoteProviderEnableRequestState) async throws -> RemoteProviderConfigState {
        recorded.enable = request
        if enableFails {
            throw CoreError.Internal(message: "remote provider save failed")
        }
        let snapshot = RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: request.provider,
            modelID: request.modelID,
            endpointURL: request.endpointURL,
            credentialConfigured: true,
            featureScope: request.featureScope,
            updatedAt: 303,
            disabledReason: nil
        )
        initial = snapshot
        return snapshot
    }

    func disableRemoteProvider(repoPath _: String,
                               request: RemoteProviderDisableRequestState) async throws -> RemoteProviderConfigState {
        recorded.disable = request
        let snapshot = RemoteProviderConfigState(
            providerConfigured: !request.removeStoredCredential,
            providerVerified: !request.removeStoredCredential,
            remoteProviderEnabled: false,
            provider: request.removeStoredCredential ? nil : initial.provider,
            modelID: request.removeStoredCredential ? nil : initial.modelID,
            endpointURL: request.removeStoredCredential ? nil : initial.endpointURL,
            credentialConfigured: !request.removeStoredCredential,
            featureScope: request.removeStoredCredential ? [] : initial.featureScope,
            updatedAt: 304,
            disabledReason: "Remote AI disabled"
        )
        initial = snapshot
        return snapshot
    }

    func requests() -> Requests {
        recorded
    }
}

extension RemoteProviderConfigState {
    static func remoteProviderConfigDisabled() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: false,
            providerVerified: false,
            remoteProviderEnabled: false,
            provider: nil,
            modelID: nil,
            endpointURL: nil,
            credentialConfigured: false,
            featureScope: [],
            updatedAt: nil,
            disabledReason: "Remote AI is off"
        )
    }

    static func remoteProviderConfigEnabled() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: .openAi,
            modelID: "gpt-4.1-mini",
            endpointURL: nil,
            credentialConfigured: true,
            featureScope: [.autoSummaries],
            updatedAt: 302,
            disabledReason: nil
        )
    }
}

func remoteProviderConfigErrorMapper() -> StaticCoreErrorMapper {
    StaticCoreErrorMapper(mapping: CoreErrorMappingSnapshot(
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
    let requests = await bridge.requests()
    XCTAssertFalse(didEnable, file: file, line: line)
    XCTAssertNil(requests.enable, file: file, line: line)
}

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
    let requests = await bridge.requests()

    XCTAssertTrue(didDisable, file: file, line: line)
    XCTAssertEqual(requests.disable?.removeStoredCredential, removeStoredCredential, file: file, line: line)
    XCTAssertEqual(store.removedReferences(), removed, file: file, line: line)
    XCTAssertEqual(model.snapshot?.remoteProviderEnabled, false, file: file, line: line)
    XCTAssertEqual(model.snapshot?.credentialConfigured, credential, file: file, line: line)
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

extension CoreErrorMappingSnapshot {
    static func remoteProviderConfigAIPrivacyRemoteProviderUnavailable() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "Remote provider unavailable",
            severity: .medium,
            suggestedAction: "Configure remote AI",
            recoverability: .userActionRequired,
            rawContext: "ai-privacy-rules remote-provider-config-core"
        )
    }
}

extension RemoteProviderConfigState {
    static func remoteProviderConfigAIPrivacyRemoteProviderConfigured() -> RemoteProviderConfigState {
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

extension AISettingsSnapshot {
    static func remoteProviderConfigAIPrivacyRemoteReady(repoPath: String) -> AISettingsSnapshot {
        remoteProviderConfigAIPrivacySnapshot(config: AISettingsConfigSnapshot(
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

    static func remoteProviderConfigAIPrivacySnapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 309
        )
    }
}
