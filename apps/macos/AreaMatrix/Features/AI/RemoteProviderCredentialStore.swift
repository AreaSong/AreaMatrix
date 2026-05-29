import Foundation
import Security

struct RemoteProviderCredentialDraft: Equatable {
    let id: UUID
    let reference: String
    let replacesExistingCredential: Bool

    init(id: UUID = UUID(), reference: String, replacesExistingCredential: Bool = false) {
        self.id = id
        self.reference = reference
        self.replacesExistingCredential = replacesExistingCredential
    }
}

protocol RemoteProviderCredentialStoring {
    @MainActor
    func storeCredential(
        provider: RemoteProviderKindState,
        endpointURL: String?,
        apiKey: String
    ) throws -> RemoteProviderCredentialDraft
    @MainActor
    func discardCredentialDraft(_ draft: RemoteProviderCredentialDraft) throws
    @MainActor
    func commitCredentialDraft(_ draft: RemoteProviderCredentialDraft)
    @MainActor
    func removeCredential(reference: String) throws
    @MainActor
    func storedCredentialReference(provider: RemoteProviderKindState, endpointURL: String?) -> String
}

final class RemoteProviderKeychainCredentialStore: RemoteProviderCredentialStoring {
    private var rollbackSnapshots: [UUID: RemoteProviderCredentialRollback] = [:]

    @MainActor
    func storeCredential(
        provider: RemoteProviderKindState,
        endpointURL: String?,
        apiKey: String
    ) throws -> RemoteProviderCredentialDraft {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw RemoteProviderCredentialStoreError.emptyKey }
        let account = account(provider: provider, endpointURL: endpointURL)
        let rollback = try rollbackSnapshot(account: account)
        try writeCredential(Data(key.utf8), account: account)

        let draft = RemoteProviderCredentialDraft(
            reference: "keychain:\(account)",
            replacesExistingCredential: rollback.replacesExistingCredential
        )
        rollbackSnapshots[draft.id] = RemoteProviderCredentialRollback(account: account, snapshot: rollback)
        return draft
    }

    @MainActor
    func discardCredentialDraft(_ draft: RemoteProviderCredentialDraft) throws {
        guard let rollback = rollbackSnapshots[draft.id] else { return }
        switch rollback.snapshot {
        case .missing:
            try deleteCredential(account: rollback.account)
        case let .existing(data):
            try writeCredential(data, account: rollback.account)
        }
        rollbackSnapshots.removeValue(forKey: draft.id)
    }

    @MainActor
    func commitCredentialDraft(_ draft: RemoteProviderCredentialDraft) {
        rollbackSnapshots.removeValue(forKey: draft.id)
    }

    @MainActor
    func removeCredential(reference: String) throws {
        guard let account = reference.removingKeychainPrefix else { return }
        try deleteCredential(account: account)
        rollbackSnapshots = rollbackSnapshots.filter { $0.value.account != account }
    }

    @MainActor
    func storedCredentialReference(provider: RemoteProviderKindState, endpointURL: String?) -> String {
        "keychain:\(account(provider: provider, endpointURL: endpointURL))"
    }

    private func rollbackSnapshot(account: String) throws -> RemoteProviderCredentialRollbackSnapshot {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess, let data = item as? Data else {
            throw RemoteProviderCredentialStoreError.keychainReadFailed(status)
        }
        return .existing(data)
    }

    private func writeCredential(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw RemoteProviderCredentialStoreError.keychainWriteFailed(updateStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = data
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw RemoteProviderCredentialStoreError.keychainWriteFailed(addStatus)
        }
    }

    private func deleteCredential(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RemoteProviderCredentialStoreError.keychainDeleteFailed(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "AreaMatrix.RemoteAI",
            kSecAttrAccount as String: account
        ]
    }

    private func account(provider: RemoteProviderKindState, endpointURL: String?) -> String {
        "remote-ai-\(provider.rawValue)-\(stableSuffix(endpointURL))"
    }

    private func stableSuffix(_ endpointURL: String?) -> String {
        guard let endpointURL, !endpointURL.isEmpty else { return "managed" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in endpointURL.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private struct RemoteProviderCredentialRollback {
    var account: String
    var snapshot: RemoteProviderCredentialRollbackSnapshot
}

private enum RemoteProviderCredentialRollbackSnapshot {
    case missing
    case existing(Data)

    var replacesExistingCredential: Bool {
        switch self {
        case .missing: false
        case .existing: true
        }
    }
}

enum RemoteProviderCredentialStoreError: LocalizedError {
    case emptyKey
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey: "API key is required."
        case let .keychainReadFailed(status): "Keychain read failed with status \(status)."
        case let .keychainWriteFailed(status): "Keychain write failed with status \(status)."
        case let .keychainDeleteFailed(status): "Keychain delete failed with status \(status)."
        }
    }
}

private extension String {
    var removingKeychainPrefix: String? {
        guard hasPrefix("keychain:") else { return nil }
        return String(dropFirst("keychain:".count))
    }
}
