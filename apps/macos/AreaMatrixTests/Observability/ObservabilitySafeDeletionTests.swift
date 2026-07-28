@testable import AreaMatrix
import Darwin
import Foundation
import XCTest

final class ObservabilitySafeDeletionTests: XCTestCase {
    func testDeleteIncidentRemovesOnlySelectedPersistedIncidentAndDoesNotRecoverAfterRestart() async throws {
        let fixture = try makeSafeDeletionFixture()
        defer { fixture.cleanup() }
        let identifiers = TestObservabilityIdentifierSequence(["first", "second"])
        let hub = fixture.makeHub(
            sessionID: "delete-selected-session",
            idGenerator: identifiers.next
        )
        let config = safeDeletionConfiguration()
        await hub.configure(config)
        let firstID = await hub.markIncident(note: nil)
        let secondID = await hub.markIncident(note: nil)

        try await hub.deleteIncident(id: firstID)

        let retained = await hub.incidentSnapshots()
        XCTAssertEqual(retained.map(\.id), [secondID])
        let recoveredHub = fixture.makeHub(sessionID: "restart-session")
        await recoveredHub.configure(config)
        let recovered = await recoveredHub.incidentSnapshots()
        XCTAssertEqual(recovered.map(\.id), [secondID])
    }

    func testDeleteActiveIncidentClearsCaptureAndKeepsOtherIncident() async throws {
        let fixture = try makeSafeDeletionFixture()
        defer { fixture.cleanup() }
        let identifiers = TestObservabilityIdentifierSequence(["retained", "active"])
        let hub = fixture.makeHub(sessionID: "delete-active-session", idGenerator: identifiers.next)
        await hub.configure(safeDeletionConfiguration())
        let retainedID = await hub.markIncident(note: nil)
        let activeID = await hub.markIncident(note: nil)

        try await hub.deleteIncident(id: activeID)

        let incidents = await hub.incidentSnapshots()
        let activeIncidentID = await hub.activeIncidentID()
        XCTAssertEqual(incidents.map(\.id), [retainedID])
        XCTAssertNil(activeIncidentID)
    }

    func testDeleteIncidentPersistenceFailureKeepsIncidentAndActiveStateInMemory() async throws {
        let fixture = try makeSafeDeletionFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 1000)
        let hub = fixture.makeHub(
            sessionID: "delete-failure-session",
            now: { clock.date },
            idGenerator: { "unsafe" }
        )
        await hub.configure(safeDeletionConfiguration())
        let incidentID = await hub.markIncident(note: nil)
        let sentinelURL = try replaceIncidentWithSymlink(fixture: fixture, incidentID: incidentID)

        await XCTAssertThrowsErrorAsync {
            try await hub.deleteIncident(id: incidentID)
        }

