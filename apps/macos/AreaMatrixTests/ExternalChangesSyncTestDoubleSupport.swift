@testable import AreaMatrix
import XCTest

private struct ExternalSyncCall: Equatable {
    var kind: MainExternalSyncEventKind
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

actor RecordingExternalChangesSyncer: CoreExternalChangesSyncing {
    private let result: Swift.Result<SyncResultSnapshot, Error>
    private var calls: [ExternalSyncCall] = []
    private var batches: [[ExternalSyncCall]] = []
    private var cursor: Int64?
    private var cursorWrites: [Int64] = []

    init(result: Swift.Result<SyncResultSnapshot, Error>, cursor: Int64? = 1) {
        self.result = result
        self.cursor = cursor
    }

    func syncExternalChanges(
        repoPath: String,
        events: [MainExternalCreatedFileEvent]
    ) async throws -> SyncResultSnapshot {
        let batch = events.map {
            ExternalSyncCall(
                kind: $0.kind,
                repoPath: repoPath,
                relativePath: $0.relativePath,
                fsEventID: $0.fsEventID
            )
        }
        batches.append(batch)
        calls.append(contentsOf: batch)
        return try result.get()
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        cursor
    }

    func setFSEventCursor(repoPath _: String, lastEventID: Int64) async throws {
        cursor = lastEventID
        cursorWrites.append(lastEventID)
    }

    func recordedCursorWrites() -> [Int64] {
        cursorWrites
    }

    func assertSyncedExternalEvents(
        repoPath: String,
        events: [MainExternalCreatedFileEvent],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedBatch = events.map {
            ExternalSyncCall(
                kind: $0.kind,
                repoPath: repoPath,
                relativePath: $0.relativePath,
                fsEventID: $0.fsEventID
            )
        }
        XCTAssertEqual(batches, [expectedBatch], file: file, line: line)
    }

    func assertSyncedExternalEvent(
        kind: MainExternalSyncEventKind,
        repoPath: String,
        relativePath: String,
        fsEventID: Int64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            calls,
            [ExternalSyncCall(
                kind: kind,
                repoPath: repoPath,
                relativePath: relativePath,
                fsEventID: fsEventID
            )],
            file: file,
            line: line
        )
    }

    func assertSyncedCreated(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSyncedExternalEvent(
            kind: .created,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID,
            file: file,
            line: line
        )
    }

    func assertSyncedRenamed(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSyncedExternalEvent(
            kind: .renamed,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID,
            file: file,
            line: line
        )
    }

    func assertSyncedRemoved(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSyncedExternalEvent(
            kind: .removed,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID,
            file: file,
            line: line
        )
    }

    func assertSyncedRemoved(
        repoPath: String,
        relativePath: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(calls.count, 1, file: file, line: line)
        guard let call = calls.first else { return }

        XCTAssertEqual(call.kind, .removed, file: file, line: line)
        XCTAssertEqual(call.repoPath, repoPath, file: file, line: line)
        XCTAssertEqual(call.relativePath, relativePath, file: file, line: line)
        XCTAssertGreaterThan(call.fsEventID, 0, file: file, line: line)
    }

    func assertNoExternalSyncRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(calls, [], file: file, line: line)
    }

    func assertCursorWrites(
        _ expected: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(cursorWrites, expected, file: file, line: line)
    }
}
