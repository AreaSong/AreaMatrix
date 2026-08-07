@testable import AreaMatrix
import Foundation
import XCTest

final class ExternalWatcherLifecycleTests: XCTestCase {
    @MainActor
    func testWatcherStartIgnoresStaleCursorReadAfterRepositorySwitch() async throws {
        let root = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherGenerationTests")
        defer { removeTestTemporaryItems(root) }
        let repoA = root.appendingPathComponent("repo-a", isDirectory: true)
        let repoB = root.appendingPathComponent("repo-b", isDirectory: true)
        try FileManager.default.createDirectory(at: repoA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repoB, withIntermediateDirectories: true)
        let syncer = SuspendedCursorExternalChangesSyncer()
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: syncer,
            inFlightTracker: InFlightFileChangeTracker()
        )

        let startA = Task { @MainActor in await watcher.start(repoPath: repoA.path) }
        await syncer.waitUntilCursorRequested(repoPath: repoA.path)
        let startB = Task { @MainActor in await watcher.start(repoPath: repoB.path) }
        await syncer.waitUntilCursorRequested(repoPath: repoB.path)
        await syncer.resumeCursor(repoPath: repoB.path, cursor: 200)
        await startB.value
        await syncer.resumeCursor(repoPath: repoA.path, cursor: 100)
        await startA.value

