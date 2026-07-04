@testable import AreaMatrix
import Foundation

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
