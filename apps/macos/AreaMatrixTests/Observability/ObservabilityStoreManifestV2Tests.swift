@testable import AreaMatrix
import Darwin
import XCTest

final class ObservabilityStoreManifestV2Tests: XCTestCase {
    func testVersionOneMigrationAdoptsOnlyListedEventsAndMarksIncidentsReadOnly() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let listedName = eventName(4)
        let unlistedName = eventName(5)
        try eventLine(id: "listed").write(to: fixture.logsURL.appendingPathComponent(listedName))
        try eventLine(id: "unlisted").write(to: fixture.logsURL.appendingPathComponent(unlistedName))
        try incidentJournalData(
            id: "legacy-incident",
            eventID: "legacy-event",
            legacyEvent: true
        ).write(
            to: fixture.incidentURL(id: "legacy-incident")
        )
        try writeStoreManifestV1(
            ObservabilityStoreManifestV1(
                schemaVersion: 1,
                nextEventSequence: 2,
                eventFiles: [listedName]
            ),
            logsURL: fixture.logsURL
        )

        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: contractConfiguration(mode: .developer))
        store.close()

        let entries = try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))
        XCTAssertEqual(entries[listedName]?.disposition, .managed)
        XCTAssertNil(entries[unlistedName])
        XCTAssertEqual(entries["incident-legacy-incident.jsonl"]?.disposition, .readOnly)
        let recovered = try store.loadRecoverableIncidents(currentSessionID: "restart-session")
        XCTAssertEqual(recovered.map(\.snapshot.id), ["legacy-incident"])
        XCTAssertEqual(recovered.map(\.disposition), [.readOnly])
        XCTAssertEqual(recovered.first?.snapshot.events.map(\.eventID), ["legacy-event"])
    }

    func testPendingCreationDropsAuthorityWithoutDeletingSameNameFile() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let reservedName = eventName(0)
        let foreignBytes = Data("foreign-same-name".utf8)
        let foreignURL = fixture.logsURL.appendingPathComponent(reservedName)
        try foreignBytes.write(to: foreignURL)
        try writeStoreManifestV2(
            manifest(entries: [entry(reservedName, kind: .event, disposition: .pendingCreation)]),
            logsURL: fixture.logsURL
        )

        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: contractConfiguration(mode: .developer))
        store.close()

        XCTAssertEqual(try Data(contentsOf: foreignURL), foreignBytes)
        let entries = try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))
        XCTAssertNil(entries[reservedName])
        XCTAssertEqual(entries[eventName(1)]?.disposition, .managed)
    }

    func testPendingDeletionRecoveryConvergesWithPresentAndMissingFiles() throws {
        try assertPendingDeletionRecovery(fileExists: true)
        try assertPendingDeletionRecovery(fileExists: false)
    }

    func testCorruptUnsupportedAndIllegalManifestsFailClosed() throws {
        let name = eventName(0)
        let duplicate = [
            rawEntry(name, kind: "event", disposition: "managed"),
            rawEntry(name, kind: "event", disposition: "managed")
        ]
        let cases: [(Data, ObservabilityStoreError)] = try [
            (Data("{corrupt".utf8), .corruptManifest),
            (rawManifest(schemaVersion: 99, entries: []), .unsupportedSchema),
            (rawManifest(schemaVersion: 2, entries: duplicate), .corruptManifest),
            (
                rawManifest(
                    schemaVersion: 2,
                    entries: [rawEntry(name, kind: "event", disposition: "read_only")]
                ),
                .corruptManifest
            ),
            (
                rawManifest(
                    schemaVersion: 2,
                    entries: [rawEntry(name, kind: "incident", disposition: "managed")]
                ),
                .corruptManifest
            ),
            (
                rawManifest(
                    schemaVersion: 2,
                    entries: [rawEntry("../\(name)", kind: "event", disposition: "pending_deletion")]
                ),
                .corruptManifest
            ),
            (
                rawManifest(
                    schemaVersion: 2,
                    entries: [rawEntry("/tmp/\(name)", kind: "event", disposition: "managed")]
                ),
                .corruptManifest
            ),
            (
                rawManifest(
                    schemaVersion: 2,
                    entries: [rawEntry("incident-../outside.jsonl", kind: "incident", disposition: "managed")]
                ),
                .corruptManifest
            )
        ]
        for (data, expectedError) in cases {
            try assertManifestFailsClosed(data, expectedError: expectedError)
        }
    }

    func testDestructiveReloadDoesNotReuseStaleManifestAuthority() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let configuration = contractConfiguration(mode: .developer)
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: configuration)
        try store.append(
            contractEvent(id: "stale-authority", sessionID: "stale-session"),
            configuration: configuration
        )
        store.close()
        let eventBytes = try eventFileContents(in: fixture.logsURL)
        let manifestURL = manifestURL(fixture.logsURL)
        let corruptBytes = Data("{stale-corrupt".utf8)
        try corruptBytes.write(to: manifestURL)

        XCTAssertThrowsError(try store.removeAllLogs()) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .corruptManifest)
        }

        XCTAssertEqual(try Data(contentsOf: manifestURL), corruptBytes)
        XCTAssertEqual(try eventFileContents(in: fixture.logsURL), eventBytes)
    }

    func testManagedCreationPersistFailureLeavesUnownedFileForSafeRecovery() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let recorder = ManifestPersistRecorder(failingCalls: [3])
        var failingStore = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            manifestOperations: .init { fileIO, manifest in
                try recorder.persist(fileIO, manifest: manifest)
            }
        )

        XCTAssertThrowsError(try failingStore.prepare(
            configuration: contractConfiguration(mode: .developer)
        )) { error in
            XCTAssertEqual(error as? ContractDurabilityError, .injected)
        }

        let unownedURL = fixture.logsURL.appendingPathComponent(eventName(0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unownedURL.path))
        XCTAssertNil(try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))[eventName(0)])
        var recovered = RollingObservabilityStore(rootURL: fixture.logsURL)
        try recovered.prepare(configuration: contractConfiguration(mode: .developer))
        recovered.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: unownedURL.path))
        let entries = try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))
        XCTAssertNil(entries[eventName(0)])
        XCTAssertEqual(entries[eventName(1)]?.disposition, .managed)
    }

    func testDeletionCompletionPersistFailureRecoversFromPendingDeletion() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        let configuration = contractConfiguration(mode: .developer)
        var seed = RollingObservabilityStore(rootURL: fixture.logsURL)
        try seed.prepare(configuration: configuration)
        try seed.beginIncident(
            contractIncident(id: "pending-delete", sessionID: "delete-session"),
            configuration: configuration
        )
        seed.close()
        let recorder = ManifestPersistRecorder(failingCalls: [2])
        var deleting = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            manifestOperations: .init { fileIO, manifest in
                try recorder.persist(fileIO, manifest: manifest)
            }
        )

        XCTAssertThrowsError(try deleting.removeIncident(id: "pending-delete")) { error in
            XCTAssertEqual(error as? ContractDurabilityError, .injected)
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.incidentURL(id: "pending-delete").path
        ))
        XCTAssertEqual(deleting.takeIncidentPersistenceChanges().readOnlyIDs, ["pending-delete"])
        let pending = try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))
        XCTAssertEqual(pending["incident-pending-delete.jsonl"]?.disposition, .pendingDeletion)
        var recovered = RollingObservabilityStore(rootURL: fixture.logsURL)
        try recovered.prepare(configuration: configuration)
        recovered.close()
        let finalEntries = try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))
        XCTAssertNil(finalEntries["incident-pending-delete.jsonl"])
    }

    func testLegacyVersionTwoIncidentDerivesCommittedBytesAndTruncatesTail() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let incidentID = "legacy-offset"
        let committed = try incidentJournalData(id: incidentID, eventID: "committed-event")
        var physical = committed
        physical.append(Data("{uncommitted-tail".utf8))
        try physical.write(to: fixture.incidentURL(id: incidentID))
        let name = "incident-\(incidentID).jsonl"
        try writeStoreManifestV2(
            manifest(entries: [entry(name, kind: .incident, disposition: .managed)]),
            logsURL: fixture.logsURL
        )

        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: contractConfiguration(mode: .developer))
        store.close()

        let migrated = try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))
        XCTAssertEqual(migrated[name]?.committedBytes, Int64(committed.count))
        XCTAssertEqual(try Data(contentsOf: fixture.incidentURL(id: incidentID)), committed)
        XCTAssertEqual(
            try store.loadIncidentSnapshots(currentSessionID: "restart").first?.events.map(\.eventID),
            ["committed-event"]
        )
    }

    func testCommittedOffsetPastEndRevokesAuthorityWithoutDeletingFile() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let incidentID = "short-physical"
        let bytes = try incidentJournalData(id: incidentID)
        let url = fixture.incidentURL(id: incidentID)
        try bytes.write(to: url)
        let name = "incident-\(incidentID).jsonl"
        try writeStoreManifestV2(
            manifest(entries: [entry(
                name,
                kind: .incident,
                disposition: .managed,
                committedBytes: Int64(bytes.count + 1)
            )]),
            logsURL: fixture.logsURL
        )

        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: contractConfiguration(mode: .developer))
        store.close()

        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNil(try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))[name])
        XCTAssertTrue(try store.loadIncidentSnapshots(currentSessionID: "restart").isEmpty)
    }

    func testReadOnlyIncidentRecoveryNeverTruncatesPhysicalTail() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let incidentID = "readonly-tail"
        let committed = try incidentJournalData(id: incidentID)
        var physical = committed
        physical.append(try incidentEventLine(id: incidentID, eventID: "uncommitted-event"))
        let url = fixture.incidentURL(id: incidentID)
        try physical.write(to: url)
        let name = "incident-\(incidentID).jsonl"
        try writeStoreManifestV2(
            manifest(entries: [entry(
                name,
                kind: .incident,
                disposition: .readOnly,
                committedBytes: Int64(committed.count)
            )]),
            logsURL: fixture.logsURL
        )

        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: contractConfiguration(mode: .developer))
        store.close()

        XCTAssertEqual(try Data(contentsOf: url), physical)
        XCTAssertEqual(store.usageBytes, Int64(physical.count))
        let recovered = try store.loadRecoverableIncidents(currentSessionID: "restart")
        XCTAssertEqual(recovered.first?.disposition, .readOnly)
        XCTAssertTrue(recovered.first?.snapshot.events.isEmpty == true)
    }

    func testHiddenExternalCandidateIsCountedBeforeBudgetDecision() throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: contractConfiguration(mode: .developer))
        let externalURL = fixture.logsURL.appendingPathComponent(eventName(9999))
        let externalBytes = Data(repeating: 0x41, count: 4096)
        try externalBytes.write(to: externalURL)
        XCTAssertEqual(chflags(externalURL.path, UInt32(UF_HIDDEN)), 0)

        XCTAssertThrowsError(try store.append(
            contractEvent(id: "budget-refresh", sessionID: "budget-session"),
            configuration: contractConfiguration(mode: .developer, diskBudgetBytes: 2048)
        )) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .budgetExceeded)
        }

        XCTAssertGreaterThanOrEqual(store.usageBytes, Int64(externalBytes.count))
        XCTAssertEqual(try Data(contentsOf: externalURL), externalBytes)
    }

    func testCheckedTimeAndByteArithmeticNeverTrap() {
        XCTAssertEqual(ObservabilityTime.milliseconds(Date(timeIntervalSince1970: .infinity)), .max)
        XCTAssertEqual(ObservabilityTime.milliseconds(Date(timeIntervalSince1970: -.infinity)), .min)
        XCTAssertEqual(ObservabilityTime.milliseconds(Date(timeIntervalSince1970: .nan)), 0)
        XCTAssertThrowsError(try ObservabilityStoreArithmetic.adding(.max, 1)) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .fileTooLarge)
        }
    }
}

