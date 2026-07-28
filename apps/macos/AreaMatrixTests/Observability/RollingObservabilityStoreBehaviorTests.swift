@testable import AreaMatrix
import XCTest

final class RollingObservabilityStoreBehaviorTests: XCTestCase {
    func testFrozenIncidentRecoversAfterRestartAndIgnoresCorruptTail() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 2_000_000)
        let firstHub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "first-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { "recoverable" }
        )
        let config = configuration(mode: .developer, minimumSeverity: .trace)
        await firstHub.configure(config)
        await firstHub.ingestCoreEvent(event(id: "before-crash", timestamp: 2_000_000, sessionID: "first-session"))
        _ = await firstHub.markIncident(note: "local note")
        try await firstHub.flush()

        let incidentURL = fixture.logsURL
            .appendingPathComponent("incidents", isDirectory: true)
            .appendingPathComponent("incident-recoverable.jsonl")
        let handle = try FileHandle(forWritingTo: incidentURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{corrupt-tail".utf8))
        try handle.close()

        let recoveredHub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "second-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date }
        )
        await recoveredHub.configure(config)
        let snapshots = await recoveredHub.incidentSnapshots()
        let activeIncidentID = await recoveredHub.activeIncidentID()
        let snapshot = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snapshot.id, "recoverable")
        XCTAssertEqual(snapshot.events.map(\.eventID), ["before-crash"])
        XCTAssertEqual(snapshot.note, "local note")
        XCTAssertTrue(snapshot.isFrozen)
        XCTAssertTrue(snapshot.recoveredAfterRestart)
        XCTAssertNil(activeIncidentID)
    }

    func testStoreRotatesPrunesAndKeepsStrictPermissionsAndBudget() throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 3_000_000)
        let config = configuration(mode: .developer, diskBudgetBytes: 3000, retentionHours: 1)
        var store = RollingObservabilityStore(
            rootURL: fixture.logsURL,
            now: { clock.date },
            rotationBytesOverride: 700
        )
        try store.prepare(configuration: config)
        for index in 0 ..< 12 {
            try store.append(event(
                id: "stored-\(index)",
                timestamp: 3_000_000 + Int64(index),
                sessionID: "store-session",
                message: String(repeating: "x", count: 120)
            ), configuration: config)
        }
        store.close()

        let eventURLs = try observabilityEventURLs(in: fixture.logsURL)
        XCTAssertGreaterThan(eventURLs.count, 1)
        XCTAssertLessThanOrEqual(store.usageBytes, config.diskBudgetBytes)
        XCTAssertEqual(try observabilityPermissions(at: fixture.logsURL), 0o700)
        XCTAssertEqual(
            try observabilityPermissions(at: fixture.logsURL.appendingPathComponent("incidents", isDirectory: true)),
            0o700
        )
        for url in eventURLs {
            XCTAssertEqual(try observabilityPermissions(at: url), 0o600)
        }

        let newest = try XCTUnwrap(eventURLs.last)
        let handle = try FileHandle(forWritingTo: newest)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{broken".utf8))
        try handle.close()
        let recovered = try store.loadRecentEvents(limit: 100)
        XCTAssertFalse(recovered.isEmpty)
        XCTAssertTrue(recovered.map(\.eventID).contains("stored-11"))

        try assertUnownedExpiredCandidatesSurvive(
            in: fixture.logsURL,
            store: &store,
            configuration: config
        )
    }

    func testStoreRejectsSymlinksAndCreateNewIncidentCollision() throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let outsideURL = fixture.rootURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: false)
        let sentinelURL = outsideURL.appendingPathComponent("sentinel.txt")
        try Data("unchanged".utf8).write(to: sentinelURL)
        let linkedLogsURL = fixture.rootURL.appendingPathComponent("linked-logs", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedLogsURL, withDestinationURL: outsideURL)
        var linkedStore = RollingObservabilityStore(rootURL: linkedLogsURL)
        XCTAssertThrowsError(try linkedStore.prepare(configuration: configuration(mode: .developer))) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .unsafePath)
        }
        XCTAssertEqual(try String(contentsOf: sentinelURL, encoding: .utf8), "unchanged")

        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        let config = configuration(mode: .developer)
        try store.prepare(configuration: config)
        let collisionTarget = outsideURL.appendingPathComponent("collision-target")
        try Data("target".utf8).write(to: collisionTarget)
        let collisionURL = fixture.logsURL.appendingPathComponent("incidents/incident-collision.jsonl")
        try FileManager.default.createSymbolicLink(at: collisionURL, withDestinationURL: collisionTarget)
        XCTAssertThrowsError(
            try store.beginIncident(
                incident(id: "collision", sessionID: "store-session"),
                configuration: config
            )
        ) { error in
            XCTAssertEqual(error as? ObservabilitySafeFileError, .unsafePath)
        }
        XCTAssertEqual(try String(contentsOf: collisionTarget, encoding: .utf8), "target")
    }

    func testRollingAndIncidentWritersRejectLegacyEvents() throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let config = configuration(mode: .developer)
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: config)

        var legacy = event(id: "legacy", timestamp: 1, sessionID: "writer-session")
        legacy.schemaVersion = 1
        legacy.buildContext = nil
        assertUnsupportedSchema {
            try store.append(legacy, configuration: config)
        }

        var legacyIncident = incident(id: "legacy-header", sessionID: "writer-session")
        legacyIncident.events = [legacy]
        assertUnsupportedSchema {
            try store.beginIncident(legacyIncident, configuration: config)
        }

        try store.beginIncident(
            incident(id: "current-header", sessionID: "writer-session"),
            configuration: config
        )
        assertUnsupportedSchema {
            try store.appendIncidentEvent(
                legacy,
                incidentID: "current-header",
                configuration: config
            )
        }
    }

    func testRestartRecoveryIgnoresUncommittedTailAndRejectsUnsafeEvents() async throws {
        let fixture = try makeObservabilityFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 4_000_000)
        let config = configuration(mode: .developer, minimumSeverity: .trace)
        let firstHub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "first-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date },
            idGenerator: { "sanitized-recovery" }
        )
        await firstHub.configure(config)
        await firstHub.ingestCoreEvent(event(
            id: "valid-current",
            timestamp: clock.milliseconds,
            sessionID: "first-session"
        ))
        _ = await firstHub.markIncident(note: "safe note")
        try await firstHub.shutdown()

        let incidentURL = fixture.logsURL
            .appendingPathComponent("incidents", isDirectory: true)
            .appendingPathComponent("incident-sanitized-recovery.jsonl")
        let committed = try Data(contentsOf: incidentURL)
        try appendRecoveryAttackRecords(to: incidentURL)

        let recoveredHub = ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: fixture.defaults),
            rootURL: fixture.logsURL,
            sessionID: "second-session",
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: { clock.date }
        )
        await recoveredHub.configure(config)
        let snapshots = await recoveredHub.incidentSnapshots()
        let snapshot = try XCTUnwrap(snapshots.first)

        XCTAssertEqual(snapshot.events.map(\.eventID), ["valid-current"])
        XCTAssertEqual(snapshot.note, "safe note")
        XCTAssertTrue(snapshot.isFrozen)
        XCTAssertTrue(snapshot.recoveredAfterRestart)
        XCTAssertEqual(try Data(contentsOf: incidentURL), committed)
    }

    func testIncidentJournalStopsAtFirstInvalidRecordAndSecondHeader() throws {
        let codec = ObservabilityStoreRecordCodec()
        let incident = incident(id: "journal", sessionID: "journal-session")
        var first = event(id: "first", timestamp: 1, sessionID: "journal-session")
        first.incidentID = "journal"
        var afterInvalid = event(id: "after-invalid", timestamp: 2, sessionID: "journal-session")
        afterInvalid.incidentID = "journal"
        let header = try codec.encodedRecord(.header(incident))
        let firstRecord = try codec.encodedRecord(.event("journal", first))
        let laterRecord = try codec.encodedRecord(.event("journal", afterInvalid))
        let corruptData = header + firstRecord + Data("{invalid}\n".utf8) + laterRecord

        let corruptRecovered = codec.decodeIncident(
            corruptData,
            expectedIncidentID: "journal",
            currentSessionID: "journal-session",
            nowMilliseconds: 1
        )
        XCTAssertEqual(corruptRecovered?.events.map(\.eventID), ["first"])

        let secondHeaderData = header + firstRecord + header + laterRecord
        let secondHeaderRecovered = codec.decodeIncident(
            secondHeaderData,
            expectedIncidentID: "journal",
            currentSessionID: "journal-session",
            nowMilliseconds: 1
        )
        XCTAssertEqual(secondHeaderRecovered?.events.map(\.eventID), ["first"])
    }

    func testIncidentJournalRejectsHeaderAndEventIdentityMismatch() throws {
        let codec = ObservabilityStoreRecordCodec()
        let header = try codec.encodedRecord(.header(
            incident(id: "header-id", sessionID: "journal-session")
        ))
        XCTAssertNil(codec.decodeIncident(
            header,
            expectedIncidentID: "file-name-id",
            currentSessionID: "journal-session",
            nowMilliseconds: 1
        ))

        var mismatched = event(id: "mismatch", timestamp: 1, sessionID: "journal-session")
        mismatched.incidentID = "other-incident"
        let mismatchedData = try header + (codec.encodedRecord(.event("header-id", mismatched)))
        let recovered = codec.decodeIncident(
            mismatchedData,
            expectedIncidentID: "header-id",
            currentSessionID: "journal-session",
            nowMilliseconds: 1
        )
        XCTAssertTrue(recovered?.events.isEmpty == true)
    }
}

