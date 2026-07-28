import Foundation

enum ObservabilityStoreManifestDisposition: String, Codable, Equatable {
    case managed
    case readOnly = "read_only"
    case pendingCreation = "pending_creation"
    case pendingDeletion = "pending_deletion"

    var isReadable: Bool {
        self == .managed || self == .readOnly
    }

    var isDeletable: Bool {
        self == .managed || self == .pendingDeletion
    }
}

enum ObservabilityStoreManifestFileKind: String, Codable, Equatable {
    case event
    case incident
}

struct ObservabilityStoreManifestEntry: Codable, Equatable {
    var name: String
    var kind: ObservabilityStoreManifestFileKind
    var disposition: ObservabilityStoreManifestDisposition
    var committedBytes: Int64?

    init(
        name: String,
        kind: ObservabilityStoreManifestFileKind,
        disposition: ObservabilityStoreManifestDisposition,
        committedBytes: Int64? = nil
    ) {
        self.name = name
        self.kind = kind
        self.disposition = disposition
        self.committedBytes = committedBytes
    }

    enum CodingKeys: String, CodingKey {
        case name
        case kind
        case disposition
        case committedBytes = "committed_bytes"
    }
}

struct ObservabilityStoreManifest: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var nextEventSequence: UInt64
    var entries: [ObservabilityStoreManifestEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case nextEventSequence = "next_event_sequence"
        case entries
    }
}

struct ObservabilityStoreManifestV1: Codable, Equatable {
    var schemaVersion: Int
    var nextEventSequence: UInt64
    var eventFiles: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case nextEventSequence = "next_event_sequence"
        case eventFiles = "event_files"
    }
}

enum ObservabilityStoreManifestLoadResult {
    case missing
    case version1(ObservabilityStoreManifestV1)
    case version2(ObservabilityStoreManifest)
    case corrupt
    case unsupported
}

struct ObservabilityStoreInventory {
    var eventFiles: [String: ObservabilityOwnedFile]
    var incidentFiles: [String: ObservabilityOwnedFile]

    var occupiedNames: Set<String> {
        Set(eventFiles.keys).union(incidentFiles.keys)
    }

    var files: [ObservabilityOwnedFile] {
        Array(eventFiles.values) + Array(incidentFiles.values)
    }

    func file(for entry: ObservabilityStoreManifestEntry) -> ObservabilityOwnedFile? {
        switch entry.kind {
        case .event:
            eventFiles[entry.name]
        case .incident:
            incidentFiles[entry.name]
        }
    }
}

struct ObservabilityStoreManifestRecovery {
    var state: ObservabilityStoreManifestState
    var requiresPersistence: Bool
}

struct ObservabilityStoreManifestState {
    private(set) var nextEventSequence: UInt64
    private(set) var entries: [String: ObservabilityStoreManifestEntry]
    private(set) var occupiedNames: Set<String>

    init(
        nextEventSequence: UInt64,
        entries: [String: ObservabilityStoreManifestEntry] = [:],
        occupiedNames: Set<String> = []
    ) {
        self.nextEventSequence = nextEventSequence
        self.entries = entries
        self.occupiedNames = occupiedNames
    }

    static func recover(using fileIO: ObservabilityStoreFileIO) throws -> ObservabilityStoreManifestRecovery {
        let inventory = try fileIO.inventory()
        switch try fileIO.loadManifest() {
        case .missing:
            return ObservabilityStoreManifestRecovery(
                state: emptyState(inventory: inventory),
                requiresPersistence: true
            )
        case let .version1(manifest):
            return try migrate(manifest, inventory: inventory, fileIO: fileIO)
        case let .version2(manifest):
            return try recover(manifest, inventory: inventory, fileIO: fileIO)
        case .corrupt:
            throw ObservabilityStoreError.corruptManifest
        case .unsupported:
            throw ObservabilityStoreError.unsupportedSchema
        }
    }

    mutating func reserveEventFileName() throws -> String {
        while true {
            let name = Self.eventFileName(sequence: nextEventSequence)
            if !occupiedNames.contains(name), entries[name] == nil {
                entries[name] = ObservabilityStoreManifestEntry(
                    name: name,
                    kind: .event,
                    disposition: .pendingCreation
                )
                occupiedNames.insert(name)
                if nextEventSequence < .max { nextEventSequence += 1 }
                return name
            }
            guard nextEventSequence < .max else { throw ObservabilityStoreError.createFailed }
            nextEventSequence += 1
        }
    }

