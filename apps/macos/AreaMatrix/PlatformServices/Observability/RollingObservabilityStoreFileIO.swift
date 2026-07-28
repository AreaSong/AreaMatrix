import Darwin
import Foundation

private struct ObservabilityStoreManifestHeader: Decodable {
    let schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
    }
}

struct ObservabilityStoreDurabilityOperations {
    let synchronizeIncident: @Sendable (Int32, String) throws -> Void

    static let live = Self { descriptor, _ in
        guard Darwin.fsync(descriptor) == 0 else {
            throw ObservabilitySafeFileError.writeFailed
        }
    }
}

enum ObservabilityStoreManifestPersistResult: Equatable {
    case durable
    case replacedDurabilityUncertain

    func requireDurable() throws {
        guard self == .durable else { throw ObservabilityStoreError.durabilityUncertain }
    }
}

struct ObservabilityStoreManifestOperations {
    let persist: @Sendable (
        ObservabilityStoreFileIO,
        ObservabilityStoreManifest
    ) throws -> ObservabilityStoreManifestPersistResult

    static let live = Self { fileIO, manifest in
        try fileIO.persistManifest(manifest)
    }
}

struct ObservabilityStoreFileIO {
    private static let maximumManifestBytes = 1024 * 1024

    let fileManager: FileManager
    let rootURL: URL?

    func prepareDirectories() throws {
        guard let rootURL, rootURL.isFileURL else {
            throw ObservabilityStoreError.applicationSupportUnavailable
        }
        do {
            try safeOperations(rootURL: rootURL).prepareDirectories()
        } catch {
            throw ObservabilityStoreError.unsafePath
        }
    }

    func loadManifest() throws -> ObservabilityStoreManifestLoadResult {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        let data: Data
        do {
            data = try safeOperations(rootURL: rootURL).read(
                "manifest.json",
                kind: .manifest,
                maximumBytes: Self.maximumManifestBytes
            )
        } catch ObservabilitySafeFileError.missing {
            return .missing
        }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(ObservabilityStoreManifestHeader.self, from: data) else {
            return .corrupt
        }
        switch header.schemaVersion {
        case 1:
            guard let manifest = try? decoder.decode(ObservabilityStoreManifestV1.self, from: data) else {
                return .corrupt
            }
            return .version1(manifest)
        case ObservabilityStoreManifest.currentSchemaVersion:
            guard let manifest = try? decoder.decode(ObservabilityStoreManifest.self, from: data) else {
                return .corrupt
            }
            return .version2(manifest)
        default:
            return .unsupported
        }
    }

    func persistManifest(
        _ manifest: ObservabilityStoreManifest
    ) throws -> ObservabilityStoreManifestPersistResult {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        guard data.count <= Self.maximumManifestBytes else {
            throw ObservabilityStoreError.fileTooLarge
        }
        let result = try safeOperations(rootURL: rootURL).replaceAtomically(
            data,
            name: "manifest.json",
            kind: .manifest
        )
        switch result {
        case .durable:
            return .durable
        case .replacedDurabilityUncertain:
            return .replacedDurabilityUncertain
        }
    }

    func createEventFile(named name: String) throws -> (URL, FileHandle) {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        let handle = try safeOperations(rootURL: rootURL).createExclusive(name, kind: .event)
        return (rootURL.appendingPathComponent(name, isDirectory: false), handle)
    }

