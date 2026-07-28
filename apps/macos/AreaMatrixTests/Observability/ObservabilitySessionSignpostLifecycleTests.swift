import AppKit
@testable import AreaMatrix
import XCTest

final class ObservabilitySessionLifecycleStoreTests: XCTestCase {
    func testSessionMarkerClassifiesMissingCleanInterruptedAndCorrupt() throws {
        let fixture = try SessionMarkerFixture()
        defer { fixture.cleanup() }

        let missingStore = ObservabilitySessionLifecycleStore(rootURL: fixture.root("missing"))
        XCTAssertEqual(
            try missingStore.beginSession(sessionID: "session-a", nowMilliseconds: 10),
            .missing
        )

        let cleanStore = ObservabilitySessionLifecycleStore(rootURL: fixture.root("clean"))
        _ = try cleanStore.beginSession(sessionID: "session-a", nowMilliseconds: 10)
        try cleanStore.closeSession(
            sessionID: "session-a",
            startedAtMilliseconds: 10,
            nowMilliseconds: 20
        )
        guard case let .clean(marker) = try cleanStore.beginSession(
            sessionID: "session-b",
            nowMilliseconds: 30
        ) else {
            return XCTFail("Expected a clean previous session")
        }
        XCTAssertEqual(marker.sessionID, "session-a")
        XCTAssertEqual(marker.state, .closed)

        let interruptedStore = ObservabilitySessionLifecycleStore(rootURL: fixture.root("interrupted"))
        _ = try interruptedStore.beginSession(sessionID: "session-a", nowMilliseconds: 10)
        guard case let .interrupted(marker) = try interruptedStore.beginSession(
            sessionID: "session-b",
            nowMilliseconds: 20
        ) else {
            return XCTFail("Expected an interrupted previous session")
        }
        XCTAssertEqual(marker.sessionID, "session-a")

        let corruptRoot = fixture.root("corrupt")
        try fixture.write(Data("{".utf8), to: corruptRoot)
        let corruptStore = ObservabilitySessionLifecycleStore(rootURL: corruptRoot)
        XCTAssertEqual(
            try corruptStore.beginSession(sessionID: "session-b", nowMilliseconds: 20),
            .corrupt
        )
    }

    func testSessionMarkerRejectsUnsupportedOversizedAndInvalidStateCombinations() throws {
        let fixture = try SessionMarkerFixture()
        defer { fixture.cleanup() }

        try assertCorrupt(
            marker: marker(schemaVersion: 2, state: .running),
            root: fixture.root("unsupported"),
            fixture: fixture
        )

        let oversizedRoot = fixture.root("oversized")
        try fixture.write(Data(repeating: 0x41, count: 16 * 1024 + 1), to: oversizedRoot)
        XCTAssertEqual(
            try ObservabilitySessionLifecycleStore(rootURL: oversizedRoot)
                .beginSession(sessionID: "current", nowMilliseconds: 30),
            .corrupt
        )

        let invalidMarkers = [
            marker(state: .closed, closedAtMilliseconds: nil),
            marker(sessionID: "current", state: .closed, closedAtMilliseconds: nil),
            marker(state: .closed, closedAtMilliseconds: 9),
            marker(state: .closed, closedAtMilliseconds: -1),
            marker(state: .running, closedAtMilliseconds: 20),
            marker(sessionID: "", state: .running),
            marker(startedAtMilliseconds: -1, state: .running)
        ]
        for (index, invalidMarker) in invalidMarkers.enumerated() {
            try assertCorrupt(
                marker: invalidMarker,
                root: fixture.root("invalid-\(index)"),
                fixture: fixture
            )
        }
    }

    func testStaleCloseCannotOverwriteNewerRunningSession() throws {
        let fixture = try SessionMarkerFixture()
        defer { fixture.cleanup() }
        let store = ObservabilitySessionLifecycleStore(rootURL: fixture.root("stale-close"))

        _ = try store.beginSession(sessionID: "session-a", nowMilliseconds: 10)
        _ = try store.beginSession(sessionID: "session-b", nowMilliseconds: 20)
        try store.closeSession(
            sessionID: "session-a",
            startedAtMilliseconds: 10,
            nowMilliseconds: 30
        )

        guard case let .interrupted(marker) = try store.beginSession(
            sessionID: "session-c",
            nowMilliseconds: 40
        ) else {
            return XCTFail("A stale close must preserve the newer running session")
        }
        XCTAssertEqual(marker.sessionID, "session-b")
        XCTAssertEqual(marker.state, .running)
    }

    func testCloseSessionWritesExactMarkerWithRestrictedPermissions() throws {
        let fixture = try SessionMarkerFixture()
        defer { fixture.cleanup() }
        let root = fixture.root("closed-marker")
        let store = ObservabilitySessionLifecycleStore(rootURL: root)

        _ = try store.beginSession(sessionID: "session-a", nowMilliseconds: 10)
        try store.closeSession(
            sessionID: "session-a",
            startedAtMilliseconds: 10,
            nowMilliseconds: 20
        )

        XCTAssertEqual(
            try fixture.readMarker(from: root),
            marker(
                sessionID: "session-a",
                startedAtMilliseconds: 10,
                state: .closed,
                closedAtMilliseconds: 20
            )
        )
        XCTAssertEqual(try fixture.markerPermissions(in: root), 0o600)
    }

    func testNilRootSessionStoreIsAnExplicitNoOp() throws {
        let store = ObservabilitySessionLifecycleStore(rootURL: nil)
        XCTAssertEqual(
            try store.beginSession(sessionID: "session", nowMilliseconds: 10),
            .missing
        )
        XCTAssertNoThrow(try store.closeSession(
            sessionID: "session",
            startedAtMilliseconds: 10,
            nowMilliseconds: 20
        ))
    }

    private func assertCorrupt(
        marker: ObservabilitySessionMarker,
        root: URL,
        fixture: SessionMarkerFixture
    ) throws {
        try fixture.write(JSONEncoder().encode(marker), to: root)
        XCTAssertEqual(
            try ObservabilitySessionLifecycleStore(rootURL: root)
                .beginSession(sessionID: "current", nowMilliseconds: 30),
            .corrupt
        )
    }

    private func marker(
        schemaVersion: Int = 1,
        sessionID: String = "previous",
        startedAtMilliseconds: Int64 = 10,
        state: ObservabilitySessionMarker.State,
        closedAtMilliseconds: Int64? = nil
    ) -> ObservabilitySessionMarker {
        ObservabilitySessionMarker(
            schemaVersion: schemaVersion,
            sessionID: sessionID,
            startedAtMilliseconds: startedAtMilliseconds,
            closedAtMilliseconds: closedAtMilliseconds,
            state: state
        )
    }
}

private final class SessionMarkerFixture {
    private let baseURL: URL

    init() throws {
        baseURL = try makeTestTemporaryDirectory(named: "areamatrix-session-marker")
    }

    func root(_ name: String) -> URL {
        baseURL.appendingPathComponent(name, isDirectory: true)
    }

    func write(_ data: Data, to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: root.appendingPathComponent("session-marker.json"))
    }

    func readMarker(from root: URL) throws -> ObservabilitySessionMarker {
        let data = try Data(contentsOf: root.appendingPathComponent("session-marker.json"))
        return try JSONDecoder().decode(ObservabilitySessionMarker.self, from: data)
    }

    func markerPermissions(in root: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appendingPathComponent("session-marker.json").path
        )
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
    }

    func cleanup() {
        removeTestTemporaryItems(baseURL)
    }
}
