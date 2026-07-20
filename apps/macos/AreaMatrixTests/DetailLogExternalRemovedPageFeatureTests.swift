@testable import AreaMatrix
import XCTest

final class DetailLogExternalRemovedPageFeatureTests: XCTestCase {
    @MainActor
    func testDetailLogSyncExternalRemovedCoreProductionRelayCreatesCurrentMainWindowRemovedEvent() {
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            model: makeShellOnboardingModel()
        )
        let opening = fixture.opening
        let model = fixture.model

        AreaMatrixExternalCreatedFileRelay.publish(
            kind: .removed,
            repoPath: "/tmp/repo",
            relativePath: "docs/removed.pdf",
            fsEventID: 10100
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertEqual(
            model.externalCreatedEvents(for: opening),
            [MainExternalCreatedFileEvent(kind: .removed, relativePath: "docs/removed.pdf", fsEventID: 10100)]
        )
        let handledEvents = model.externalCreatedEvents(for: opening)
        model.finishExternalCreatedFileEvents(handledEvents)
        XCTAssertEqual(model.externalCreatedEvents(for: opening), [])
    }

    func testDetailLogSyncExternalRemovedCoreWatcherBuildsRemovedSignalForUserFileOnly() {
        let removedFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)

        let signal = MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs/removed.pdf",
            flags: removedFlags,
            eventID: 10101
        )

        XCTAssertEqual(signal?.kind, .removed)
        XCTAssertEqual(signal?.repoPath, "/tmp/repo")
        XCTAssertEqual(signal?.relativePath, "docs/removed.pdf")
        XCTAssertEqual(signal?.fsEventID, 10101)
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/.areamatrix/index.db",
            flags: removedFlags,
            eventID: 10102
        ))
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs",
            flags: removedFlags | FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir),
            eventID: 10103
        ))
    }

    @MainActor
    func testDetailLogConsumesSelectedExternalRemovedEventThenRefreshesListAndLog() async throws {
        let removed = FileEntrySnapshot.detailMetaFixture(id: 40, currentName: "removed.pdf")
        let keeper = FileEntrySnapshot.detailMetaFixture(id: 41, currentName: "keeper.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: removed.path,
            fsEventID: 10001
        ))
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: removed.id, action: "deleted")
        let lister = DetailLogRecordingLister(results: [.success([entry])])
        let syncer = DetailLogExternalRemovedSyncer(result: .success(.detailRemovedFixture()))
        let fileLister = DetailLogExternalRemovedLister(files: [keeper])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [removed, keeper]),
            fileLister: fileLister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(removed)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([removed.id])
        await model.syncExternalCreated(event)

        await syncer.assertSyncedRemoved(repoPath: "/tmp/repo", relativePath: removed.path, fsEventID: 10001)
        await fileLister.assertFileListRequests([DetailLogExternalRemovedListRequest(
            repoPath: "/tmp/repo",
            filter: .currentCategory(nil)
        )])
        XCTAssertEqual(model.selection, .single(removed.id))
        XCTAssertEqual(model.files, [keeper])
        var missingRemoved = removed
        missingRemoved.availability = .missing
        XCTAssertEqual(model.selectedFileDetail, missingRemoved)
        XCTAssertEqual(model.detailErrorMapping?.kind, .fileNotFound)
        XCTAssertEqual(model.statusBanner, .removedSelectedFile(fileID: removed.id))
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(fileID: removed.id, event: event, .detailRemovedFixture())
        )
        await lister.assertChangeLogListRequests([
            DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: removed.id))
        ])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: removed.id, entries: [entry]))
    }
}