    func writeIncidentExclusive(
        _ data: Data,
        id: String,
        synchronize: Bool
    ) throws {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        let name = "incident-\(id).jsonl"
        let operations = safeOperations(rootURL: rootURL)
        let handle = try operations.createExclusive(name, kind: .incident(id: id))
        do {
            try handle.write(contentsOf: data)
            if synchronize { try handle.synchronize() }
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    func appendIncident(
        _ data: Data,
        id: String,
        expectedCommittedBytes: Int64,
        synchronize: (Int32) throws -> Void
    ) throws -> Int64 {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        return try safeOperations(rootURL: rootURL).appendAndSynchronize(
            data,
            name: "incident-\(id).jsonl",
            kind: .incident(id: id),
            expectedSize: expectedCommittedBytes,
            synchronize: synchronize
        )
    }

    func truncateIncident(id: String, to committedBytes: Int64) throws {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        try safeOperations(rootURL: rootURL).truncate(
            "incident-\(id).jsonl",
            kind: .incident(id: id),
            to: committedBytes
        )
    }

    func read(_ url: URL, maximumBytes: Int64) throws -> Data {
        guard let rootURL, maximumBytes >= 0, maximumBytes <= Int64(Int.max) else {
            throw ObservabilityStoreError.fileTooLarge
        }
        return try safeOperations(rootURL: rootURL).read(
            url.lastPathComponent,
            kind: ownedKind(for: url),
            maximumBytes: Int(maximumBytes)
        )
    }

    func readPrefix(_ url: URL, byteCount: Int64) throws -> Data {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        return try safeOperations(rootURL: rootURL).readPrefix(
            url.lastPathComponent,
            kind: ownedKind(for: url),
            byteCount: byteCount
        )
    }

    func regularFileSize(_ url: URL) throws -> Int64 {
        try safeMetadata(for: url).st_size
    }

    func ownedDataFiles() throws -> [ObservabilityOwnedFile] {
        try ownedEventFiles() + ownedIncidentFiles()
    }

    func inventory() throws -> ObservabilityStoreInventory {
        let events = try ownedEventFiles()
        let incidents = try ownedIncidentFiles()
        return ObservabilityStoreInventory(
            eventFiles: Dictionary(uniqueKeysWithValues: events.map {
                ($0.url.lastPathComponent, $0)
            }),
            incidentFiles: Dictionary(uniqueKeysWithValues: incidents.map {
                ($0.url.lastPathComponent, $0)
            })
        )
    }

    func ownedEventFiles() throws -> [ObservabilityOwnedFile] {
        guard let rootURL else { return [] }
        return try ownedFiles(in: rootURL, matching: ObservabilityOwnedFileKind.event.accepts)
    }

    func ownedIncidentFiles() throws -> [ObservabilityOwnedFile] {
        guard let rootURL else { return [] }
        return try ownedFiles(
            in: rootURL.appendingPathComponent("incidents", isDirectory: true)
        ) { name in
            name.hasPrefix("incident-") && name.hasSuffix(".jsonl")
        }
    }

    func safeMetadata(for url: URL) throws -> stat {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        return try safeOperations(rootURL: rootURL).metadata(
            url.lastPathComponent,
            kind: ownedKind(for: url)
        )
    }

    func removeOwnedFile(at url: URL) throws {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        try safeOperations(rootURL: rootURL).remove(
            url.lastPathComponent,
            kind: ownedKind(for: url)
        )
    }

    func url(for entry: ObservabilityStoreManifestEntry) throws -> URL {
        guard let rootURL else { throw ObservabilityStoreError.applicationSupportUnavailable }
        switch entry.kind {
        case .event:
            return rootURL.appendingPathComponent(entry.name, isDirectory: false)
        case .incident:
            return rootURL
                .appendingPathComponent("incidents", isDirectory: true)
                .appendingPathComponent(entry.name, isDirectory: false)
        }
    }

    func incidentURL(id: String) throws -> URL {
        guard let rootURL, ObservabilityOwnedFileKind.isSafeIdentifier(id) else {
            throw ObservabilityStoreError.invalidIdentifier
        }
        return rootURL
            .appendingPathComponent("incidents", isDirectory: true)
            .appendingPathComponent("incident-\(id).jsonl", isDirectory: false)
    }

    func incidentID(for url: URL) -> String? {
        let name = url.lastPathComponent
        let prefix = "incident-"
        let suffix = ".jsonl"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let id = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        return ObservabilityOwnedFileKind.isSafeIdentifier(id) ? id : nil
    }
}

private extension ObservabilityStoreFileIO {
    func ownedFiles(
        in directory: URL,
        matching predicate: (String) -> Bool
    ) throws -> [ObservabilityOwnedFile] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ).compactMap { url in
            guard predicate(url.lastPathComponent) else { return nil }
            let metadata = try safeMetadata(for: url)
            let modifiedAt = TimeInterval(metadata.st_mtimespec.tv_sec)
                + TimeInterval(metadata.st_mtimespec.tv_nsec) / 1_000_000_000
            return ObservabilityOwnedFile(
                url: url,
                size: metadata.st_size,
                modifiedAt: Date(timeIntervalSince1970: modifiedAt)
            )
        }
    }

    func ownedKind(for url: URL) throws -> ObservabilityOwnedFileKind {
        let name = url.lastPathComponent
        if ObservabilityOwnedFileKind.event.accepts(name) { return .event }
        guard let id = incidentID(for: url) else { throw ObservabilityStoreError.unsafePath }
        return .incident(id: id)
    }

    func safeOperations(rootURL: URL) -> ObservabilitySafeFileOperations {
        ObservabilitySafeFileOperations(rootURL: rootURL)
    }
}
