@testable import AreaMatrix
import Foundation
import XCTest

final class ExternalWatcherTransitionTests: XCTestCase {
    @MainActor
    func testRepositorySwitchDropsFlushSuspendedForPreviousRepository() async throws {
        let root = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherStaleFlushTests")
        defer { removeTestTemporaryItems(root) }
        let repoA = root.appendingPathComponent("repo-a", isDirectory: true)
        let repoB = root.appendingPathComponent("repo-b", isDirectory: true)
        let fileA = repoA.appendingPathComponent("docs/a.pdf")
        try FileManager.default.createDirectory(
            at: fileA.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: fileA)
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()

        let syncer = RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 500)
        let tracker = SuspendedInFlightFileChangeTracker()
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: syncer,
            inFlightTracker: tracker,
            flushDelay: .milliseconds(0)
        )
        await watcher.start(repoPath: repoA.path)
        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: fileA.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
            eventID: 501
        )])
        await tracker.waitUntilContainsRequested()

        await watcher.start(repoPath: repoB.path)
        await tracker.resumeContains(false)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(
            AreaMatrixExternalCreatedFileRelay.takePendingWindows(matchingRepoPath: repoA.path),
            []
        )
        XCTAssertEqual(watcher.streamStartEventID, 500)
        await syncer.assertCursorWrites([])
        watcher.stop()
    }

    @MainActor
    func testCallbackContextRejectsOldRepositoryEventsAfterSwitch() async throws {
        let repoA = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherCallbackContextTests")
        defer { removeTestTemporaryItems(repoA) }
        let repoB = repoA.appendingPathComponent("repo-b", isDirectory: true)
        let nestedFile = repoB.appendingPathComponent("docs/nested.pdf")
        try FileManager.default.createDirectory(
            at: nestedFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("nested".utf8).write(to: nestedFile)
        let syncer = RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 600)
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: syncer,
            inFlightTracker: InFlightFileChangeTracker(),
            flushDelay: .milliseconds(1)
        )

        await watcher.start(repoPath: repoA.path)
        let staleContext = try XCTUnwrap(watcher.activeCallbackContext)
        XCTAssertEqual(staleContext.repoPath, repoA.standardizedFileURL.path)
        await watcher.start(repoPath: repoB.path)
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()

        staleContext.deliver([
            MainExternalCreatedFileWatcherEvent(
                path: nestedFile.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                eventID: 601
            ),
            MainExternalCreatedFileWatcherEvent(
                path: repoA.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
                eventID: 602
            )
        ])
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(AreaMatrixExternalCreatedFileRelay.takePendingSignals(), [])
        XCTAssertNil(watcher.recoveryRequest)
        XCTAssertEqual(watcher.streamStartEventID, 600)
        await syncer.assertCursorWrites([])
        watcher.stop()
    }

    @MainActor
    func testSingleFlushTaskSerializesBurstArrivingWhileDrainIsSuspended() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherSerialDrainTests")
        defer { removeTestTemporaryItems(repoURL) }
        let firstURL = repoURL.appendingPathComponent("docs/first.pdf")
        let secondURL = repoURL.appendingPathComponent("docs/second.pdf")
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        let tracker = SuspendedInFlightFileChangeTracker()
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 700),
            inFlightTracker: tracker,
            flushDelay: .milliseconds(0)
        )
        await watcher.start(repoPath: repoURL.path)
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()

        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: firstURL.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
            eventID: 701
        )])
        await tracker.waitUntilContainsRequestCount(1)
        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: secondURL.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
            eventID: 702
        )])
        try await Task.sleep(for: .milliseconds(10))

        let requestCountBeforeResume = await tracker.recordedContainsRequestCount()
        let maxConcurrentBeforeResume = await tracker.recordedMaxConcurrentContainsCalls()
        XCTAssertEqual(requestCountBeforeResume, 1)
        XCTAssertEqual(maxConcurrentBeforeResume, 1)
        await tracker.resumeContains(false)
        await tracker.waitUntilContainsRequestCount(2)
        let maxConcurrentAfterResume = await tracker.recordedMaxConcurrentContainsCalls()
        XCTAssertEqual(maxConcurrentAfterResume, 1)
        await tracker.resumeContains(false)

        let signals = await waitForWatcherSignalCount(2)
        XCTAssertEqual(signals.map(\.relativePath), ["docs/first.pdf", "docs/second.pdf"])
        watcher.stop()
    }

    @MainActor
    func testRootChangedInvalidatesFlushSuspendedInInFlightFilter() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherRecoveryFlushTests")
        defer { removeTestTemporaryItems(repoURL) }
        let fileURL = repoURL.appendingPathComponent("docs/pending.pdf")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("pending".utf8).write(to: fileURL)
        let tracker = SuspendedInFlightFileChangeTracker()
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 800),
            inFlightTracker: tracker,
            flushDelay: .milliseconds(0)
        )
        await watcher.start(repoPath: repoURL.path)
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()

        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: fileURL.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
            eventID: 801
        )])
        await tracker.waitUntilContainsRequested()
        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: repoURL.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
            eventID: 802
        )])
        await tracker.resumeContains(false)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(watcher.recoveryRequest?.kind, .rootChanged)
        XCTAssertEqual(AreaMatrixExternalCreatedFileRelay.takePendingSignals(), [])
        watcher.stop()
    }

    @MainActor
    private func waitForWatcherSignalCount(_ expectedCount: Int) async -> [MainExternalCreatedFileSignal] {
        var signals: [MainExternalCreatedFileSignal] = []
        for _ in 0 ..< 100 {
            signals.append(contentsOf: AreaMatrixExternalCreatedFileRelay.takePendingSignals())
            if signals.count >= expectedCount { return signals }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for \(expectedCount) watcher signals")
        return signals
    }
}
