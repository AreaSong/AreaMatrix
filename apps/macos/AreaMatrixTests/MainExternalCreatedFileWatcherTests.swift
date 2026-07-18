@testable import AreaMatrix
import Foundation
import XCTest

final class MainExternalCreatedFileWatcherTests: XCTestCase {
    @MainActor
    func testStartsFromCursorAndRequestsRescanWhenCursorIsMissing() async throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixExternalWatcherCursorTests")
        defer { removeTestTemporaryItems(repoURL) }

        let cursorWatcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: 42)
        )
        await cursorWatcher.start(repoPath: repoURL.path)

        XCTAssertEqual(cursorWatcher.streamStartEventID, 42)
        XCTAssertNil(cursorWatcher.recoveryRequest)
        cursorWatcher.stop()

        let missingCursorWatcher = MainExternalCreatedFileWatcher(
            cursorStore: RecordingExternalChangesSyncer(result: .success(.createdFixture()), cursor: nil)
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
    func testFilteredOnlyBatchAdvancesCursorWithoutPublishingSignal() async throws {
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
        watcher.handle(events: [
            MainExternalCreatedFileWatcherEvent(
                path: filteredURL.path,
                flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated),
                eventID: 401
            )
        ])

        try await Task.sleep(for: .milliseconds(20))
        await syncer.assertCursorWrites([401])
        XCTAssertEqual(AreaMatrixExternalCreatedFileRelay.takePendingSignals(), [])
        watcher.stop()
    }

    @MainActor
    func testPendingQueueKeepsDistinctPathsAndLatestPathEvent() throws {
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            model: makeShellOnboardingModel()
        )
        let signals = try [
            XCTUnwrap(MainExternalCreatedFileSignal(
                repoPath: "/tmp/repo",
                relativePath: "docs/second.pdf",
                fsEventID: 320
            )),
            XCTUnwrap(MainExternalCreatedFileSignal(
                repoPath: "/tmp/repo",
                relativePath: "docs/first.pdf",
                fsEventID: 310
            )),
            XCTUnwrap(MainExternalCreatedFileSignal(
                kind: .modified,
                repoPath: "/tmp/repo",
                relativePath: "docs/first.pdf",
                fsEventID: 330
            ))
        ]

        XCTAssertTrue(fixture.model.handleExternalCreatedFiles(signals))
        XCTAssertEqual(fixture.model.externalCreatedEvents(for: fixture.opening), [
            MainExternalCreatedFileEvent(
                kind: .created,
                relativePath: "docs/second.pdf",
                fsEventID: 320
            ),
            MainExternalCreatedFileEvent(
                kind: .modified,
                relativePath: "docs/first.pdf",
                fsEventID: 330
            )
        ])
    }

    @MainActor
    func testRescanRecoveryClearsPendingEventsAndRoutesToRepair() throws {
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            model: makeShellOnboardingModel()
        )
        let signal = try XCTUnwrap(MainExternalCreatedFileSignal(
            repoPath: "/tmp/repo",
            relativePath: "docs/pending.pdf",
            fsEventID: 350
        ))
        XCTAssertTrue(fixture.model.handleExternalCreatedFile(signal))

        fixture.model.handleExternalWatcherRecovery(MainExternalWatcherRecoveryRequest(
            kind: .rescanRequired,
            repoPath: "/tmp/repo",
            resumeEventID: 351,
            reason: "history unavailable"
        ))

        XCTAssertEqual(fixture.model.externalCreatedEvents(for: fixture.opening), [])
        XCTAssertEqual(fixture.model.pendingWatcherRescanSeed?.repoPath, "/tmp/repo")
        XCTAssertEqual(fixture.model.pendingWatcherRescanSeed?.eventID, 351)
        guard case let .dbRepairConfirm(route) = fixture.model.route else {
            return XCTFail("Expected watcher recovery to route to repository repair")
        }
        XCTAssertEqual(route.repoPath, "/tmp/repo")
    }

    @MainActor
    func testRootChangedRecoveryRoutesToRepositoryReconnectError() {
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            model: makeShellOnboardingModel()
        )

        fixture.model.handleExternalWatcherRecovery(MainExternalWatcherRecoveryRequest(
            kind: .rootChanged,
            repoPath: "/tmp/repo",
            resumeEventID: nil,
            reason: "root moved"
        ))

        guard case let .mainRepoError(repoPath, mapping) = fixture.model.route else {
            return XCTFail("Expected watcher root change to route to repository error")
        }
        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(mapping?.kind, .fileNotFound)
        XCTAssertEqual(mapping?.recoverability, .userActionRequired)
    }

    func testInFlightTrackerUsesReferenceCountsAndTTL() async {
        let tracker = InFlightFileChangeTracker(ttl: 0.02)
        await tracker.mark(repoPath: "/tmp/repo/./", relativePath: " docs/file.pdf ")
        await tracker.mark(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        await tracker.unmark(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")

        let remainsInFlight = await tracker.contains(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        XCTAssertTrue(remainsInFlight)
        await tracker.unmark(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        let remainsDuringGrace = await tracker.contains(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        XCTAssertTrue(remainsDuringGrace)
        try? await Task.sleep(for: .milliseconds(40))
        let expiredAfterGrace = await tracker.contains(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        XCTAssertFalse(expiredAfterGrace)

        let expiredTracker = InFlightFileChangeTracker(ttl: 0)
        await expiredTracker.mark(repoPath: "/tmp/repo", relativePath: "docs/expired.pdf")
        let expired = await expiredTracker.contains(repoPath: "/tmp/repo", relativePath: "docs/expired.pdf")
        XCTAssertFalse(expired)
    }

    @MainActor
    func testSubmitsBurstAsSingleCoreBatch() async throws {
        var created = FileEntrySnapshot.detailMetaFixture(id: 26, currentName: "created.pdf")
        created.origin = "External"
        var modified = FileEntrySnapshot.detailMetaFixture(id: 27, currentName: "modified.pdf")
        modified.origin = "External"
        let events = try [
            XCTUnwrap(MainExternalCreatedFileEvent(
                kind: .created,
                relativePath: created.path,
                fsEventID: 340
            )),
            XCTUnwrap(MainExternalCreatedFileEvent(
                kind: .modified,
                relativePath: modified.path,
                fsEventID: 341,
                cursorWatermark: 342
            ))
        ]
        let syncer = RecordingExternalChangesSyncer(result: .success(SyncResultSnapshot(
            detectedCreates: 1,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 1,
            errors: []
        )))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            fileLister: RecordingFileLister(files: [created, modified]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(modified)),
            changeLogLister: DetailLogRecordingLister(results: [.success([
                .detailLogFixture(fileID: modified.id, action: "external_modified")
            ])]),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        let synced = await model.syncExternalChanges(events)
        XCTAssertTrue(synced)
        await syncer.assertSyncedExternalEvents(repoPath: "/tmp/repo", events: events)
        await syncer.assertCursorWrites([342])
        XCTAssertEqual(model.selection, .single(modified.id))
    }

    @MainActor
    func testNoOpExternalBatchCompletesWithoutSelectingIgnoredPath() async throws {
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .modified,
            relativePath: "docs/report.pdf.md",
            fsEventID: 350
        ))
        let syncer = RecordingExternalChangesSyncer(result: .success(SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: []
        )))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            fileLister: RecordingFileLister(files: []),
            fileDetailer: RecordingFileDetailer(results: []),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        let synced = await model.syncExternalChanges([event])

        XCTAssertTrue(synced)
        XCTAssertEqual(model.selection, MainFileSelectionState.none)
        await syncer.assertSyncedExternalEvents(repoPath: "/tmp/repo", events: [event])
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