private extension RollingObservabilityStoreBehaviorTests {
    func assertUnownedExpiredCandidatesSurvive(
        in logsURL: URL,
        store: inout RollingObservabilityStore,
        configuration: AppObservabilityConfiguration
    ) throws {
        let expired = logsURL.appendingPathComponent("events-00000000000000009999.jsonl")
        let lookalike = logsURL.appendingPathComponent("events-expired.jsonl")
        try Data("{}\n".utf8).write(to: expired)
        try Data("preserve\n".utf8).write(to: lookalike)
        for url in [expired, lookalike] {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: -10000)],
                ofItemAtPath: url.path
            )
        }
        try store.prepare(configuration: configuration)
        XCTAssertEqual(try Data(contentsOf: expired), Data("{}\n".utf8))
        XCTAssertEqual(try String(contentsOf: lookalike, encoding: .utf8), "preserve\n")
        XCTAssertLessThanOrEqual(store.usageBytes, configuration.diskBudgetBytes)
    }

    func assertUnsupportedSchema(
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? ObservabilityStoreError, .unsupportedSchema, file: file, line: line)
        }
    }

    func appendRecoveryAttackRecords(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let records = recoveryAttackEvents().map {
            ObservabilityIncidentRecord.event("sanitized-recovery", $0)
        }
        var data = Data()
        for record in records {
            let encoded = try encoder.encode(record)
            data.append(encoded)
            data.append(0x0A)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    func recoveryAttackEvents() -> [ObservabilityEventSnapshot] {
        var legacy = event(id: "valid-legacy", timestamp: 4_000_001, sessionID: "first-session")
        legacy.schemaVersion = 1
        legacy.buildContext = nil
        legacy.incidentID = "sanitized-recovery"

        var prohibited = event(id: "prohibited", timestamp: 4_000_002, sessionID: "first-session")
        prohibited.privacy = "prohibited"
        prohibited.incidentID = "sanitized-recovery"

        var underclassified = event(id: "underclassified", timestamp: 4_000_003, sessionID: "first-session")
        underclassified.incidentID = "sanitized-recovery"
        underclassified.resources = [ObservabilityResourceSnapshot(
            resourceID: "resource-id",
            alias: "file.0123456789abcdef01234567",
            pathExtension: "txt",
            sizeBucket: "lt_1mb",
            storageMode: "copied"
        )]

        var invalidBuild = event(id: "invalid-build", timestamp: 4_000_004, sessionID: "first-session")
        invalidBuild.buildContext?.producer = "untrusted_producer"
        invalidBuild.incidentID = "sanitized-recovery"
        return [legacy, prohibited, underclassified, invalidBuild]
    }
}
