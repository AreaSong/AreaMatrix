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
    private var recorded = Requests()

    init(
        initial: RemoteProviderConfigState = .remoteProviderConfigDisabled(),
        testMode: TestMode = .success,
        enableFails: Bool = false
    ) {
        self.initial = initial
        self.testMode = testMode
        self.enableFails = enableFails
    }

    func loadRemoteProviderConfig(repoPath _: String) async throws -> RemoteProviderConfigState {
        recorded.loadCount += 1
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

actor RemoteProviderConfigErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "Remote provider save failed",
            severity: .medium,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "remote-provider-config remote provider"
        )
    }
}
