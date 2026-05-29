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
            verificationToken: "verified-s303",
            sanitizedMessage: "Connection verified"
        )
    }

    func enableRemoteProvider(repoPath _: String,
                              request: RemoteProviderEnableRequestState) async throws -> RemoteProviderConfigState {
        recorded.enable = request
        if enableFails {
            throw CoreError.Internal(message: "remote provider save failed")
        }
        return RemoteProviderConfigState(
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
    }

    func disableRemoteProvider(repoPath _: String,
                               request: RemoteProviderDisableRequestState) async throws -> RemoteProviderConfigState {
        recorded.disable = request
        return RemoteProviderConfigState(
            providerConfigured: !request.removeStoredCredential,
            providerVerified: !request.removeStoredCredential,
            remoteProviderEnabled: false,
            provider: request.removeStoredCredential ? nil : initial.provider,
            modelID: request.removeStoredCredential ? nil : initial.modelID,
            endpointURL: request.removeStoredCredential ? nil : initial.endpointURL,
            credentialConfigured: !request.removeStoredCredential,
            featureScope: [],
            updatedAt: 304,
            disabledReason: "Remote AI disabled"
        )
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

@MainActor
final class RemoteProviderTestCredentialStore: RemoteProviderCredentialStoring {
    enum FailureMode {
        case never, oneShot, always

        mutating func shouldFail() -> Bool {
            switch self {
            case .never:
                return false
            case .oneShot:
                self = .never
                return true
            case .always:
                return true
            }
        }
    }

    private var keys: [String: String] = [:]
    private var removed: [String] = []
    private var rollbacks: [UUID: RemoteProviderConfigCredentialRollback] = [:]
    private var discardFailure: FailureMode
    private var removeFailure: FailureMode

    init(discardFailure: FailureMode = .never, removeFailure: FailureMode = .never) {
        self.discardFailure = discardFailure
        self.removeFailure = removeFailure
    }

    func storeCredential(
        provider: RemoteProviderKindState,
        endpointURL: String?,
        apiKey: String
    ) throws -> RemoteProviderCredentialDraft {
        let reference = storedCredentialReference(provider: provider, endpointURL: endpointURL)
        let draft = RemoteProviderCredentialDraft(
            reference: reference,
            replacesExistingCredential: keys[reference] != nil
        )
        rollbacks[draft.id] = keys[reference]
            .map { .existing(reference: reference, value: $0) } ?? .missing(reference: reference)
        keys[reference] = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft
    }

    func discardCredentialDraft(_ draft: RemoteProviderCredentialDraft) throws {
        if discardFailure.shouldFail() {
            throw RemoteProviderConfigCredentialStoreError.cleanupFailed
        }
        guard let rollback = rollbacks[draft.id] else { return }
        switch rollback {
        case let .existing(_, previous):
            keys[draft.reference] = previous
        case .missing:
            keys.removeValue(forKey: draft.reference)
            removed.append(draft.reference)
        }
        rollbacks.removeValue(forKey: draft.id)
    }

    func commitCredentialDraft(_ draft: RemoteProviderCredentialDraft) {
        rollbacks.removeValue(forKey: draft.id)
    }

    func removeCredential(reference: String) throws {
        if removeFailure.shouldFail() {
            throw RemoteProviderConfigCredentialStoreError.cleanupFailed
        }
        rollbacks = rollbacks.filter { $0.value.reference != reference }
        removed.append(reference)
        keys.removeValue(forKey: reference)
    }

    func storedCredentialReference(provider: RemoteProviderKindState, endpointURL: String?) -> String {
        let suffix = endpointURL?.isEmpty == false ? endpointURL ?? "managed" : "managed"
        return "keychain:\(provider.rawValue)-\(suffix)"
    }

    func storedKeys() -> [String: String] {
        keys
    }

    func removedReferences() -> [String] {
        removed
    }

    func seedCredential(provider: RemoteProviderKindState = .openAi, endpointURL: String? = nil,
                        apiKey: String) -> String {
        let reference = storedCredentialReference(provider: provider, endpointURL: endpointURL)
        keys[reference] = apiKey
        return reference
    }
}

private enum RemoteProviderConfigCredentialRollback {
    case missing(reference: String)
    case existing(reference: String, value: String)

    var reference: String {
        switch self {
        case let .missing(reference), let .existing(reference, _):
            reference
        }
    }
}

private enum RemoteProviderConfigCredentialStoreError: LocalizedError {
    case cleanupFailed

    var errorDescription: String? {
        "Keychain cleanup failed."
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
            rawContext: "S3-03 remote provider"
        )
    }
}
