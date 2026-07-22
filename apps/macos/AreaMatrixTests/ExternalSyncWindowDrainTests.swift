@testable import AreaMatrix
import XCTest

final class ExternalSyncWindowDrainTests: XCTestCase {
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
        let syncer = RecordingExternalChangesSyncer(result: .success(.testFixture(
            detectedCreates: 1,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 1,
            errors: []
        )))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [modified]),
            fileLister: RecordingFileLister(files: [created, modified]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(modified)),
            changeLogLister: DetailLogRecordingLister(results: [.success([
                .detailLogFixture(fileID: modified.id, action: "external_modified")
            ])]),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([modified.id])
        let synced = await model.syncExternalChanges(events)
        XCTAssertTrue(synced)
        await syncer.assertSyncedExternalEvents(repoPath: "/tmp/repo", events: events)
        await syncer.assertCursorWrites([342])
        XCTAssertEqual(model.selection, .single(modified.id))
        XCTAssertEqual(model.selectedFileDetail, modified)
    }

    @MainActor
    func testNoOpExternalBatchCompletesWithoutSelectingIgnoredPath() async throws {
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .modified,
            relativePath: "docs/report.pdf.md",
            fsEventID: 350
        ))
        let syncer = RecordingExternalChangesSyncer(result: .success(.testFixture(
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
    func testMixedBatchWithFinalManagedSidecarReloadsLastVisibleFile() async throws {
        var created = FileEntrySnapshot.detailMetaFixture(id: 28, currentName: "created.pdf")
        created.path = "docs/created.pdf"
        created.origin = "External"
        let events = try [
            XCTUnwrap(MainExternalCreatedFileEvent(
                kind: .created,
                relativePath: created.path,
                fsEventID: 360,
                cursorWatermark: 362
            )),
            XCTUnwrap(MainExternalCreatedFileEvent(
                kind: .modified,
                relativePath: "docs/created.pdf.md",
                fsEventID: 361,
                cursorWatermark: 362
            ))
        ]
        let syncer = RecordingExternalChangesSyncer(result: .success(.testFixture(
            detectedCreates: 1,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: []
        )))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            fileLister: RecordingFileLister(files: [created]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(created)),
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        let synced = await model.syncExternalChanges(events)

        XCTAssertTrue(synced)
        XCTAssertEqual(model.selection, MainFileSelectionState.none)
        XCTAssertNil(model.selectedFileDetail)
        await syncer.assertCursorWrites([362])
        await syncer.assertSyncedExternalEvents(repoPath: "/tmp/repo", events: events)
    }

    @MainActor
    func testPresentationReloadFailureCompletesCommittedWindowWithoutResubmittingCore() async throws {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let shell = makeShellMainListFixture(opening: opening, model: makeShellOnboardingModel())
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: "docs/committed.pdf",
            fsEventID: 365,
            cursorWatermark: 365
        ))
        let window = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: opening.config.repoPath,
            events: [event],
            cursorWatermark: 365
        ))
        XCTAssertTrue(shell.model.handleExternalSyncWindows([window]))

        let reloadError = CoreError.Db(message: "presentation reload failed")
        let mapping = CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "Presentation reload failed",
            suggestedAction: "Refresh the file list."
        )
        let fileLister = RecordingFileLister(results: [.failure(reloadError)])
        let syncer = RecordingExternalChangesSyncer(result: .success(.createdFixture()))
        let model = MainFileListModel(
            opening: opening,
            fileLister: fileLister,
            fileDetailer: RecordingFileDetailer(results: []),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        scheduleHeadExternalSyncWindow(model, shell: shell.model, opening: opening)
        let drained = await waitForWindowDrain(shell.model, opening: opening)
        XCTAssertTrue(drained)
        model.scheduleExternalSyncDrain(windows: shell.model.externalSyncWindows(for: opening)) { _ in
            XCTFail("An already completed window must not be submitted again")
        }

        let batchCount = await syncer.recordedBatchCount()
        XCTAssertEqual(batchCount, 1)
        await fileLister.assertFileListRequestCount(1)
        XCTAssertEqual(model.errorMapping, mapping)
        XCTAssertEqual(model.detailExternalCreateSyncState, .idle)
    }

    @MainActor
    func testExternalSyncDrainSerializesBusinessAndFilteredWindows() async throws {
        var created = FileEntrySnapshot.detailMetaFixture(id: 29, currentName: "created.pdf")
        created.path = "docs/created.pdf"
        created.origin = "External"
        let business = try XCTUnwrap(try MainExternalSyncWindow(
            repoPath: "/tmp/repo",
            events: [XCTUnwrap(MainExternalCreatedFileEvent(
                relativePath: created.path,
                fsEventID: 370
            ))],
            cursorWatermark: 370
        ))
        let filtered = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: "/tmp/repo",
            events: [],
            cursorWatermark: 371
        ))
        let syncer = RecordingExternalChangesSyncer(
            result: .success(.createdFixture()),
            suspendsSync: true
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            fileLister: RecordingFileLister(files: [created]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(created)),
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )
        var completed: [MainExternalSyncWindow] = []

        model.scheduleExternalSyncDrain(windows: [business, filtered]) { completed.append($0) }
        await waitForBatchCount(1, syncer: syncer)
        model.scheduleExternalSyncDrain(windows: [business, filtered]) { completed.append($0) }

        let batchCountBeforeResume = await syncer.recordedBatchCount()
        let maxConcurrentBeforeResume = await syncer.recordedMaxConcurrentSyncCalls()
        let cursorWritesBeforeResume = await syncer.recordedCursorWrites()
        XCTAssertEqual(batchCountBeforeResume, 1)
        XCTAssertEqual(maxConcurrentBeforeResume, 1)
        XCTAssertEqual(cursorWritesBeforeResume, [])

        await syncer.resumeNextSync()
        await waitForCompletedWindowCount(1, completed: { completed.count })
        model.scheduleExternalSyncDrain(windows: [filtered]) { completed.append($0) }
        await waitForCursorWrites([371], syncer: syncer)

        XCTAssertEqual(completed, [business, filtered])
        let maxConcurrentAfterCompletion = await syncer.recordedMaxConcurrentSyncCalls()
        XCTAssertEqual(maxConcurrentAfterCompletion, 1)
    }
}