extension DetailLogExternalRemovedPageFeatureTests {
    @MainActor
    func testMixedExternalWindowKeepsSelectedRemovedFileAheadOfLaterCreate() async throws {
        let removed = FileEntrySnapshot.detailMetaFixture(id: 44, currentName: "removed.pdf")
        var created = FileEntrySnapshot.detailMetaFixture(id: 45, currentName: "later.pdf")
        created.path = "docs/later.pdf"
        let removedEvent = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: removed.path,
            fsEventID: 10004
        ))
        let createdEvent = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: created.path,
            fsEventID: 10005
        ))
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: removed.id, action: "deleted")
        let result = SyncResultSnapshot.testFixture(detectedCreates: 1, detectedDeletes: 1)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [removed]),
            fileLister: RecordingFileLister(files: [created]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(removed)),
            changeLogLister: DetailLogRecordingLister(results: [.success([entry])]),
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(result)),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([removed.id])
        await model.syncExternalChanges([removedEvent, createdEvent])

        var missingRemoved = removed
        missingRemoved.availability = .missing
        XCTAssertEqual(model.files, [created])
        XCTAssertEqual(model.selection, .single(removed.id))
        XCTAssertEqual(model.selectedFileDetail, missingRemoved)
        XCTAssertEqual(model.statusBanner, .removedSelectedFile(fileID: removed.id))
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(fileID: removed.id, event: removedEvent, result)
        )
    }

    @MainActor
    func testSelectedRemovalReplayWithNoDetectedChangesRefreshesAndCompletes() async throws {
        let removed = FileEntrySnapshot.detailMetaFixture(id: 46, currentName: "cursor-removed.pdf")
        let keeper = FileEntrySnapshot.detailMetaFixture(id: 47, currentName: "keeper.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: removed.path,
            fsEventID: 10006,
            cursorWatermark: 10007
        ))
        let window = try externalRemovedWindow(event: event, cursorWatermark: 10007)
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: removed.id, action: "deleted")
        let fileLister = RecordingFileLister(files: [keeper])
        let syncer = RecordingExternalChangesSyncer(
            results: [
                .success(.deletedFixture()),
                .success(.testFixture())
            ],
            cursorWriteResults: [
                .failure(CoreError.Db(message: "cursor failed")),
                .success(())
            ]
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [removed, keeper]),
            fileLister: fileLister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(removed)),
            changeLogLister: DetailLogRecordingLister(results: [.success([entry])]),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([removed.id])
        let firstAttemptCompleted = await model.syncExternalWindow(window)
        XCTAssertFalse(firstAttemptCompleted)
        XCTAssertTrue(model.hasRetryableExternalSyncFailure)

        let replayCompleted = await model.syncExternalWindow(window)
        XCTAssertTrue(replayCompleted)

        var missingRemoved = removed
        missingRemoved.availability = .missing
        XCTAssertEqual(model.files, [keeper])
        XCTAssertEqual(model.selection, .single(removed.id))
        XCTAssertEqual(model.selectedFileDetail, missingRemoved)
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(fileID: removed.id, event: event, .testFixture())
        )
        XCTAssertFalse(model.hasRetryableExternalSyncFailure)
        let batchCount = await syncer.recordedBatchCount()
        XCTAssertEqual(batchCount, 2)
        await syncer.assertCursorWrites([10007, 10007])
        await fileLister.assertFileListRequestCount(1)
    }

    @MainActor
    func testDetailLogSyncExternalRemovedCoreMapsCoreFailureWithoutRefreshingLog() async throws {
        let selected = FileEntrySnapshot.detailMetaFixture(id: 42, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: selected.path,
            fsEventID: 10002
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalRemoved(kind: .db)
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncer = DetailLogExternalRemovedSyncer(result: .failure(CoreError.Db(message: "delete log failed")))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: DetailLogExternalRemovedLister(files: [selected]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(selected)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: mapper
        )

        await model.selectFiles([selected.id])
        await model.syncExternalCreated(event)

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(fileID: selected.id, event: event, mapping))
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "delete log failed")])
        await lister.assertChangeLogListRequests([])
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testDetailLogSyncExternalRemovedCoreTreatsMissingDetectedDeleteAsFailure() async throws {
        let selected = FileEntrySnapshot.detailMetaFixture(id: 43, currentName: "partial.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: selected.path,
            fsEventID: 10003
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalRemoved(kind: .internal)
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncer = DetailLogExternalRemovedSyncer(result: .success(.detailRemovedMissingDeleteFixture()))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: DetailLogExternalRemovedLister(files: []),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(selected)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: mapper
        )

        await model.selectFiles([selected.id])
        await model.syncExternalCreated(event)

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(fileID: selected.id, event: event, mapping))
        await lister.assertChangeLogListRequests([])
        await mapper.assertFirstMappedInternalErrorContains("removed event 10003 did not report a detected delete")
    }

    func testDetailLogSyncExternalRemovedCoreRejectsInvalidExternalRemovedEventsBeforeCoreBridge() {
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: "/tmp/repo/docs/gone.pdf",
            fsEventID: 1
        ))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "../gone.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "docs/../gone.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "docs/gone.pdf", fsEventID: 0))
    }

    func testDetailLogSyncExternalRemovedCoreDefaultCoreBridgeSyncsRealExternalRemovedFileIntoListDetailAndLog(
    ) async throws {
        let repoURL = try makeDetailLogExternalRemovedTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

        let bridge = CoreBridge()
        let fixture = try await prepareRealExternalRemovedFixture(repoURL: repoURL, bridge: bridge)
        let removedFile = fixture.removedFile
        try removeTestTemporaryItem(fixture.removedURL)

        let result = try await bridge.syncExternalRemoved(
            repoPath: repoURL.path,
            relativePath: "docs/removed.pdf",
            fsEventID: 10012
        )
        let visibleFiles = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(nil))
        let deletedFiles = try await bridge.listFiles(repoPath: repoURL.path, filter: .detailLogIncludingDeleted())
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: removedFile.id))
        let cursor = try await bridge.getFSEventCursor(repoPath: repoURL.path)

        XCTAssertEqual(result, .detailRemovedFixture())
        XCTAssertEqual(visibleFiles.map(\.path), ["docs/keeper.pdf"])
        XCTAssertTrue(deletedFiles.contains { $0.id == removedFile.id && $0.path == "docs/removed.pdf" })
        XCTAssertEqual(Array(changes.map(\.action).prefix(1)), ["deleted"])
        XCTAssertEqual(changes.first?.fileID, removedFile.id)
        XCTAssertTrue(changes.first?.detailSummary.contains("by: external") == true)
        XCTAssertEqual(cursor, 10012)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.keeperURL.path))
    }

    private func prepareRealExternalRemovedFixture(
        repoURL: URL,
        bridge: CoreBridge
    ) async throws -> RealExternalRemovedFixture {
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let removedURL = repoURL.appendingPathComponent("docs/removed.pdf")
        let keeperURL = repoURL.appendingPathComponent("docs/keeper.pdf")
        try FileManager.default.createDirectory(
            at: removedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await createAndSyncFixtureFile(
            DetailLogExternalCreatedFixture(
                repoURL: repoURL,
                bridge: bridge,
                url: removedURL,
                relativePath: "docs/removed.pdf",
                bytes: "external removed bytes",
                fsEventID: 10010
            )
        )
        try await createAndSyncFixtureFile(
            DetailLogExternalCreatedFixture(
                repoURL: repoURL,
                bridge: bridge,
                url: keeperURL,
                relativePath: "docs/keeper.pdf",
                bytes: "keeper bytes",
                fsEventID: 10011
            )
        )
        let files = try await bridge.listFiles(
            repoPath: repoURL.path,
            filter: .currentCategory(nil)
        )
        let removedFile = try XCTUnwrap(files.first { $0.path == "docs/removed.pdf" })
        return RealExternalRemovedFixture(
            removedURL: removedURL,
            keeperURL: keeperURL,
            removedFile: removedFile
        )
    }

    private func createAndSyncFixtureFile(_ fixture: DetailLogExternalCreatedFixture) async throws {
        try Data(fixture.bytes.utf8).write(to: fixture.url)
        _ = try await fixture.bridge.syncExternalCreated(
            repoPath: fixture.repoURL.path,
            relativePath: fixture.relativePath,
            fsEventID: fixture.fsEventID
        )
    }
}

