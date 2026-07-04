@testable import AreaMatrix

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

    func testRemoteProvider(
        repoPath _: String,
        request: RemoteProviderTestRequestState
    ) async throws -> RemoteProviderTestResultState {
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

    func enableRemoteProvider(
        repoPath _: String,
        request: RemoteProviderEnableRequestState
    ) async throws -> RemoteProviderConfigState {
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

    func disableRemoteProvider(
        repoPath _: String,
        request: RemoteProviderDisableRequestState
    ) async throws -> RemoteProviderConfigState {
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