extension ExternalSyncWindowDrainTests {
    @MainActor
    func testCoreFailureRetriesHeadWindowBeforeLaterCursorAck() async throws {
        let created = externalSyncFile(id: 30, currentName: "retry.pdf", path: "docs/retry.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: created.path,
            fsEventID: 380
        ))
        let business = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: "/tmp/repo",
            events: [event],
            cursorWatermark: 380
        ))
        let filtered = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: "/tmp/repo",
            events: [],
            cursorWatermark: 381
        ))
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let shell = makeShellMainListFixture(opening: opening, model: makeShellOnboardingModel())
        XCTAssertTrue(shell.model.handleExternalSyncWindows([business, filtered]))
        let mapping = CoreErrorMappingSnapshot.testFixture(kind: .db, userMessage: "External sync failed")
        let syncer = RecordingExternalChangesSyncer(results: [
            .failure(CoreError.Db(message: "sync failed")),
            .success(.createdFixture())
        ])
        let model = MainFileListModel(
            opening: opening,
            fileLister: RecordingFileLister(files: [created]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(created)),
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        scheduleHeadExternalSyncWindow(model, shell: shell.model, opening: opening)
        let firstFailureBecameRetryable = await waitForRetryableExternalSyncFailure(model)
        XCTAssertTrue(firstFailureBecameRetryable)
        XCTAssertEqual(shell.model.externalSyncWindows(for: opening), [business, filtered])
        XCTAssertEqual(model.externalSyncAttemptRevision, 0)
        await syncer.assertCursorWrites([])

        model.retryExternalSync()
        XCTAssertEqual(model.externalSyncAttemptRevision, 1)
        scheduleHeadExternalSyncWindow(model, shell: shell.model, opening: opening)
        let advancedToFilteredWindow = await waitForHeadWindow(filtered, shell: shell.model, opening: opening)
        let batchCountAfterRetry = await syncer.recordedBatchCount()
        XCTAssertTrue(advancedToFilteredWindow)
        XCTAssertEqual(batchCountAfterRetry, 2)
        await syncer.assertCursorWrites([])

        scheduleHeadExternalSyncWindow(model, shell: shell.model, opening: opening)
        let drainedAllWindows = await waitForWindowDrain(shell.model, opening: opening)
        XCTAssertTrue(drainedAllWindows)
        await syncer.assertCursorWrites([381])
    }

    @MainActor
    func testCursorFailureAfterCoreCommitRetriesSameHeadWindow() async throws {
        var created = FileEntrySnapshot.detailMetaFixture(id: 31, currentName: "cursor-retry.pdf")
        created.path = "docs/cursor-retry.pdf"
        created.origin = "External"
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: created.path,
            fsEventID: 390,
            cursorWatermark: 391
        ))
        let window = try externalSyncWindow(event: event, cursorWatermark: 391)
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let shell = makeShellMainListFixture(opening: opening, model: makeShellOnboardingModel())
        XCTAssertTrue(shell.model.handleExternalSyncWindows([window]))
        let mapping = CoreErrorMappingSnapshot.testFixture(kind: .db, userMessage: "Cursor write failed")
        let syncer = RecordingExternalChangesSyncer(
            results: [
                .success(.createdFixture()),
                .success(.testFixture())
            ],
            cursorWriteResults: [
                .failure(CoreError.Db(message: "cursor failed")),
                .success(())
            ]
        )
        let fileLister = RecordingFileLister(files: [created])
        let model = MainFileListModel(
            opening: opening,
            fileLister: fileLister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(created)),
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        scheduleHeadExternalSyncWindow(model, shell: shell.model, opening: opening)
        let cursorFailureBecameRetryable = await waitForRetryableExternalSyncFailure(model)
        XCTAssertTrue(cursorFailureBecameRetryable)
        XCTAssertEqual(shell.model.externalSyncWindows(for: opening), [window])
        await syncer.assertCursorWrites([391])

        model.retryExternalSync()
        scheduleHeadExternalSyncWindow(model, shell: shell.model, opening: opening)
        let retriedWindowDrained = await waitForWindowDrain(shell.model, opening: opening)
        let cursorRetryBatchCount = await syncer.recordedBatchCount()
        XCTAssertTrue(retriedWindowDrained)
        XCTAssertEqual(cursorRetryBatchCount, 2)
        await syncer.assertCursorWrites([391, 391])
        XCTAssertEqual(model.files, [created])
        XCTAssertEqual(model.selection, MainFileSelectionState.none)
        XCTAssertNil(model.selectedFileDetail)
        await fileLister.assertFileListRequestCount(1)
        XCTAssertFalse(model.hasRetryableExternalSyncFailure)
    }

    @MainActor
    private func scheduleHeadExternalSyncWindow(
        _ model: MainFileListModel,
        shell: OnboardingModel,
        opening: RepositoryOpeningResult
    ) {
        model.scheduleExternalSyncDrain(windows: shell.externalSyncWindows(for: opening)) {
            shell.finishExternalSyncWindow($0)
        }
    }

    @MainActor
    private func waitForWindowDrain(
        _ shellModel: OnboardingModel,
        opening: RepositoryOpeningResult
    ) async -> Bool {
        await waitForMainActorTestValue(
            attempts: 100,
            delayNanoseconds: 1_000_000,
            failureMessage: { "Timed out waiting for committed external window to finish" },
            value: { shellModel.externalSyncWindows(for: opening).isEmpty ? true : nil }
        ) == true
    }

    @MainActor
    private func waitForRetryableExternalSyncFailure(_ model: MainFileListModel) async -> Bool {
        await waitForMainActorTestValue(
            attempts: 100,
            delayNanoseconds: 1_000_000,
            failureMessage: { "Timed out waiting for retryable external sync failure" },
            value: {
                model.hasRetryableExternalSyncFailure && model.externalSyncDrainTask == nil ? true : nil
            }
        ) == true
    }

    @MainActor
    private func waitForHeadWindow(
        _ expected: MainExternalSyncWindow,
        shell: OnboardingModel,
        opening: RepositoryOpeningResult
    ) async -> Bool {
        await waitForMainActorTestValue(
            attempts: 100,
            delayNanoseconds: 1_000_000,
            failureMessage: { "Timed out waiting for the next external sync window" },
            value: { shell.externalSyncWindows(for: opening).first == expected ? true : nil }
        ) == true
    }

    private func waitForBatchCount(_ expected: Int, syncer: RecordingExternalChangesSyncer) async {
        for _ in 0 ..< 100 {
            if await syncer.recordedBatchCount() == expected { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func waitForCursorWrites(_ expected: [Int64], syncer: RecordingExternalChangesSyncer) async {
        for _ in 0 ..< 100 {
            if await syncer.recordedCursorWrites() == expected { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func waitForCompletedWindowCount(
        _ expected: Int,
        completed: @escaping @MainActor () -> Int
    ) async {
        for _ in 0 ..< 100 {
            if await completed() == expected { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

private func externalSyncFile(id: Int64, currentName: String, path: String) -> FileEntrySnapshot {
    var file = FileEntrySnapshot.detailMetaFixture(id: id, currentName: currentName)
    file.path = path
    file.origin = "External"
    return file
}

private func externalSyncWindow(
    event: MainExternalCreatedFileEvent,
    cursorWatermark: Int64
) throws -> MainExternalSyncWindow {
    try XCTUnwrap(MainExternalSyncWindow(
        repoPath: "/tmp/repo",
        events: [event],
        cursorWatermark: cursorWatermark
    ))
}
