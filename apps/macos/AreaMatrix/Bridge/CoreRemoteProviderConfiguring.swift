import Foundation

protocol CoreRemoteProviderConfiguring: Sendable {
    func loadRemoteProviderConfig(repoPath: String) async throws -> RemoteProviderConfigState
    func testRemoteProvider(
        repoPath: String,
        request: RemoteProviderTestRequestState
    ) async throws -> RemoteProviderTestResultState
    func enableRemoteProvider(
        repoPath: String,
        request: RemoteProviderEnableRequestState
    ) async throws -> RemoteProviderConfigState
    func disableRemoteProvider(
        repoPath: String,
        request: RemoteProviderDisableRequestState
    ) async throws -> RemoteProviderConfigState
}

extension CoreBridge: CoreRemoteProviderConfiguring {
    func loadRemoteProviderConfig(repoPath: String) async throws -> RemoteProviderConfigState {
        try await Task.detached(priority: .userInitiated) {
            try RemoteProviderConfigState(coreSnapshot: loadRemoteAiProviderConfig(repoPath: repoPath))
        }.value
    }

    func testRemoteProvider(
        repoPath: String,
        request: RemoteProviderTestRequestState
    ) async throws -> RemoteProviderTestResultState {
        try ensureRemoteProviderProbeRuntime()
        return try await Task.detached(priority: .userInitiated) {
            try RemoteProviderTestResultState(coreResult: testRemoteAiProvider(
                repoPath: repoPath,
                request: RemoteProviderTestRequest(snapshot: request)
            ))
        }.value
    }

    func enableRemoteProvider(
        repoPath: String,
        request: RemoteProviderEnableRequestState
    ) async throws -> RemoteProviderConfigState {
        try await Task.detached(priority: .userInitiated) {
            try RemoteProviderConfigState(coreSnapshot: enableRemoteAiProvider(
                repoPath: repoPath,
                request: RemoteProviderEnableRequest(snapshot: request)
            ))
        }.value
    }

    func disableRemoteProvider(
        repoPath: String,
        request: RemoteProviderDisableRequestState
    ) async throws -> RemoteProviderConfigState {
        try await Task.detached(priority: .userInitiated) {
            try RemoteProviderConfigState(coreSnapshot: disableRemoteAiProvider(
                repoPath: repoPath,
                request: RemoteProviderDisableRequest(snapshot: request)
            ))
        }.value
    }

    private func ensureRemoteProviderProbeRuntime() throws {
        _ = try RemoteProviderProbeRuntimeInstaller().ensureInstalled()
    }
}

extension RemoteProviderConfigState {
    init(coreSnapshot: RemoteProviderConfigSnapshot) {
        providerConfigured = coreSnapshot.providerConfigured
        providerVerified = coreSnapshot.providerVerified
        remoteProviderEnabled = coreSnapshot.remoteProviderEnabled
        provider = coreSnapshot.provider.map(RemoteProviderKindState.init(coreProvider:))
        modelID = coreSnapshot.modelId
        endpointURL = coreSnapshot.endpointUrl
        credentialConfigured = coreSnapshot.credentialConfigured
        featureScope = coreSnapshot.featureScope.map(AISettingsFeatureKind.init(coreFeature:))
        updatedAt = coreSnapshot.updatedAt
        disabledReason = coreSnapshot.disabledReason
    }
}

extension RemoteProviderTestResultState {
    init(coreResult: RemoteProviderTestResult) {
        provider = RemoteProviderKindState(coreProvider: coreResult.provider)
        modelID = coreResult.modelId
        endpointURL = coreResult.endpointUrl
        status = RemoteProviderTestStatusState(coreStatus: coreResult.status)
        providerVerified = coreResult.providerVerified
        verificationToken = coreResult.verificationToken
        sanitizedMessage = coreResult.sanitizedMessage
    }
}

extension RemoteProviderTestRequest {
    init(snapshot: RemoteProviderTestRequestState) {
        self.init(
            provider: RemoteAiProviderKind(snapshotProvider: snapshot.provider),
            modelId: snapshot.modelID,
            endpointUrl: snapshot.endpointURL,
            keyReference: snapshot.keyReference
        )
    }
}

extension RemoteProviderEnableRequest {
    init(snapshot: RemoteProviderEnableRequestState) {
        self.init(
            provider: RemoteAiProviderKind(snapshotProvider: snapshot.provider),
            modelId: snapshot.modelID,
            endpointUrl: snapshot.endpointURL,
            keyReference: snapshot.keyReference,
            featureScope: snapshot.featureScope.map(AiFeatureKind.init(snapshotFeature:)),
            verificationToken: snapshot.verificationToken,
            dataFlowConfirmed: snapshot.dataFlowConfirmed
        )
    }
}

extension RemoteProviderDisableRequest {
    init(snapshot: RemoteProviderDisableRequestState) {
        self.init(removeStoredCredential: snapshot.removeStoredCredential)
    }
}

private extension RemoteProviderKindState {
    init(coreProvider: RemoteAiProviderKind) {
        switch coreProvider {
        case .openAi: self = .openAi
        case .anthropic: self = .anthropic
        case .other: self = .other
        }
    }
}

private extension RemoteProviderTestStatusState {
    init(coreStatus: RemoteProviderTestStatus) {
        switch coreStatus {
        case .succeeded: self = .succeeded
        case .providerRejected: self = .providerRejected
        case .connectionFailed: self = .connectionFailed
        case .unsupportedProvider: self = .unsupportedProvider
        }
    }
}

private extension RemoteAiProviderKind {
    init(snapshotProvider: RemoteProviderKindState) {
        switch snapshotProvider {
        case .openAi: self = .openAi
        case .anthropic: self = .anthropic
        case .other: self = .other
        }
    }
}
