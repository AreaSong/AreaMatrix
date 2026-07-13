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

    init(result: Swift.Result<SyncResultSnapshot, Error>) {
        self.result = result
    }

    func syncExternalCreated(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        try recordAndResolve(kind: .created, repoPath: repoPath, relativePath: relativePath, fsEventID: fsEventID)
    }

    func syncExternalRenamed(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        try recordAndResolve(kind: .renamed, repoPath: repoPath, relativePath: relativePath, fsEventID: fsEventID)
    }

    func syncExternalRemoved(
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) async throws -> SyncResultSnapshot {
        try recordAndResolve(kind: .removed, repoPath: repoPath, relativePath: relativePath, fsEventID: fsEventID)
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        nil
    }

    func setFSEventCursor(repoPath _: String, lastEventID _: Int64) async throws {}

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

    private func recordAndResolve(
        kind: MainExternalSyncEventKind,
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) throws -> SyncResultSnapshot {
        calls.append(ExternalSyncCall(
            kind: kind,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        return try result.get()
    }
}