        XCTAssertEqual(watcher.streamStartEventID, 200)
        watcher.stop()
    }

    @MainActor
    func testWatcherStopInvalidatesSuspendedStart() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherStopGenerationTests")
        defer { removeTestTemporaryItems(repoURL) }
        let syncer = SuspendedCursorExternalChangesSyncer()
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: syncer,
            inFlightTracker: InFlightFileChangeTracker()
        )

        let start = Task { @MainActor in await watcher.start(repoPath: repoURL.path) }
        await syncer.waitUntilCursorRequested(repoPath: repoURL.path)
        watcher.stop()
        await syncer.resumeCursor(repoPath: repoURL.path, cursor: 100)
        await start.value

        XCTAssertNil(watcher.streamStartEventID)
        XCTAssertNil(watcher.recoveryRequest)
    }

    @MainActor
    func testStartsFromCursorAndRequestsRescanWhenCursorIsMissing() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherCursorTests")
        defer { removeTestTemporaryItems(repoURL) }

        let cursorWatcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 42),
            inFlightTracker: InFlightFileChangeTracker()
        )
        await cursorWatcher.start(repoPath: repoURL.path)

        XCTAssertEqual(cursorWatcher.streamStartEventID, 42)
        XCTAssertNil(cursorWatcher.recoveryRequest)
        cursorWatcher.stop()

        let missingCursorWatcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: nil),
            inFlightTracker: InFlightFileChangeTracker()
        )
        await missingCursorWatcher.start(repoPath: repoURL.path)

        XCTAssertNil(missingCursorWatcher.streamStartEventID)
        XCTAssertEqual(missingCursorWatcher.recoveryRequest?.kind, .rescanRequired)
        XCTAssertEqual(missingCursorWatcher.recoveryRequest?.repoPath, repoURL.standardizedFileURL.path)
        XCTAssertNotNil(missingCursorWatcher.recoveryRequest?.resumeEventID)
        missingCursorWatcher.stop()
    }

    @MainActor
    func testRoutesRecoveryFlagsAndIgnoresHistoryBoundary() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherRecoveryTests")
        defer { removeTestTemporaryItems(repoURL) }
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 50),
            inFlightTracker: InFlightFileChangeTracker(),
            flushDelay: .milliseconds(1)
        )
        await watcher.start(repoPath: repoURL.path)

        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: repoURL.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone),
            eventID: 51
        )])
        XCTAssertNil(watcher.recoveryRequest)
        XCTAssertEqual(AreaMatrixExternalCreatedFileRelay.takePendingSignals(), [])

        let rescanFlags = [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped,
            kFSEventStreamEventFlagEventIdsWrapped
        ]
        for (offset, flag) in rescanFlags.enumerated() {
            await watcher.start(repoPath: repoURL.path)
            watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
                path: repoURL.path,
                flags: FSEventStreamEventFlags(flag),
                eventID: FSEventStreamEventId(52 + offset)
            )])
            XCTAssertEqual(watcher.recoveryRequest?.kind, .rescanRequired)
            XCTAssertNil(watcher.streamStartEventID)
        }

        await watcher.start(repoPath: repoURL.path)
        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: repoURL.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged),
            eventID: 56
        )])
        XCTAssertEqual(watcher.recoveryRequest?.kind, .rootChanged)
        XCTAssertNil(watcher.streamStartEventID)
        watcher.stop()
    }

    @MainActor
    func testCoalescesBurstAndPublishesEventIDOrder() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherBurstTests")
        defer { removeTestTemporaryItems(repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let firstURL = docsURL.appendingPathComponent("first.pdf")
        let secondURL = docsURL.appendingPathComponent("second.pdf")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()

        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 100),
            inFlightTracker: InFlightFileChangeTracker(),
            flushDelay: .milliseconds(1)
        )
        await watcher.start(repoPath: repoURL.path)
        watcher.handle(events: [
            MainExternalCreatedFileWatcherEvent(
                path: firstURL.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                eventID: 200
            ),
            MainExternalCreatedFileWatcherEvent(
                path: secondURL.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
                eventID: 150
            ),
            MainExternalCreatedFileWatcherEvent(
                path: firstURL.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified),
                eventID: 250
            )
        ])

        let observedSignals = await waitForWatcherSignals(failureMessage: "Timed out waiting for watcher burst flush")
        let signals = try XCTUnwrap(observedSignals)
        let expectedModified = try XCTUnwrap(MainExternalCreatedFileSignal(
            kind: .modified,
            repoPath: repoURL.path,
            relativePath: "docs/second.pdf",
            fsEventID: 150,
            cursorWatermark: 250
        ))
        let expectedCreated = try XCTUnwrap(MainExternalCreatedFileSignal(
            kind: .created,
            repoPath: repoURL.path,
            relativePath: "docs/first.pdf",
            fsEventID: 250,
            cursorWatermark: 250
        ))
        XCTAssertEqual(signals, [expectedModified, expectedCreated])
        watcher.stop()
    }

    @MainActor
    func testFiltersInFlightPathsWithoutDroppingOtherEvents() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherInFlightTests")
        defer { removeTestTemporaryItems(repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let filteredURL = docsURL.appendingPathComponent("filtered.pdf")
        let deliveredURL = docsURL.appendingPathComponent("delivered.pdf")
        try Data("filtered".utf8).write(to: filteredURL)
        try Data("delivered".utf8).write(to: deliveredURL)
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()

        let tracker = InFlightFileChangeTracker()
        await tracker.mark(repoPath: repoURL.path, relativePath: "docs/filtered.pdf")
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 300),
            inFlightTracker: tracker,
            flushDelay: .milliseconds(1)
        )
        await watcher.start(repoPath: repoURL.path)
        watcher.handle(events: [
            MainExternalCreatedFileWatcherEvent(
                path: filteredURL.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                eventID: 303
            ),
            MainExternalCreatedFileWatcherEvent(
                path: deliveredURL.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                eventID: 302
            )
        ])

        let observedSignals = await waitForWatcherSignals(
            failureMessage: "Timed out waiting for in-flight filtered watcher flush"
        )
        let signals = try XCTUnwrap(observedSignals)
        let expectedSignal = try XCTUnwrap(MainExternalCreatedFileSignal(
            repoPath: repoURL.path,
            relativePath: "docs/delivered.pdf",
            fsEventID: 302,
            cursorWatermark: 303
        ))
        XCTAssertEqual(signals, [expectedSignal])
        await tracker.unmark(repoPath: repoURL.path, relativePath: "docs/filtered.pdf")
        watcher.stop()
    }

    @MainActor
    func testFilteredOnlyBatchPublishesOrderedAckWindowWithoutWritingCursorDirectly() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherFilteredCursorTests")
        defer { removeTestTemporaryItems(repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let filteredURL = docsURL.appendingPathComponent("filtered.pdf")
        try Data("filtered".utf8).write(to: filteredURL)
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()

        let tracker = InFlightFileChangeTracker()
        await tracker.mark(repoPath: repoURL.path, relativePath: "docs/filtered.pdf")
        let syncer = RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 400)
        let watcher = MainExternalCreatedFileWatcher(
            cursorStore: syncer,
            inFlightTracker: tracker,
            flushDelay: .milliseconds(1)
        )
        await watcher.start(repoPath: repoURL.path)
        watcher.handle(events: [MainExternalCreatedFileWatcherEvent(
            path: filteredURL.path,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
            eventID: 401
        )])

        try await Task.sleep(for: .milliseconds(20))
        await syncer.assertCursorWrites([])
        let windows = AreaMatrixExternalCreatedFileRelay.takePendingWindows(matchingRepoPath: repoURL.path)
        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows.first?.cursorWatermark, 401)
        XCTAssertEqual(windows.first?.events, [])
        watcher.stop()
    }

    @MainActor
    private func waitForWatcherSignals(failureMessage: String) async -> [MainExternalCreatedFileSignal]? {
        await waitForMainActorTestValue(
            attempts: 100,
            delayNanoseconds: 1_000_000,
            failureMessage: { failureMessage },
            value: {
                let signals = AreaMatrixExternalCreatedFileRelay.takePendingSignals()
                return signals.isEmpty ? nil : signals
            }
        )
    }
}
