@testable import AreaMatrix
import XCTest

final class DetailLogExternalRenamedPageFeatureTests: XCTestCase {
    @MainActor
    func testDetailLogSyncExternalRenamedCoreProductionRelayCreatesCurrentMainWindowRenamedEvent() {
        let repoPath = "/tmp/AreaMatrixRelayRenamed-\(UUID().uuidString)"
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: repoPath, files: []),
            model: makeShellOnboardingModel()
        )
        let opening = fixture.opening
        let model = fixture.model

        AreaMatrixExternalCreatedFileRelay.publish(
            kind: .renamed,
            repoPath: repoPath,
            relativePath: "docs/renamed.pdf",
            fsEventID: 9100
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertEqual(
            model.externalCreatedEvents(for: opening),
            [MainExternalCreatedFileEvent(kind: .renamed, relativePath: "docs/renamed.pdf", fsEventID: 9100)]
        )
        let handledEvents = model.externalCreatedEvents(for: opening)
        model.finishExternalCreatedFileEvents(handledEvents)
        XCTAssertEqual(model.externalCreatedEvents(for: opening), [])
    }

    func testDetailLogSyncExternalRenamedCoreWatcherBuildsRenamedSignalForUserFileOnly() {
        let renamedFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed)

        let signal = MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs/renamed.pdf",
            flags: renamedFlags,
            eventID: 9101
        )

        XCTAssertEqual(signal?.kind, .renamed)
        XCTAssertEqual(signal?.repoPath, "/tmp/repo")
        XCTAssertEqual(signal?.relativePath, "docs/renamed.pdf")
        XCTAssertEqual(signal?.fsEventID, 9101)
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/.areamatrix/index.db",
            flags: renamedFlags,
            eventID: 9102
        ))
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs",
            flags: renamedFlags | FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir),
            eventID: 9103
        ))
    }

    @MainActor
    func testDetailLogSyncExternalRenamedCoreConsumesRealExternalRenamedEventThenRefreshesListDetailAndLog(
    ) async throws {
        let original = FileEntrySnapshot.detailMetaFixture(id: 30, currentName: "original.pdf")
        let renamed = FileEntrySnapshot.detailMetaFixture(id: 30, currentName: "renamed.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: renamed.path,
            fsEventID: 9001
        ))
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: renamed.id, action: "renamed")
        let lister = DetailLogRecordingLister(results: [.success([entry])])
        let syncer = DetailLogExternalRenamedSyncer(result: .success(.detailRenamedFixture()))
        let fileLister = DetailLogExternalRenamedLister(files: [renamed])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: fileLister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(renamed)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([original.id])
        await model.syncExternalCreated(event)

        await syncer.assertSyncedRenamed(repoPath: "/tmp/repo", relativePath: renamed.path, fsEventID: 9001)
        await fileLister.assertFileListRequests([DetailLogExternalRenamedListRequest(
            repoPath: "/tmp/repo",
            filter: .currentCategory(nil)
        )])
        XCTAssertEqual(model.selection, .single(renamed.id))
        XCTAssertEqual(model.selectedFileDetail, renamed)
        XCTAssertEqual(model.files, [renamed])
        XCTAssertEqual(model.statusBanner, .renamedPreservedSelection(fileID: renamed.id))
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(fileID: renamed.id, event: event, .detailRenamedFixture())
        )
        await lister.assertChangeLogListRequests([
            DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: renamed.id))
        ])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: renamed.id, entries: [entry]))
    }
}