private struct DetailLogExternalCreatedFixture {
    var repoURL: URL
    var bridge: CoreBridge
    var url: URL
    var relativePath: String
    var bytes: String
    var fsEventID: Int64
}

private struct RealExternalRemovedFixture {
    var removedURL: URL
    var keeperURL: URL
    var removedFile: FileEntrySnapshot
}

private typealias DetailLogExternalRemovedListRequest = FileListRequest
private typealias DetailLogExternalRemovedSyncer = RecordingExternalChangesSyncer

private typealias DetailLogExternalRemovedLister = RecordingFileLister

private extension FileFilterSnapshot {
    static func detailLogIncludingDeleted() -> FileFilterSnapshot {
        .testFixture(includeDeleted: true)
    }
}

private extension SyncResultSnapshot {
    static func detailRemovedFixture() -> SyncResultSnapshot {
        .deletedFixture()
    }

    static func detailRemovedMissingDeleteFixture() -> SyncResultSnapshot {
        .testFixture()
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailLogExternalRemoved(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "外部删除同步失败",
            severity: .medium,
            suggestedAction: "请确认文件确实已离开资料库，然后等待下一次文件系统事件或刷新。",
            recoverability: .userActionRequired,
            rawContext: "detail-change-log sync-external-removed sync_external_changes Removed"
        )
    }
}

private func makeDetailLogExternalRemovedTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixDetailExternalRemoved")
}

private func externalRemovedWindow(
    event: MainExternalCreatedFileEvent,
    cursorWatermark: Int64
) throws -> MainExternalSyncWindow {
    try XCTUnwrap(MainExternalSyncWindow(
        repoPath: "/tmp/repo",
        events: [event],
        cursorWatermark: cursorWatermark
    ))
}
