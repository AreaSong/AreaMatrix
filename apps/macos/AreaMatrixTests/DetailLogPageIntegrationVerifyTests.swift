@testable import AreaMatrix
import XCTest

final class DetailLogPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testDetailLogPageIntegrationRequestsLogTabAfterEveryDeclaredExternalSyncKind() async throws {
        try await verifyExternalSync(kind: .created, action: "external_modified", result: .created)
        try await verifyExternalSync(kind: .renamed, action: "renamed", result: .renamed)
        try await verifyExternalSync(kind: .removed, action: "deleted", result: .removed)
    }

    @MainActor
    func testDetailLogPageIntegrationClearsLogStateOnNoSelectionAndMultiSelectionExit() async {
        let first = FileEntrySnapshot.detailMetaFixture(id: 70, currentName: "first.pdf")
        let second = FileEntrySnapshot.detailMetaFixture(id: 71, currentName: "second.pdf")
        let lister = DetailLogRecordingLister(results: [
            .success([.detailLogFixture(fileID: first.id, action: "imported")])
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: DetailLogIntegrationLister(files: [first, second]),
            fileDetailer: DetailLogIntegrationDetailer(results: [.success(first), .success(second)]),
            changeLogLister: lister,
            externalChangesSyncer: DetailLogIntegrationSyncer(
                result: .success(DetailLogIntegrationSyncScenario.created.snapshot)
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([first.id])
        await model.loadSelectedFileChangeLog()
        XCTAssertEqual(model.detailLogState, .loaded(
            fileID: first.id,
            entries: [ChangeLogEntrySnapshot.detailLogFixture(fileID: first.id, action: "imported")]
        ))

        await model.selectFiles([])
        XCTAssertEqual(model.selection, MainFileSelectionState.none)
        XCTAssertEqual(model.detailLogState, MainDetailLogState.notLoaded)
        XCTAssertNil(model.detailTabRequest)

        await model.selectFiles([first.id, second.id])
        XCTAssertEqual(model.selection, MainFileSelectionState.multiple([first.id, second.id]))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertEqual(model.detailLogState, MainDetailLogState.notLoaded)
        XCTAssertNil(model.detailTabRequest)
    }

    @MainActor
    func testDetailLogPageIntegrationKeepsFailureInlineWithoutOpeningLogTab() async throws {
        let selected = FileEntrySnapshot.detailMetaFixture(id: 80, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: selected.path,
            fsEventID: 12001
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: DetailLogIntegrationLister(files: [selected]),
            fileDetailer: DetailLogIntegrationDetailer(results: [.success(selected)]),
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            externalChangesSyncer: DetailLogIntegrationSyncer(result: .failure(CoreError.Db(message: "sync failed"))),
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        await model.selectFiles([selected.id])
        await model.syncExternalCreated(event)

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(fileID: selected.id, event: event, mapping))
        XCTAssertEqual(model.selection, .single(selected.id))
        XCTAssertEqual(model.detailLogState, MainDetailLogState.notLoaded)
        XCTAssertNil(model.detailTabRequest)
    }

    @MainActor
    private func verifyExternalSync(
        kind: MainExternalSyncEventKind,
        action: String,
        result: DetailLogIntegrationSyncScenario
    ) async throws {
        let selected = FileEntrySnapshot.detailMetaFixture(id: 60, currentName: "selected.pdf")
        let synced = FileEntrySnapshot.detailMetaFixture(
            id: syncedFileID(kind: kind),
            currentName: "\(kind.rawValue).pdf"
        )
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: kind,
            relativePath: eventPath(kind: kind, selected: selected, synced: synced),
            fsEventID: fsEventID(kind: kind)
        ))
        let logFileID = syncedLogFileID(kind: kind, selected: selected, synced: synced)
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: logFileID, action: action)
        let lister = DetailLogRecordingLister(results: [.success([entry])])
        let syncer = DetailLogIntegrationSyncer(result: .success(result.snapshot))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: DetailLogIntegrationLister(files: listedFiles(kind: kind, synced: synced)),
            fileDetailer: DetailLogIntegrationDetailer(results: [.success(selected), .success(synced)]),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([selected.id])
        await model.syncExternalCreated(event)

        await syncer.assertSyncedExternalEvent(
            kind: kind,
            repoPath: "/tmp/repo",
            relativePath: event.relativePath,
            fsEventID: event.fsEventID
        )
        await lister.assertChangeLogListRequests([
            DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: logFileID))
        ])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: entry.fileID ?? -1, entries: [entry]))
        XCTAssertEqual(model.detailTabRequest, .automatic(.log))
        model.consumeDetailTabRequest(.automatic(.log))
        XCTAssertNil(model.detailTabRequest)
        assertSelectionState(kind: kind, model: model, selected: selected, synced: synced)
    }

    private func eventPath(
        kind: MainExternalSyncEventKind,
        selected: FileEntrySnapshot,
        synced: FileEntrySnapshot
    ) -> String {
        kind == .removed ? selected.path : synced.path
    }

    private func listedFiles(kind: MainExternalSyncEventKind, synced: FileEntrySnapshot) -> [FileEntrySnapshot] {
        kind == .removed ? [] : [synced]
    }

    private func syncedFileID(kind: MainExternalSyncEventKind) -> Int64 {
        kind == .renamed ? 60 : 61
    }

    private func syncedLogFileID(
        kind: MainExternalSyncEventKind,
        selected: FileEntrySnapshot,
        synced: FileEntrySnapshot
    ) -> Int64 {
        kind == .removed ? selected.id : synced.id
    }

    private func fsEventID(kind: MainExternalSyncEventKind) -> Int64 {
        switch kind {
        case .created:
            11001
        case .renamed:
            11002
        case .removed:
            11003
        case .modified:
            11004
        }
    }

    @MainActor
    private func assertSelectionState(
        kind: MainExternalSyncEventKind,
        model: MainFileListModel,
        selected: FileEntrySnapshot,
        synced: FileEntrySnapshot
    ) {
        if kind == .removed {
            XCTAssertEqual(model.selection, .single(selected.id))
            var missingSelected = selected
            missingSelected.availability = .missing
            XCTAssertEqual(model.selectedFileDetail, missingSelected)
            XCTAssertEqual(model.detailErrorMapping?.kind, .fileNotFound)
        } else {
            XCTAssertEqual(model.selection, .single(synced.id))
            XCTAssertEqual(model.selectedFileDetail, synced)
            XCTAssertNil(model.detailErrorMapping)
        }
    }
}

private enum DetailLogIntegrationSyncScenario {
    case created
    case renamed
    case removed

    var snapshot: SyncResultSnapshot {
        switch self {
        case .created:
            .createdFixture()
        case .renamed:
            .renamedFixture()
        case .removed:
            .deletedFixture()
        }
    }
}

private typealias DetailLogIntegrationSyncer = RecordingExternalChangesSyncer

private typealias DetailLogIntegrationLister = StaticFileLister

private typealias DetailLogIntegrationDetailer = RecordingFileDetailer