private extension ObservabilityStoreManifestV2Tests {
    func assertPendingDeletionRecovery(fileExists: Bool) throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let name = eventName(fileExists ? 10 : 11)
        let fileURL = fixture.logsURL.appendingPathComponent(name)
        if fileExists { try Data("pending".utf8).write(to: fileURL) }
        try writeStoreManifestV2(
            manifest(entries: [entry(name, kind: .event, disposition: .pendingDeletion)]),
            logsURL: fixture.logsURL
        )
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: contractConfiguration(mode: .developer))
        store.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNil(try entryMap(decodeStoreManifest(at: manifestURL(fixture.logsURL)))[name])
    }

    func assertManifestFailsClosed(
        _ data: Data,
        expectedError: ObservabilityStoreError
    ) throws {
        let fixture = try makeHubStoreContractFixture()
        defer { fixture.cleanup() }
        try prepareStoreDirectories(at: fixture.logsURL)
        let sentinelURL = fixture.logsURL.appendingPathComponent(eventName(0))
        let sentinelBytes = Data("sentinel".utf8)
        try sentinelBytes.write(to: sentinelURL)
        let outsideURL = fixture.rootURL.appendingPathComponent("outside-sentinel.txt")
        let outsideBytes = Data("outside-sentinel".utf8)
        try outsideBytes.write(to: outsideURL)
        let manifestURL = manifestURL(fixture.logsURL)
        try data.write(to: manifestURL)
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        XCTAssertThrowsError(try store.prepare(
            configuration: contractConfiguration(mode: .developer)
        )) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, expectedError)
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), data)
        XCTAssertEqual(try Data(contentsOf: sentinelURL), sentinelBytes)
        XCTAssertEqual(try Data(contentsOf: outsideURL), outsideBytes)
        XCTAssertEqual(try Set(eventFileContents(in: fixture.logsURL).keys), [eventName(0)])
    }

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
            data.append(try incidentEventLine(id: id, eventID: eventID, legacy: legacyEvent))
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