        let incidents = await hub.incidentSnapshots()
        let activeIncidentID = await hub.activeIncidentID()
        XCTAssertEqual(incidents.map(\.id), [incidentID])
        XCTAssertEqual(activeIncidentID, incidentID)
        XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("external".utf8))
    }

    func testRemoveLocalLogsUnsafeOwnedEntryKeepsHubMemoryAndIncidents() async throws {
        let fixture = try makeSafeDeletionFixture()
        defer { fixture.cleanup() }
        let clock = TestObservabilityClock(milliseconds: 2000)
        let hub = fixture.makeHub(
            sessionID: "remove-all-failure-session",
            now: { clock.date },
            idGenerator: { "unsafe-all" }
        )
        await hub.configure(safeDeletionConfiguration())
        let event = safeDeletionEvent(id: "memory-event", sessionID: "remove-all-failure-session")
        await hub.ingestCoreEvent(event)
        let eventsBeforeDeletion = await hub.recentEvents()
        XCTAssertEqual(eventsBeforeDeletion.map(\.eventID), [event.eventID])
        let incidentID = await hub.markIncident(note: nil)
        let eventURL = try XCTUnwrap(try ownedEventURLs(in: fixture.logsURL).first)
        let sentinelURL = try replaceIncidentWithSymlink(fixture: fixture, incidentID: incidentID)

        await XCTAssertThrowsErrorAsync {
            try await hub.removeLocalLogs()
        }

        let events = await hub.recentEvents()
        let incidents = await hub.incidentSnapshots()
        let activeIncidentID = await hub.activeIncidentID()
        XCTAssertEqual(events.map(\.eventID), [event.eventID])
        XCTAssertEqual(incidents.map(\.id), [incidentID])
        XCTAssertEqual(activeIncidentID, incidentID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: eventURL.path))
        XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("external".utf8))
    }

    func testSafeRemoveRejectsSymlinkHardlinkFIFOAndDirectory() throws {
        for hostileKind in SafeDeletionHostileEntryKind.allCases {
            try assertSafeRemoveRejects(hostileKind)
        }
    }

    func testSafeRemoveRejectsRootAndIncidentsDirectoryReplacement() throws {
        try assertRootDirectoryReplacementIsRejected()
        try assertIncidentsDirectoryReplacementIsRejected()
    }

    func testRemoveAllLogsPreservesUnknownFilesAndExternalSentinel() throws {
        let fixture = try makeSafeDeletionFixture()
        defer { fixture.cleanup() }
        let config = safeDeletionConfiguration()
        var store = RollingObservabilityStore(rootURL: fixture.logsURL)
        try store.prepare(configuration: config)
        let managedEventURL = try XCTUnwrap(try ownedEventURLs(in: fixture.logsURL).first)
        try store.append(safeDeletionEvent(id: "owned", sessionID: "store-session"), configuration: config)
        try store.beginIncident(
            safeDeletionIncident(id: "owned", sessionID: "store-session"),
            configuration: config
        )
        let unknownURL = fixture.logsURL.appendingPathComponent("user-note.txt")
        let hiddenURL = fixture.logsURL.appendingPathComponent(".events-hidden.jsonl")
        let lookalikeURL = fixture.logsURL.appendingPathComponent("events-user-note.jsonl")
        let incidentUnknownURL = fixture.incidentsURL.appendingPathComponent("README.md")
        let externalSentinelURL = fixture.rootURL.appendingPathComponent("outside-sentinel.txt")
        for url in [unknownURL, hiddenURL, lookalikeURL, incidentUnknownURL, externalSentinelURL] {
            try Data("preserved".utf8).write(to: url)
        }

        try store.removeAllLogs()

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedEventURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.incidentURL(id: "owned").path))
        for url in [unknownURL, hiddenURL, lookalikeURL, incidentUnknownURL, externalSentinelURL] {
            XCTAssertEqual(try Data(contentsOf: url), Data("preserved".utf8))
        }
        XCTAssertEqual(store.usageBytes, 0)
    }
}

private enum SafeDeletionHostileEntryKind: CaseIterable {
    case symbolicLink
    case hardLink
    case fifo
    case directory

    func install(at url: URL, sentinelURL: URL) throws {
        switch self {
        case .symbolicLink:
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: sentinelURL)
        case .hardLink:
            try FileManager.default.linkItem(at: sentinelURL, to: url)
        case .fifo:
            guard mkfifo(url.path, 0o600) == 0 else { throw CocoaError(.fileWriteUnknown) }
        case .directory:
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
    }
}

private struct SafeDeletionFixture {
    let rootURL: URL
    let logsURL: URL
    let suiteName: String
    let defaults: UserDefaults

    var incidentsURL: URL {
        logsURL.appendingPathComponent("incidents", isDirectory: true)
    }

    func incidentURL(id: String) -> URL {
        incidentsURL.appendingPathComponent("incident-\(id).jsonl", isDirectory: false)
    }

    func makeHub(
        sessionID: String,
        now: @escaping @Sendable () -> Date = Date.init,
        idGenerator: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) -> ObservabilityHub {
        ObservabilityHub(
            configurationStore: ObservabilityConfigurationStore(defaults: defaults),
            rootURL: logsURL,
            sessionID: sessionID,
            expectedCoreBuildContext: observabilityTestCoreBuildContext(),
            now: now,
            idGenerator: idGenerator
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        removeTestTemporaryItems(rootURL)
    }
}

private func makeSafeDeletionFixture() throws -> SafeDeletionFixture {
    let rootURL = try makeTestTemporaryDirectory(named: "ObservabilitySafeDeletionTests")
    let suiteName = "ObservabilitySafeDeletionTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return SafeDeletionFixture(
        rootURL: rootURL,
        logsURL: rootURL.appendingPathComponent("Logs", isDirectory: true),
        suiteName: suiteName,
        defaults: defaults
    )
}

private func assertSafeRemoveRejects(_ hostileKind: SafeDeletionHostileEntryKind) throws {
    let fixture = try makeSafeDeletionFixture()
    defer { fixture.cleanup() }
    let operations = ObservabilitySafeFileOperations(rootURL: fixture.logsURL)
    try operations.prepareDirectories()
    let sentinelURL = fixture.rootURL.appendingPathComponent("outside-\(hostileKind).txt")
    try Data("sentinel".utf8).write(to: sentinelURL)
    let incidentURL = fixture.incidentURL(id: "hostile")
    try hostileKind.install(at: incidentURL, sentinelURL: sentinelURL)

    XCTAssertThrowsError(try operations.remove(
        incidentURL.lastPathComponent,
        kind: .incident(id: "hostile")
    )) { error in
        XCTAssertEqual(error as? ObservabilitySafeFileError, .unsafePath)
    }
    XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("sentinel".utf8))
}