    mutating func reserveIncident(id: String) throws -> String {
        guard ObservabilityOwnedFileKind.isSafeIdentifier(id) else {
            throw ObservabilityStoreError.invalidIdentifier
        }
        let name = "incident-\(id).jsonl"
        guard !occupiedNames.contains(name), entries[name] == nil else {
            throw ObservabilityStoreError.createFailed
        }
        entries[name] = ObservabilityStoreManifestEntry(
            name: name,
            kind: .incident,
            disposition: .pendingCreation
        )
        occupiedNames.insert(name)
        return name
    }

    mutating func markManaged(_ name: String, committedBytes: Int64? = nil) throws {
        guard var entry = entries[name], entry.disposition == .pendingCreation else {
            throw ObservabilityStoreError.unsafePath
        }
        switch entry.kind {
        case .event:
            guard committedBytes == nil else { throw ObservabilityStoreError.unsafePath }
        case .incident:
            guard let committedBytes, committedBytes >= 0 else {
                throw ObservabilityStoreError.unsafePath
            }
            entry.committedBytes = committedBytes
        }
        entry.disposition = .managed
        entries[name] = entry
    }

    mutating func commitIncidentBytes(
        _ name: String,
        from previousBytes: Int64,
        to committedBytes: Int64
    ) throws {
        guard var entry = entries[name],
              entry.kind == .incident,
              entry.disposition == .managed,
              entry.committedBytes == previousBytes,
              committedBytes >= previousBytes
        else { throw ObservabilityStoreError.unsafePath }
        entry.committedBytes = committedBytes
        entries[name] = entry
    }

    mutating func markPendingDeletion(_ names: Set<String>) throws {
        for name in names {
            guard var entry = entries[name],
                  entry.disposition == .managed || entry.disposition == .pendingDeletion
            else {
                throw ObservabilityStoreError.readOnly
            }
            entry.disposition = .pendingDeletion
            entries[name] = entry
        }
    }

    mutating func markReadOnly(_ name: String) throws {
        guard var entry = entries[name], entry.kind == .incident else {
            throw ObservabilityStoreError.openFailed
        }
        entry.disposition = .readOnly
        entries[name] = entry
    }

    mutating func completeDeletion(_ name: String) {
        entries.removeValue(forKey: name)
        occupiedNames.remove(name)
    }

    mutating func cancelCreation(_ name: String, remainsOccupied: Bool) throws {
        guard entries[name]?.disposition == .pendingCreation else {
            throw ObservabilityStoreError.unsafePath
        }
        entries.removeValue(forKey: name)
        if !remainsOccupied { occupiedNames.remove(name) }
    }

    mutating func refreshOccupiedNames(_ names: Set<String>) {
        occupiedNames = names.union(entries.keys)
    }

    mutating func removeMissingEntry(_ name: String) {
        entries.removeValue(forKey: name)
        occupiedNames.remove(name)
    }

    func entry(named name: String) -> ObservabilityStoreManifestEntry? {
        entries[name]
    }

    func matchingEntries(
        kind: ObservabilityStoreManifestFileKind,
        where predicate: (ObservabilityStoreManifestDisposition) -> Bool
    ) -> [ObservabilityStoreManifestEntry] {
        entries.values.filter { $0.kind == kind && predicate($0.disposition) }
    }

    func snapshot() -> ObservabilityStoreManifest {
        ObservabilityStoreManifest(
            schemaVersion: ObservabilityStoreManifest.currentSchemaVersion,
            nextEventSequence: nextEventSequence,
            entries: entries.values.sorted { $0.name < $1.name }
        )
    }

    static func sequence(fromEventFileName name: String) -> UInt64? {
        let prefix = "events-"
        let suffix = ".jsonl"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let digits = name.dropFirst(prefix.count).dropLast(suffix.count)
        guard digits.count == 20, digits.allSatisfy(\.isNumber) else { return nil }
        return UInt64(digits)
    }
}

private extension ObservabilityStoreManifestState {
    static func emptyState(inventory: ObservabilityStoreInventory) -> Self {
        Self(
            nextEventSequence: nextSequence(after: Set(inventory.eventFiles.keys)),
            occupiedNames: inventory.occupiedNames
        )
    }

    static func migrate(
        _ manifest: ObservabilityStoreManifestV1,
        inventory: ObservabilityStoreInventory,
        fileIO: ObservabilityStoreFileIO
    ) throws -> ObservabilityStoreManifestRecovery {
        guard manifest.schemaVersion == 1,
              Set(manifest.eventFiles).count == manifest.eventFiles.count,
              manifest.eventFiles.allSatisfy(ObservabilityOwnedFileKind.event.accepts)
        else { throw ObservabilityStoreError.corruptManifest }
        var entries: [String: ObservabilityStoreManifestEntry] = [:]
        for name in manifest.eventFiles where inventory.eventFiles[name] != nil {
            entries[name] = ObservabilityStoreManifestEntry(
                name: name,
                kind: .event,
                disposition: .managed
            )
        }
        for (name, file) in inventory.incidentFiles {
            let legacy = ObservabilityStoreManifestEntry(
                name: name,
                kind: .incident,
                disposition: .readOnly
            )
            if let normalized = try normalizedIncidentEntry(legacy, file: file, fileIO: fileIO) {
                entries[name] = normalized
            }
        }
        return ObservabilityStoreManifestRecovery(
            state: Self(
                nextEventSequence: max(
                    manifest.nextEventSequence,
                    nextSequence(after: Set(inventory.eventFiles.keys))
                ),
                entries: entries,
                occupiedNames: inventory.occupiedNames
            ),
            requiresPersistence: true
        )
    }

