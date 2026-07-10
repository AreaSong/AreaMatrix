@testable import AreaMatrix
import XCTest

actor RemoteProviderConfigBridge: CoreRemoteProviderConfiguring {
    enum TestMode {
        case success, rejected, coreFailure
    }

    private struct Requests: Equatable {
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

    func assertLoadCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded.loadCount, expectedCount, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recorded, Requests(), file: file, line: line)
    }

    func assertNoEnableRequest(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(recorded.enable, file: file, line: line)
    }

    func assertNoDisableRequest(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(recorded.disable, file: file, line: line)
    }

    func assertTestRequest(
        keyReference expectedKeyReference: String? = nil,
        modelID expectedModelID: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let expectedKeyReference {
            XCTAssertEqual(recorded.test?.keyReference, expectedKeyReference, file: file, line: line)
        }
        if let expectedModelID {
            XCTAssertEqual(recorded.test?.modelID, expectedModelID, file: file, line: line)
        }
    }

    func assertEnableRequest(
        keyReference expectedKeyReference: String? = nil,
        verificationToken expectedVerificationToken: String? = nil,
        featureScope expectedFeatureScope: [AISettingsFeatureKind]? = nil,
        dataFlowConfirmed expectedDataFlowConfirmed: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let expectedKeyReference {
            XCTAssertEqual(recorded.enable?.keyReference, expectedKeyReference, file: file, line: line)
        }
        if let expectedVerificationToken {
            XCTAssertEqual(recorded.enable?.verificationToken, expectedVerificationToken, file: file, line: line)
        }
        if let expectedFeatureScope {
            XCTAssertEqual(recorded.enable?.featureScope, expectedFeatureScope, file: file, line: line)
        }
        if let expectedDataFlowConfirmed {
            XCTAssertEqual(recorded.enable?.dataFlowConfirmed, expectedDataFlowConfirmed, file: file, line: line)
        }
    }

    func assertDisableRequest(
        removeStoredCredential expectedRemoveStoredCredential: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let expectedRemoveStoredCredential {
            XCTAssertEqual(
                recorded.disable?.removeStoredCredential,
                expectedRemoveStoredCredential,
                file: file,
                line: line
            )
        } else {
            XCTAssertNotNil(recorded.disable, file: file, line: line)
        }
    }
}