private func assertRootDirectoryReplacementIsRejected() throws {
    let fixture = try makeSafeDeletionFixture()
    defer { fixture.cleanup() }
    let operations = ObservabilitySafeFileOperations(rootURL: fixture.logsURL)
    try operations.prepareDirectories()
    let parkedURL = fixture.rootURL.appendingPathComponent("parked-logs", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.logsURL, to: parkedURL)
    let outsideURL = fixture.rootURL.appendingPathComponent("outside-root", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: false)
    let sentinelURL = outsideURL.appendingPathComponent("events-replaced.jsonl")
    try Data("external-root".utf8).write(to: sentinelURL)
    try FileManager.default.createSymbolicLink(at: fixture.logsURL, withDestinationURL: outsideURL)

    XCTAssertThrowsError(try operations.remove("events-replaced.jsonl", kind: .event))
    XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("external-root".utf8))
}

private func assertIncidentsDirectoryReplacementIsRejected() throws {
    let fixture = try makeSafeDeletionFixture()
    defer { fixture.cleanup() }
    let operations = ObservabilitySafeFileOperations(rootURL: fixture.logsURL)
    try operations.prepareDirectories()
    let parkedURL = fixture.logsURL.appendingPathComponent("parked-incidents", isDirectory: true)
    try FileManager.default.moveItem(at: fixture.incidentsURL, to: parkedURL)
    let outsideURL = fixture.rootURL.appendingPathComponent("outside-incidents", isDirectory: true)
    try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: false)
    let sentinelURL = outsideURL.appendingPathComponent("incident-replaced.jsonl")
    try Data("external-incident".utf8).write(to: sentinelURL)
    try FileManager.default.createSymbolicLink(at: fixture.incidentsURL, withDestinationURL: outsideURL)

    XCTAssertThrowsError(try operations.remove(
        sentinelURL.lastPathComponent,
        kind: .incident(id: "replaced")
    ))
    XCTAssertEqual(try Data(contentsOf: sentinelURL), Data("external-incident".utf8))
}

private func replaceIncidentWithSymlink(
    fixture: SafeDeletionFixture,
    incidentID: String
) throws -> URL {
    let incidentURL = fixture.incidentURL(id: incidentID)
    try FileManager.default.removeItem(at: incidentURL)
    let sentinelURL = fixture.rootURL.appendingPathComponent("external-\(incidentID).txt")
    try Data("external".utf8).write(to: sentinelURL)
    try FileManager.default.createSymbolicLink(at: incidentURL, withDestinationURL: sentinelURL)
    return sentinelURL
}

private func safeDeletionConfiguration() -> AppObservabilityConfiguration {
    AppObservabilityConfiguration(
        mode: .developer,
        minimumSeverity: .trace,
        diskBudgetBytes: 100 * 1024 * 1024,
        retentionHours: 24,
        includeSensitive: false
    )
}

private func safeDeletionEvent(id: String, sessionID: String) -> ObservabilityEventSnapshot {
    ObservabilityEventSnapshot(
        schemaVersion: 2,
        eventID: id,
        wallTimestampMilliseconds: 1,
        monotonicTimestampNanoseconds: 1,
        sequenceNumber: 1,
        sessionID: sessionID,
        incidentID: nil,
        traceID: "trace-\(id)",
        spanID: "span-\(id)",
        parentSpanID: nil,
        operationID: nil,
        retryOfOperationID: nil,
        actionID: "observability.events_dropped",
        componentID: "core.observability.runtime",
        layer: "core",
        phase: "event",
        severity: .info,
        outcome: "succeeded",
        durationMilliseconds: nil,
        resources: [],
        error: nil,
        attributes: [],
        privacy: "public",
        message: nil,
        target: nil,
        threadName: nil,
        buildContext: observabilityTestCoreBuildContext()
    )
}

private func safeDeletionIncident(id: String, sessionID: String) -> ObservabilityIncidentSnapshot {
    ObservabilityIncidentSnapshot(
        id: id,
        sessionID: sessionID,
        markedAtMilliseconds: 1,
        captureEndsAtMilliseconds: 2,
        status: .open,
        note: nil,
        events: [],
        isFrozen: true,
        recoveredAfterRestart: false
    )
}

private func ownedEventURLs(in logsURL: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("events-") && $0.pathExtension == "jsonl" }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        return
    }
}
