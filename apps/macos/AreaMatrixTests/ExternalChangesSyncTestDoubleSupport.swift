@testable import AreaMatrix
import XCTest

private struct ExternalSyncCall: Equatable {
    var kind: MainExternalSyncEventKind
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

actor RecordingExternalChangesSyncer: CoreExternalChangesSyncing {
    private var results: [Swift.Result<SyncResultSnapshot, Error>]
    private var calls: [ExternalSyncCall] = []
    private var batches: [[ExternalSyncCall]] = []
    private var cursor: Int64?
    private var cursorWrites: [Int64] = []
    private let suspendsSync: Bool
    private var syncContinuations: [CheckedContinuation<Void, Never>] = []
    private var activeSyncCalls = 0
    private var maxConcurrentSyncCalls = 0
    private var cursorWriteResults: [Swift.Result<Void, Error>]

    init(
        result: Swift.Result<SyncResultSnapshot, Error>,
        cursor: Int64? = 1,
        suspendsSync: Bool = false,
        cursorWriteResults: [Swift.Result<Void, Error>] = [.success(())]
    ) {
        results = [result]
        self.cursor = cursor
        self.suspendsSync = suspendsSync
        self.cursorWriteResults = cursorWriteResults
    }

    init(
        results: [Swift.Result<SyncResultSnapshot, Error>],
        cursor: Int64? = 1,
        cursorWriteResults: [Swift.Result<Void, Error>] = [.success(())]
    ) {
        self.results = results
        self.cursor = cursor
        suspendsSync = false
        self.cursorWriteResults = cursorWriteResults
    }

    func syncExternalChanges(
        repoPath: String,
        events: [MainExternalCreatedFileEvent]
    ) async throws -> SyncResultSnapshot {
        activeSyncCalls += 1
        maxConcurrentSyncCalls = max(maxConcurrentSyncCalls, activeSyncCalls)
        defer { activeSyncCalls -= 1 }
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
        if suspendsSync {
            await withCheckedContinuation { continuation in
                syncContinuations.append(continuation)
            }
        }
        return try nextSyncResult().get()
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        cursor
    }

    func setFSEventCursor(repoPath _: String, lastEventID: Int64) async throws {
        cursorWrites.append(lastEventID)
        try nextCursorWriteResult().get()
        cursor = lastEventID
    }

    func recordedCursorWrites() -> [Int64] {
        cursorWrites
    }

    func recordedBatchCount() -> Int {
        batches.count
    }

    func recordedMaxConcurrentSyncCalls() -> Int {
        maxConcurrentSyncCalls
    }

    func resumeNextSync() {
        guard !syncContinuations.isEmpty else { return }
        syncContinuations.removeFirst().resume()
    }

    private func nextSyncResult() -> Swift.Result<SyncResultSnapshot, Error> {
        guard let result = results.first else {
            return .failure(CoreError.Internal(message: "No external sync result configured"))
        }
        if results.count > 1 { results.removeFirst() }
        return result
    }

    private func nextCursorWriteResult() -> Swift.Result<Void, Error> {
        guard let result = cursorWriteResults.first else {
            return .failure(CoreError.Internal(message: "No cursor write result configured"))
        }
        if cursorWriteResults.count > 1 { cursorWriteResults.removeFirst() }
        return result
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

actor SuspendedCursorExternalChangesSyncer: CoreExternalChangesSyncing {
    private var requestedRepoPaths: Set<String> = []
    private var continuations: [String: CheckedContinuation<Int64?, Never>] = [:]

    func syncExternalChanges(
        repoPath _: String,
        events _: [MainExternalCreatedFileEvent]
    ) async throws -> SyncResultSnapshot {
        .createdFixture()
    }

    func getFSEventCursor(repoPath: String) async throws -> Int64? {
        let normalized = normalizedRepoPath(repoPath)
        requestedRepoPaths.insert(normalized)
        return await withCheckedContinuation { continuation in
            continuations[normalized] = continuation
        }
    }

    func setFSEventCursor(repoPath _: String, lastEventID _: Int64) async throws {}

    func waitUntilCursorRequested(repoPath: String) async {
        let normalized = normalizedRepoPath(repoPath)
        while !requestedRepoPaths.contains(normalized) {
            await Task.yield()
        }
    }

    func resumeCursor(repoPath: String, cursor: Int64?) {
        continuations.removeValue(forKey: normalizedRepoPath(repoPath))?.resume(returning: cursor)
    }

    private func normalizedRepoPath(_ repoPath: String) -> String {
        URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
    }
}

actor SuspendedInFlightFileChangeTracker: InFlightFileChangeTracking {
    private var containsRequestCount = 0
    private var activeContainsCalls = 0
    private var maxConcurrentContainsCalls = 0
    private var containsContinuations: [CheckedContinuation<Bool, Never>] = []

    func mark(repoPath _: String, relativePath _: String) async {}

    func unmark(repoPath _: String, relativePath _: String) async {}

    func contains(repoPath _: String, relativePath _: String) async -> Bool {
        containsRequestCount += 1
        activeContainsCalls += 1
        maxConcurrentContainsCalls = max(maxConcurrentContainsCalls, activeContainsCalls)
        let result = await withCheckedContinuation { continuation in
            containsContinuations.append(continuation)
        }
        activeContainsCalls -= 1
        return result
    }

    func waitUntilContainsRequested() async {
        await waitUntilContainsRequestCount(1)
    }

    func waitUntilContainsRequestCount(_ expected: Int) async {
        while containsRequestCount < expected {
            await Task.yield()
        }
    }

    func resumeContains(_ value: Bool) {
        guard !containsContinuations.isEmpty else { return }
        containsContinuations.removeFirst().resume(returning: value)
    }

    func recordedContainsRequestCount() -> Int {
        containsRequestCount
    }

    func recordedMaxConcurrentContainsCalls() -> Int {
        maxConcurrentContainsCalls
    }
}
