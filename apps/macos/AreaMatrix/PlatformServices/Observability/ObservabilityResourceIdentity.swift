import CryptoKit
import Darwin
import Foundation
import Security

actor ObservabilityResourceIdentityProvider {
    static let shared = ObservabilityResourceIdentityProvider()

    private let keyStore: any ObservabilityAliasKeyStoring
    private var cachedKeyState: KeyState?

    init(keyStore: any ObservabilityAliasKeyStoring = ObservabilityAliasKeyStore()) {
        self.keyStore = keyStore
    }

    func identity(
        for sourceURL: URL,
        storageMode: StorageMode
    ) -> ObservabilityResourceIdentityResult {
        guard case let .available(key) = installationKeyState() else {
            return .init(reference: nil, degradedReason: "resource-alias-key-unavailable")
        }
        let reference = ObservabilityResourceIdentityFactory(keyData: key).reference(
            for: sourceURL,
            storageMode: storageMode.observabilityIdentifier,
            fileSize: Self.fileSize(at: sourceURL)
        )
        return .init(reference: reference, degradedReason: nil)
    }

    private func installationKeyState() -> KeyState {
        if let cachedKeyState { return cachedKeyState }
        do {
            if let stored = try keyStore.load() {
                cachedKeyState = stored.count == 32 ? .available(stored) : .unavailable
                return cachedKeyState ?? .unavailable
            }
            let generated = Self.randomKey()
            try keyStore.save(generated)
            guard let stored = try keyStore.load(), stored.count == 32 else {
                cachedKeyState = .unavailable
                return .unavailable
            }
            cachedKeyState = .available(stored)
            return .available(stored)
        } catch {
            cachedKeyState = .unavailable
            return .unavailable
        }
    }

    private static func randomKey() -> Data {
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }

    private static func fileSize(at url: URL) -> Int64? {
        var status = stat()
        guard url.withUnsafeFileSystemRepresentation({ path in
            guard let path else { return false }
            return lstat(path, &status) == 0
        }) else { return nil }
        guard status.st_mode & S_IFMT == S_IFREG else { return nil }
        return Int64(status.st_size)
    }

    private enum KeyState {
        case available(Data)
        case unavailable
    }
}

struct ObservabilityResourceIdentityResult {
    let reference: CoreObservabilityResourceRef?
    let degradedReason: String?
}

struct ObservabilityResourceIdentityFactory {
    private let key: SymmetricKey
    private let idGenerator: @Sendable () -> String

    init(
        keyData: Data,
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        key = SymmetricKey(data: keyData)
        self.idGenerator = idGenerator
    }

    func reference(
        for sourceURL: URL,
        storageMode: String,
        fileSize: Int64?
    ) -> CoreObservabilityResourceRef {
        let locator = sourceURL.standardizedFileURL.path.precomposedStringWithCanonicalMapping
        let digest = Array(HMAC<SHA256>.authenticationCode(for: Data(locator.utf8), using: key))
        return CoreObservabilityResourceRef(
            resourceId: idGenerator(),
            alias: "file.\(Self.hex(digest.prefix(12)))",
            extension: Self.safeExtension(sourceURL.pathExtension),
            sizeBucket: fileSize.map(Self.sizeBucket),
            storageMode: storageMode
        )
    }

    private static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func safeExtension(_ value: String) -> String? {
        let normalized = value.lowercased()
        guard !normalized.isEmpty, normalized.utf8.count <= 32,
              normalized.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })
        else { return nil }
        return normalized
    }

    private static func sizeBucket(_ size: Int64) -> String {
        switch size {
        case ..<1_048_576: "lt_1mb"
        case ..<10_485_760: "1mb_10mb"
        case ..<104_857_600: "10mb_100mb"
        case ..<1_073_741_824: "100mb_1gb"
        default: "gte_1gb"
        }
    }
}

protocol ObservabilityAliasKeyStoring: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
}

struct ObservabilityAliasKeyStore: ObservabilityAliasKeyStoring {
    private static let service = "app.areamatrix.observability"
    private static let account = "resource-alias-key-v1"

    func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ObservabilityAliasKeyStoreError.keychain(status)
        }
        return data
    }

    func save(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw ObservabilityAliasKeyStoreError.keychain(status)
        }
    }
}

enum ObservabilityAliasKeyStoreError: Error {
    case keychain(OSStatus)
}

private extension StorageMode {
    var observabilityIdentifier: String {
        switch self {
        case .copied: "copied"
        case .moved: "moved"
        case .indexed: "indexed"
        }
    }
}
