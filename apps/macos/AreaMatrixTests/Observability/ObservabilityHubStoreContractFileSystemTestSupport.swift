@testable import AreaMatrix
import XCTest

enum ContractDurabilityError: Error, Equatable {
    case injected
}

final class IncidentSynchronizeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedIDs: [String] = []
    private let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    var ids: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedIDs
    }

    func record(_ id: String) {
        lock.lock()
        storedIDs.append(id)
        lock.unlock()
    }

    func synchronize(_ id: String) throws {
        record(id)
        if fails { throw ContractDurabilityError.injected }
    }
}

final class ManifestPersistRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallCount = 0
    private var failingCalls: Set<Int>
    private var uncertainCalls: Set<Int>
    private var storedManifests: [ObservabilityStoreManifest] = []

    init(failingCalls: Set<Int> = [], uncertainCalls: Set<Int> = []) {
        self.failingCalls = failingCalls
        self.uncertainCalls = uncertainCalls
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCallCount
    }

    var manifests: [ObservabilityStoreManifest] {
        lock.lock()
        defer { lock.unlock() }
        return storedManifests
    }

    func failNextCall() {
        lock.lock()
        failingCalls.insert(storedCallCount + 1)
        lock.unlock()
    }

    func failNextCalls(_ count: Int) {
        guard count > 0 else { return }
        lock.lock()
        for offset in 1 ... count {
            failingCalls.insert(storedCallCount + offset)
        }
        lock.unlock()
    }

    func makeNextCallUncertain() {
        lock.lock()
        uncertainCalls.insert(storedCallCount + 1)
        lock.unlock()
    }

    func persist(
        _ fileIO: ObservabilityStoreFileIO,
        manifest: ObservabilityStoreManifest
    ) throws -> ObservabilityStoreManifestPersistResult {
        lock.lock()
        storedCallCount += 1
        let call = storedCallCount
        storedManifests.append(manifest)
        let shouldFail = failingCalls.contains(call)
        let shouldBeUncertain = uncertainCalls.contains(call)
        lock.unlock()
        if shouldFail { throw ContractDurabilityError.injected }
        let result = try fileIO.persistManifest(manifest)
        return shouldBeUncertain ? .replacedDurabilityUncertain : result
    }
}

struct HubStoreContractFixture {
    let rootURL: URL
    let logsURL: URL
    let defaults: UserDefaults
    let suiteName: String

    func incidentURL(id: String) -> URL {
        logsURL.appendingPathComponent("incidents/incident-\(id).jsonl")
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        removeTestTemporaryItems(rootURL)
    }
}

func makeHubStoreContractFixture() throws -> HubStoreContractFixture {
    let rootURL = try makeTestTemporaryDirectory(named: "ObservabilityHubStoreContractTests")
    let suiteName = "ObservabilityHubStoreContractTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return HubStoreContractFixture(
        rootURL: rootURL,
        logsURL: rootURL.appendingPathComponent("Logs", isDirectory: true),
        defaults: defaults,
        suiteName: suiteName
    )
}

func contractConfiguration(
    mode: AppObservabilityMode,
    diskBudgetBytes: Int64 = 100 * 1024 * 1024
) -> AppObservabilityConfiguration {
    AppObservabilityConfiguration(
        mode: mode,
        minimumSeverity: .trace,
        diskBudgetBytes: diskBudgetBytes,
        retentionHours: 24,
        includeSensitive: false
    )
}

func contractEvent(
    id: String,
    timestamp: Int64 = 1,
    sessionID: String,
    message: String? = nil
) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 2,
        eventID: id,
        wallTimestampMilliseconds: timestamp,
        monotonicTimestampNanoseconds: UInt64(max(0, timestamp)),
        sequenceNumber: UInt64(max(0, timestamp)),
        sessionID: sessionID,
        incidentID: nil,
        traceID: "trace-\(id)",
        spanID: "span-\(id)",
        parentSpanID: nil,
        operationID: nil,
        retryOfOperationID: nil,
        actionID: "diagnostics.export.confirmed",
        componentID: "macos.observability.runtime",
        layer: "platform",
        phase: "event",
        severity: .info,
        outcome: "succeeded",
        durationMilliseconds: nil,
        resources: [],
        error: nil,
        attributes: [],
        privacy: "public",
        message: message,
        target: nil,
        threadName: nil,
        buildContext: observabilityTestCoreBuildContext()
    )
}

func contractIncident(id: String, sessionID: String) -> ObservabilityIncidentSnapshot {
    ObservabilityIncidentSnapshot(
        id: id,
        sessionID: sessionID,
        markedAtMilliseconds: 1,
        captureEndsAtMilliseconds: 2,
        status: .open,
        note: nil,
        events: [],
        isFrozen: false,
        recoveredAfterRestart: false
    )
}

