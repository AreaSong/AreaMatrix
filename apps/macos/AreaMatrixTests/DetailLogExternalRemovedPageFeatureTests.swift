import XCTest
@testable import AreaMatrix

final class DetailLogExternalRemovedPageFeatureTests: XCTestCase {
    @MainActor
    func testS113C119ProductionRelayCreatesCurrentMainWindowRemovedEvent() throws {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: ShellStaticStartupRecoverer(),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)

        AreaMatrixExternalCreatedFileRelay.publish(
            kind: .removed,
            repoPath: "/tmp/repo",
            relativePath: "docs/removed.pdf",
            fsEventID: 10_100
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertEqual(
            model.externalCreatedEvent(for: opening),
            MainExternalCreatedFileEvent(kind: .removed, relativePath: "docs/removed.pdf", fsEventID: 10_100)
        )
        let handledEvent = try XCTUnwrap(model.externalCreatedEvent(for: opening))
        model.finishExternalCreatedFileEvent(handledEvent)
        XCTAssertNil(model.externalCreatedEvent(for: opening))
    }

    func testS113C119WatcherBuildsRemovedSignalForUserFileOnly() {
        let removedFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved)

        let signal = MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs/removed.pdf",
            flags: removedFlags,
            eventID: 10_101
        )

        XCTAssertEqual(signal?.kind, .removed)
        XCTAssertEqual(signal?.repoPath, "/tmp/repo")
        XCTAssertEqual(signal?.relativePath, "docs/removed.pdf")
        XCTAssertEqual(signal?.fsEventID, 10_101)
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/.areamatrix/index.db",
            flags: removedFlags,
            eventID: 10_102
        ))
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs",
            flags: removedFlags | FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir),
            eventID: 10_103
        ))
    }

    @MainActor
    func testS113C119ConsumesSelectedExternalRemovedEventThenRefreshesListAndLog() async throws {
        let removed = FileEntrySnapshot.detailMetaFixture(id: 40, currentName: "removed.pdf")
        let keeper = FileEntrySnapshot.detailMetaFixture(id: 41, currentName: "keeper.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: removed.path,
            fsEventID: 10_001
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
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([removed.id])
        await model.syncExternalCreated(event)
        let syncRequests = await syncer.recordedRemovedRequests()
        let listRequests = await fileLister.recordedRequests()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(syncRequests, [
            DetailLogExternalRemovedRequest(repoPath: "/tmp/repo", relativePath: removed.path, fsEventID: 10_001),
        ])
        XCTAssertEqual(listRequests, [DetailLogExternalRemovedListRequest(
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
        XCTAssertEqual(model.detailExternalCreateSyncState, .synced(event: event, fileID: removed.id, .detailRemovedFixture()))
        XCTAssertEqual(logRequests, [DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: removed.id))])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: removed.id, entries: [entry]))
    }

    @MainActor
    func testS113C119MapsCoreFailureWithoutRefreshingLog() async throws {
        let selected = FileEntrySnapshot.detailMetaFixture(id: 42, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: selected.path,
            fsEventID: 10_002
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalRemoved(kind: .db)
        let mapper = DetailMetaErrorMapper(mapping: mapping)
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
        let mappedErrors = await mapper.recordedErrors()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "delete log failed")])
        XCTAssertEqual(logRequests, [])
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testS113C119TreatsMissingDetectedDeleteAsFailure() async throws {
        let selected = FileEntrySnapshot.detailMetaFixture(id: 43, currentName: "partial.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .removed,
            relativePath: selected.path,
            fsEventID: 10_003
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalRemoved(kind: .internal)
        let mapper = DetailMetaErrorMapper(mapping: mapping)
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
        let mappedErrors = await mapper.recordedErrors()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(logRequests, [])
        guard case .Internal(let message) = mappedErrors.first else {
            return XCTFail("expected internal error for missing detected delete")
        }
        XCTAssertTrue(message.contains("removed event 10003 did not report a detected delete"))
    }

    func testS113C119RejectsInvalidExternalRemovedEventsBeforeCoreBridge() {
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "/tmp/repo/docs/gone.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "../gone.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "docs/../gone.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .removed, relativePath: "docs/gone.pdf", fsEventID: 0))
    }

    func testS113C119DefaultCoreBridgeSyncsRealExternalRemovedFileIntoListDetailAndLog() async throws {
        let repoURL = try makeDetailLogExternalRemovedTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let bridge = CoreBridge()
        let fixture = try await prepareRealExternalRemovedFixture(repoURL: repoURL, bridge: bridge)
        let removedFile = fixture.removedFile
        try FileManager.default.removeItem(at: fixture.removedURL)

        let result = try await bridge.syncExternalRemoved(
            repoPath: repoURL.path,
            relativePath: "docs/removed.pdf",
            fsEventID: 10_012
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
        XCTAssertEqual(cursor, 10_012)
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
            repoURL: repoURL,
            bridge: bridge,
            url: removedURL,
            relativePath: "docs/removed.pdf",
            bytes: "external removed bytes",
            fsEventID: 10_010
        )
        try await createAndSyncFixtureFile(
            repoURL: repoURL,
            bridge: bridge,
            url: keeperURL,
            relativePath: "docs/keeper.pdf",
            bytes: "keeper bytes",
            fsEventID: 10_011
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

    private func createAndSyncFixtureFile(
        repoURL: URL,
        bridge: CoreBridge,
        url: URL,
        relativePath: String,
        bytes: String,
        fsEventID: Int64
    ) async throws {
        try Data(bytes.utf8).write(to: url)
        _ = try await bridge.syncExternalCreated(
            repoPath: repoURL.path,
            relativePath: relativePath,
            fsEventID: fsEventID
        )
    }
}

private struct RealExternalRemovedFixture {
    var removedURL: URL
    var keeperURL: URL
    var removedFile: FileEntrySnapshot
}

private struct DetailLogExternalRemovedRequest: Equatable {
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

private struct DetailLogExternalRemovedListRequest: Equatable {
    var repoPath: String
    var filter: FileFilterSnapshot
}

private actor DetailLogExternalRemovedSyncer: CoreExternalChangesSyncing {
    private let result: Result<SyncResultSnapshot, Error>
    private var removedRequests: [DetailLogExternalRemovedRequest] = []

    init(result: Result<SyncResultSnapshot, Error>) {
        self.result = result
    }

    func syncExternalCreated(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        throw CoreError.Internal(message: "external created is outside S1-13 C1-19")
    }

    func syncExternalRenamed(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        throw CoreError.Internal(message: "external renamed is outside S1-13 C1-19")
    }

    func syncExternalRemoved(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        removedRequests.append(DetailLogExternalRemovedRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        return try result.get()
    }

    func getFSEventCursor(repoPath: String) async throws -> Int64? { nil }
    func setFSEventCursor(repoPath: String, lastEventID: Int64) async throws {}

    func recordedRemovedRequests() -> [DetailLogExternalRemovedRequest] { removedRequests }
}

private actor DetailLogExternalRemovedLister: CoreFileListing {
    private let files: [FileEntrySnapshot]
    private var requests: [DetailLogExternalRemovedListRequest] = []

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(DetailLogExternalRemovedListRequest(repoPath: repoPath, filter: filter))
        return files
    }

    func recordedRequests() -> [DetailLogExternalRemovedListRequest] { requests }
}

private extension FileFilterSnapshot {
    static func detailLogIncludingDeleted() -> FileFilterSnapshot {
        FileFilterSnapshot(
            category: nil,
            includeDeleted: true,
            importedAfter: nil,
            importedBefore: nil,
            limit: 50,
            offset: 0
        )
    }
}

private extension SyncResultSnapshot {
    static func detailRemovedFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 0,
            detectedDeletes: 1,
            detectedModifies: 0,
            errors: []
        )
    }

    static func detailRemovedMissingDeleteFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: []
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailLogExternalRemoved(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "外部删除同步失败",
            severity: .medium,
            suggestedAction: "请确认文件确实已离开资料库，然后等待下一次文件系统事件或刷新。",
            recoverability: .userActionRequired,
            rawContext: "S1-13 C1-19 sync_external_changes Removed"
        )
    }
}

private func makeDetailLogExternalRemovedTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixDetailExternalRemoved-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
