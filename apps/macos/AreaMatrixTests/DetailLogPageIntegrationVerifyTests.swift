import XCTest
@testable import AreaMatrix

final class DetailLogPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS113PageIntegrationRequestsLogTabAfterEveryDeclaredExternalSyncKind() async throws {
        try await verifyExternalSync(kind: .created, action: "external_modified", result: .created)
        try await verifyExternalSync(kind: .renamed, action: "renamed", result: .renamed)
        try await verifyExternalSync(kind: .removed, action: "deleted", result: .removed)
    }

    @MainActor
    func testS113PageIntegrationClearsLogStateOnNoSelectionAndMultiSelectionExit() async {
        let first = FileEntrySnapshot.detailMetaFixture(id: 70, currentName: "first.pdf")
        let second = FileEntrySnapshot.detailMetaFixture(id: 71, currentName: "second.pdf")
        let lister = DetailLogRecordingLister(results: [
            .success([.detailLogFixture(fileID: first.id, action: "imported")]),
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: DetailLogIntegrationLister(files: [first, second]),
            fileDetailer: DetailLogIntegrationDetailer(results: [.success(first), .success(second)]),
            changeLogLister: lister,
            externalChangesSyncer: DetailLogIntegrationSyncer(result: .created),
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([first.id])
        await model.loadSelectedFileChangeLog()
        XCTAssertEqual(model.detailLogState, .loaded(
            fileID: first.id,
            entries: [.detailLogFixture(fileID: first.id, action: "imported")]
        ))

        await model.selectFiles([])
        XCTAssertEqual(model.selection, .none)
        XCTAssertEqual(model.detailLogState, .notLoaded)
        XCTAssertNil(model.detailTabRequest)

        await model.selectFiles([first.id, second.id])
        XCTAssertEqual(model.selection, .multiple([first.id, second.id]))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertEqual(model.detailLogState, .notLoaded)
        XCTAssertNil(model.detailTabRequest)
    }

    @MainActor
    func testS113PageIntegrationKeepsFailureInlineWithoutOpeningLogTab() async throws {
        let selected = FileEntrySnapshot.detailMetaFixture(id: 80, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: selected.path,
            fsEventID: 12_001
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: DetailLogIntegrationLister(files: [selected]),
            fileDetailer: DetailLogIntegrationDetailer(results: [.success(selected)]),
            changeLogLister: DetailLogRecordingLister(results: [.success([])]),
            externalChangesSyncer: DetailLogIntegrationSyncer(error: CoreError.Db(message: "sync failed")),
            errorMapper: DetailMetaErrorMapper(mapping: mapping)
        )

        await model.selectFiles([selected.id])
        await model.syncExternalCreated(event)

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(model.selection, .single(selected.id))
        XCTAssertEqual(model.detailLogState, .notLoaded)
        XCTAssertNil(model.detailTabRequest)
    }

    @MainActor
    private func verifyExternalSync(
        kind: MainExternalSyncEventKind,
        action: String,
        result: DetailLogIntegrationSyncResult
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
        let syncer = DetailLogIntegrationSyncer(result: result)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: DetailLogIntegrationLister(files: listedFiles(kind: kind, synced: synced)),
            fileDetailer: DetailLogIntegrationDetailer(results: [.success(selected), .success(synced)]),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([selected.id])
        await model.syncExternalCreated(event)

        let syncRequests = await syncer.recordedRequests()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(syncRequests, [DetailLogIntegrationSyncRequest(
            kind: kind,
            repoPath: "/tmp/repo",
            relativePath: event.relativePath,
            fsEventID: event.fsEventID
        )])
        XCTAssertEqual(logRequests, [
            DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: logFileID)),
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
            return 11_001
        case .renamed:
            return 11_002
        case .removed:
            return 11_003
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

private enum DetailLogIntegrationSyncResult {
    case created
    case renamed
    case removed

    var snapshot: SyncResultSnapshot {
        switch self {
        case .created:
            return SyncResultSnapshot(
                detectedCreates: 1,
                detectedRenames: 0,
                detectedDeletes: 0,
                detectedModifies: 0,
                errors: []
            )
        case .renamed:
            return SyncResultSnapshot(
                detectedCreates: 0,
                detectedRenames: 1,
                detectedDeletes: 0,
                detectedModifies: 0,
                errors: []
            )
        case .removed:
            return SyncResultSnapshot(
                detectedCreates: 0,
                detectedRenames: 0,
                detectedDeletes: 1,
                detectedModifies: 0,
                errors: []
            )
        }
    }
}

private struct DetailLogIntegrationSyncRequest: Equatable {
    var kind: MainExternalSyncEventKind
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

private actor DetailLogIntegrationSyncer: CoreExternalChangesSyncing {
    private let result: Result<SyncResultSnapshot, Error>
    private var requests: [DetailLogIntegrationSyncRequest] = []

    init(result: DetailLogIntegrationSyncResult) {
        self.result = .success(result.snapshot)
    }

    init(error: Error) {
        result = .failure(error)
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

    func getFSEventCursor(repoPath: String) async throws -> Int64? { nil }
    func setFSEventCursor(repoPath: String, lastEventID: Int64) async throws {}

    func recordedRequests() -> [DetailLogIntegrationSyncRequest] { requests }

    private func recordAndResolve(
        kind: MainExternalSyncEventKind,
        repoPath: String,
        relativePath: String,
        fsEventID: Int64
    ) throws -> SyncResultSnapshot {
        requests.append(DetailLogIntegrationSyncRequest(
            kind: kind,
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        return try result.get()
    }
}

private actor DetailLogIntegrationLister: CoreFileListing {
    private let files: [FileEntrySnapshot]

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        files
    }
}

private actor DetailLogIntegrationDetailer: CoreFileDetailing {
    typealias Result = DetailMetaImmediateDetailer.Result

    private var results: [Result]

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case .success(let file):
            return file
        case .failure(let error):
            throw error
        }
    }
}