func eventFileContents(in logsURL: URL) throws -> [String: Data] {
    let urls = try FileManager.default.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("events-") && $0.pathExtension == "jsonl" }
    return try Dictionary(uniqueKeysWithValues: urls.map { try ($0.lastPathComponent, Data(contentsOf: $0)) })
}

@discardableResult
func assertValidStoreManifest(at url: URL, logsURL: URL) throws -> ObservabilityStoreManifest {
    let manifest = try decodeStoreManifest(at: url)
    XCTAssertEqual(manifest.schemaVersion, ObservabilityStoreManifest.currentSchemaVersion)
    XCTAssertEqual(Set(manifest.entries.map(\.name)).count, manifest.entries.count)
    for entry in manifest.entries where entry.disposition.isReadable {
        let fileURL = switch entry.kind {
        case .event:
            logsURL.appendingPathComponent(entry.name)
        case .incident:
            logsURL.appendingPathComponent("incidents/\(entry.name)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }
    return manifest
}

func decodeStoreManifest(at url: URL) throws -> ObservabilityStoreManifest {
    try JSONDecoder().decode(ObservabilityStoreManifest.self, from: Data(contentsOf: url))
}

func writeStoreManifestV1(_ manifest: ObservabilityStoreManifestV1, logsURL: URL) throws {
    try writeStoreManifest(manifest, logsURL: logsURL)
}

func writeStoreManifestV2(_ manifest: ObservabilityStoreManifest, logsURL: URL) throws {
    try writeStoreManifest(manifest, logsURL: logsURL)
}

func prepareStoreDirectories(at logsURL: URL) throws {
    try ObservabilitySafeFileOperations(rootURL: logsURL).prepareDirectories()
}

private func writeStoreManifest(_ manifest: some Encodable, logsURL: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(manifest)
    try data.write(to: logsURL.appendingPathComponent("manifest.json"), options: .atomic)
}

func isSequentialEventFileName(_ name: String) -> Bool {
    guard name.hasPrefix("events-"), name.hasSuffix(".jsonl") else { return false }
    let sequence = name.dropFirst("events-".count).dropLast(".jsonl".count)
    return sequence.count == 20 && sequence.allSatisfy(\.isNumber)
}

func contractPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
}

extension ObservabilityStoreManifestV2Tests {
    func manifest(entries: [ObservabilityStoreManifestEntry]) -> ObservabilityStoreManifest {
        ObservabilityStoreManifest(schemaVersion: 2, nextEventSequence: 1, entries: entries)
    }

    func entry(
        _ name: String,
        kind: ObservabilityStoreManifestFileKind,
        disposition: ObservabilityStoreManifestDisposition,
        committedBytes: Int64? = nil
    ) -> ObservabilityStoreManifestEntry {
        ObservabilityStoreManifestEntry(
            name: name,
            kind: kind,
            disposition: disposition,
            committedBytes: committedBytes
        )
    }

    func eventName(_ sequence: UInt64) -> String {
        String(format: "events-%020llu.jsonl", sequence)
    }

    func manifestURL(_ logsURL: URL) -> URL {
        logsURL.appendingPathComponent("manifest.json")
    }

    func entryMap(
        _ manifest: ObservabilityStoreManifest
    ) -> [String: ObservabilityStoreManifestEntry] {
        Dictionary(uniqueKeysWithValues: manifest.entries.map { ($0.name, $0) })
    }

    func eventLine(id: String) throws -> Data {
        try encodedLine(contractEvent(id: id, sessionID: "migration-session"))
    }

    func incidentJournalData(
        id: String,
        eventID: String? = nil,
        legacyEvent: Bool = false
    ) throws -> Data {
        var data = try encodedLine(ObservabilityIncidentRecord.header(
            contractIncident(id: id, sessionID: "legacy-session")
        ))
        if let eventID {
            try data.append(incidentEventLine(id: id, eventID: eventID, legacy: legacyEvent))
        }
        return data
    }

    func incidentEventLine(id: String, eventID: String, legacy: Bool = false) throws -> Data {
        var event = contractEvent(id: eventID, sessionID: "legacy-session")
        event.incidentID = id
        if legacy {
            event.schemaVersion = 1
            event.buildContext = nil
        }
        return try encodedLine(ObservabilityIncidentRecord.event(id, event))
    }

    func encodedLine(_ value: some Encodable) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    func rawEntry(_ name: String, kind: String, disposition: String) -> [String: Any] {
        ["name": name, "kind": kind, "disposition": disposition]
    }

    func rawManifest(schemaVersion: Int, entries: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "schema_version": schemaVersion,
            "next_event_sequence": 1,
            "entries": entries
        ], options: [.sortedKeys])
    }
}