    static func recover(
        _ manifest: ObservabilityStoreManifest,
        inventory: ObservabilityStoreInventory,
        fileIO: ObservabilityStoreFileIO
    ) throws -> ObservabilityStoreManifestRecovery {
        guard manifest.schemaVersion == ObservabilityStoreManifest.currentSchemaVersion,
              Set(manifest.entries.map(\.name)).count == manifest.entries.count,
              manifest.entries.allSatisfy(valid)
        else { throw ObservabilityStoreError.corruptManifest }
        var recovered: [String: ObservabilityStoreManifestEntry] = [:]
        var changed = false
        for entry in manifest.entries {
            if entry.disposition == .pendingCreation {
                // A reservation alone cannot prove who created a same-name file after a crash.
                changed = true
                continue
            }
            guard let file = inventory.file(for: entry) else {
                changed = true
                continue
            }
            if entry.kind == .incident {
                guard let normalized = try normalizedIncidentEntry(entry, file: file, fileIO: fileIO) else {
                    changed = true
                    continue
                }
                recovered[entry.name] = normalized
                changed = changed || normalized != entry
            } else {
                recovered[entry.name] = entry
            }
        }
        let scannedNext = nextSequence(after: Set(inventory.eventFiles.keys))
        let resolvedNext = max(manifest.nextEventSequence, scannedNext)
        return ObservabilityStoreManifestRecovery(
            state: Self(
                nextEventSequence: resolvedNext,
                entries: recovered,
                occupiedNames: inventory.occupiedNames
            ),
            requiresPersistence: changed || resolvedNext != manifest.nextEventSequence
        )
    }

    static func valid(_ entry: ObservabilityStoreManifestEntry) -> Bool {
        switch entry.kind {
        case .event:
            return ObservabilityOwnedFileKind.event.accepts(entry.name)
                && entry.disposition != .readOnly
                && entry.committedBytes == nil
        case .incident:
            guard incidentID(from: entry.name) != nil else { return false }
            if entry.disposition == .pendingCreation { return entry.committedBytes == nil }
            return entry.committedBytes.map { $0 >= 0 } ?? true
        }
    }

    static func normalizedIncidentEntry(
        _ entry: ObservabilityStoreManifestEntry,
        file: ObservabilityOwnedFile,
        fileIO: ObservabilityStoreFileIO
    ) throws -> ObservabilityStoreManifestEntry? {
        guard let incidentID = incidentID(from: entry.name), file.size >= 0 else { return nil }
        let maximumBytes = RollingObservabilityStore.maximumIncidentBytes
        var normalized = entry
        let committedBytes: Int64
        if let existing = entry.committedBytes {
            guard existing > 0, existing <= file.size, existing <= maximumBytes else { return nil }
            let data = try fileIO.readPrefix(file.url, byteCount: existing)
            guard ObservabilityStoreRecordCodec().validIncidentPrefixLength(
                data,
                expectedIncidentID: incidentID
            ) == existing else { return nil }
            committedBytes = existing
        } else {
            guard file.size <= maximumBytes else { return nil }
            let data = try fileIO.read(file.url, maximumBytes: maximumBytes)
            guard let validBytes = ObservabilityStoreRecordCodec().validIncidentPrefixLength(
                data,
                expectedIncidentID: incidentID
            ) else { return nil }
            committedBytes = validBytes
        }
        normalized.committedBytes = committedBytes
        return normalized
    }

    static func incidentID(from name: String) -> String? {
        let prefix = "incident-"
        let suffix = ".jsonl"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let id = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        return ObservabilityOwnedFileKind.isSafeIdentifier(id) ? id : nil
    }

    static func nextSequence(after names: Set<String>) -> UInt64 {
        guard let maximum = names.compactMap(sequence(fromEventFileName:)).max() else { return 0 }
        return maximum == .max ? .max : maximum + 1
    }

    static func eventFileName(sequence: UInt64) -> String {
        String(format: "events-%020llu.jsonl", sequence)
    }
}