extension DetailLogExternalRenamedPageFeatureTests {
    @MainActor
    func testMixedExternalWindowKeepsSelectedRenamedFileAheadOfLaterCreate() async throws {
        var original = FileEntrySnapshot.detailMetaFixture(id: 35, currentName: "original.pdf")
        original.path = "docs/original.pdf"
        var renamed = original
        renamed.currentName = "renamed.pdf"
        renamed.path = "docs/renamed.pdf"
        var created = FileEntrySnapshot.detailMetaFixture(id: 36, currentName: "later.pdf")
        created.path = "docs/later.pdf"
        let renamedEvent = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: renamed.path,
            fsEventID: 9006
        ))
        let createdEvent = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: created.path,
            fsEventID: 9007
        ))
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: renamed.id, action: "renamed")
        let detailer = RecordingFileDetailer(results: [.success(original), .success(renamed)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: RecordingFileLister(files: [renamed, created]),
            fileDetailer: detailer,
            changeLogLister: DetailLogRecordingLister(results: [.success([entry])]),
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.testFixture(
                detectedCreates: 1,
                detectedRenames: 1
            ))),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([original.id])
        await model.syncExternalChanges([renamedEvent, createdEvent])

        XCTAssertEqual(model.files, [renamed, created])
        XCTAssertEqual(model.selection, .single(renamed.id))
        XCTAssertEqual(model.selectedFileDetail, renamed)
        XCTAssertEqual(model.statusBanner, .renamedPreservedSelection(fileID: renamed.id))
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(
                fileID: renamed.id,
                event: renamedEvent,
                .testFixture(detectedCreates: 1, detectedRenames: 1)
            )
        )
        await detailer.assertRequestedFileIDs([original.id, renamed.id])
    }

    @MainActor
    func testExternalSyncResetsPaginationAndKeepsUnrelatedLaterPageSelection() async throws {
        let firstPage = (0 ..< 50).map { index in
            var file = FileEntrySnapshot.detailMetaFixture(
                id: Int64(100 + index),
                currentName: "page-\(index).pdf"
            )
            file.path = "docs/page-\(index).pdf"
            return file
        }
        let additionalFiles = (50 ..< 74).map { index in
            var file = FileEntrySnapshot.detailMetaFixture(
                id: Int64(100 + index),
                currentName: "page-\(index).pdf"
            )
            file.path = "docs/page-\(index).pdf"
            return file
        }
        var selected = FileEntrySnapshot.detailMetaFixture(id: 999, currentName: "selected-later.pdf")
        selected.path = "docs/selected-later.pdf"
        let loadedDepth = firstPage + additionalFiles + [selected]
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: firstPage[0].path,
            fsEventID: 9008
        ))
        let detailer = RecordingFileDetailer(results: [.success(selected)])
        let fileLister = RecordingFileLister(files: loadedDepth)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: loadedDepth),
            fileLister: fileLister,
            fileDetailer: detailer,
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.renamedFixture())),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )
        model.hasMore = false
        model.isLoadingMore = true
        model.loadMoreErrorMapping = .detailMetaFileNotFound()

        await model.selectFiles([selected.id])
        await model.syncExternalCreated(event)

        XCTAssertEqual(model.files, loadedDepth)
        XCTAssertEqual(model.selection, .single(selected.id))
        XCTAssertEqual(model.selectedFileDetail, selected)
        XCTAssertEqual(model.nextFilePageOffset, 75)
        XCTAssertTrue(model.hasMore)
        XCTAssertFalse(model.isLoadingMore)
        XCTAssertNil(model.loadMoreErrorMapping)
        var expectedFilter = FileFilterSnapshot.currentCategory(nil)
        expectedFilter.limit = 75
        await fileLister.assertFileListFilters([expectedFilter])
        await detailer.assertRequestedFileIDs([selected.id])
    }

    @MainActor
    func testCrossCategoryExternalRenameReloadsSelectedDetailByFileIDAndRequestsNavigation() async throws {
        var original = FileEntrySnapshot.detailMetaFixture(id: 33, currentName: "original.pdf")
        original.path = "docs/original.pdf"
        original.category = "docs"
        var moved = original
        moved.currentName = "renamed.swift"
        moved.path = "code/renamed.swift"
        moved.category = "code"
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: moved.path,
            fsEventID: 9004
        ))
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: moved.id, action: "renamed")
        let detailer = RecordingFileDetailer(results: [.success(original), .success(moved)])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: RecordingFileLister(files: []),
            fileDetailer: detailer,
            changeLogLister: DetailLogRecordingLister(results: [.success([entry])]),
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.renamedFixture())),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )
        model.currentCategory = "docs"

        await model.selectFiles([original.id])
        await model.syncExternalCreated(event)

        XCTAssertEqual(model.files, [])
        XCTAssertEqual(model.selection, .single(moved.id))
        XCTAssertEqual(model.selectedFileDetail, moved)
        XCTAssertEqual(model.pendingExternalSelectionUpdate, .moved(moved))
        XCTAssertEqual(model.detailLogState, .loaded(fileID: moved.id, entries: [entry]))
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(fileID: moved.id, event: event, .renamedFixture())
        )
        await detailer.assertRequestedFileIDs([original.id, original.id])
    }

    @MainActor
    func testCrossCategoryExternalRenameKeepsUnmatchedDetailSelectionIdle() async throws {
        var original = FileEntrySnapshot.detailMetaFixture(id: 34, currentName: "original.pdf")
        original.path = "docs/original.pdf"
        original.category = "docs"
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: "code/renamed.swift",
            fsEventID: 9005
        ))
        let detailer = RecordingFileDetailer(results: [
            .success(original),
            .failure(CoreError.FileNotFound(path: event.relativePath))
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: RecordingFileLister(files: []),
            fileDetailer: detailer,
            externalChangesSyncer: RecordingExternalChangesSyncer(result: .success(.renamedFixture())),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )
        model.currentCategory = "docs"

        await model.selectFiles([original.id])
        await model.syncExternalCreated(event)

        var missingOriginal = original
        missingOriginal.availability = .missing
        XCTAssertEqual(model.selection, .single(original.id))
        XCTAssertEqual(model.selectedFileDetail, missingOriginal)
        XCTAssertNil(model.pendingExternalSelectionUpdate)
        XCTAssertEqual(model.detailExternalCreateSyncState, .idle)
        await detailer.assertRequestedFileIDs([original.id, original.id])
    }

    @MainActor
    func testDetailLogSyncExternalRenamedCoreMapsCoreFailureWithoutRefreshingLog() async throws {
        let existing = FileEntrySnapshot.detailMetaFixture(id: 31, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: "docs/renamed.pdf",
            fsEventID: 9002
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalRenamed(kind: .conflict)
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncer = DetailLogExternalRenamedSyncer(
            result: .failure(CoreError.Conflict(path: event.relativePath))
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [existing]),
            fileLister: DetailLogExternalRenamedLister(files: [existing]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(existing)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: mapper
        )

        await model.selectFiles([existing.id])
        await model.syncExternalCreated(event)

        XCTAssertEqual(model.detailExternalCreateSyncState, .idle)
        await mapper.assertMappedCoreErrors([CoreError.Conflict(path: event.relativePath)])
        await lister.assertChangeLogListRequests([])
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testDetailLogSyncExternalRenamedCoreTreatsSyncResultErrorsAsFailure() async throws {
        let renamed = FileEntrySnapshot.detailMetaFixture(id: 32, currentName: "partial.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: renamed.path,
            fsEventID: 9003
        ))
        let mapper = StaticCoreErrorMapper(mapping: .detailLogExternalRenamed(kind: .internal))
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncResult = SyncResultSnapshot.detailRenamedWithErrorsFixture()
        let syncer = DetailLogExternalRenamedSyncer(result: .success(syncResult))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [renamed]),
            fileLister: DetailLogExternalRenamedLister(files: [renamed]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(renamed)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: mapper
        )

        await model.syncExternalCreated(event)
        let rawContext = "renamed event 9003 returned sync errors: \(syncResult.errors.joined(separator: "; "))"
        let mapping = CoreErrorMappingSnapshot.internalFailure(rawContext: rawContext)

        XCTAssertEqual(model.detailExternalCreateSyncState, .idle)
        await mapper.assertMappedCoreErrors([])
        await lister.assertChangeLogListRequests([])
        XCTAssertTrue(mapping.rawContext.contains("renamed event 9003 returned sync errors"))
    }

    func testDetailLogSyncExternalRenamedCoreRejectsInvalidExternalRenamedEventsBeforeCoreBridge() {
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "/tmp/repo/docs/new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "docs/../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "docs/new.pdf", fsEventID: 0))
    }

    func testDetailLogSyncExternalRenamedCoreDefaultCoreBridgeSyncsRealExternalRenamedFileIntoListDetailAndLog(
    ) async throws {
        let repoURL = try makeDetailLogExternalRenamedTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let originalURL = repoURL.appendingPathComponent("docs/original.pdf")
        let renamedURL = repoURL.appendingPathComponent("docs/renamed.pdf")
        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("external renamed bytes".utf8).write(to: originalURL)
        _ = try await bridge.syncExternalCreated(
            repoPath: repoURL.path,
            relativePath: "docs/original.pdf",
            fsEventID: 9010
        )
        try FileManager.default.moveItem(at: originalURL, to: renamedURL)
        let bytesAfterFinderRename = try Data(contentsOf: renamedURL)

        let result = try await bridge.syncExternalRenamed(
            repoPath: repoURL.path,
            relativePath: "docs/renamed.pdf",
            fsEventID: 9011
        )
        let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(nil))
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: XCTUnwrap(files.first?.id))
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: detail.id))
        let cursor = try await bridge.getFSEventCursor(repoPath: repoURL.path)

        XCTAssertEqual(result, .detailRenamedFixture())
        XCTAssertEqual(files.map(\.path), ["docs/renamed.pdf"])
        XCTAssertEqual(files.first?.currentName, "renamed.pdf")
        XCTAssertEqual(detail.path, "docs/renamed.pdf")
        XCTAssertEqual(detail.currentName, "renamed.pdf")
        XCTAssertEqual(Array(changes.map(\.action).prefix(1)), ["renamed"])
        XCTAssertTrue(changes.first?.detailSummary.contains("to_path: .../renamed.pdf") == true)
        XCTAssertEqual(cursor, 9011)
        XCTAssertEqual(try Data(contentsOf: renamedURL), bytesAfterFinderRename)
    }
}

private typealias DetailLogExternalRenamedListRequest = FileListRequest
private typealias DetailLogExternalRenamedSyncer = RecordingExternalChangesSyncer

private typealias DetailLogExternalRenamedLister = RecordingFileLister

private extension SyncResultSnapshot {
    static func detailRenamedFixture() -> SyncResultSnapshot {
        .renamedFixture()
    }

    static func detailRenamedWithErrorsFixture() -> SyncResultSnapshot {
        .errorFixture("rename pairing failed")
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailLogExternalRenamed(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "外部重命名同步失败",
            severity: .medium,
            suggestedAction: "请确认重命名后的文件仍在资料库内，并重试改动时间线。",
            recoverability: .userActionRequired,
            rawContext: "detail-change-log sync-external-renamed sync_external_changes Renamed"
        )
    }
}

private func makeDetailLogExternalRenamedTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixDetailExternalRenamed")
}
