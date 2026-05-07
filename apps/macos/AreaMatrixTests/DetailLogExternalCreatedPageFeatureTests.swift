import XCTest
@testable import AreaMatrix

final class DetailLogExternalCreatedPageFeatureTests: XCTestCase {
    @MainActor
    func testS113C117ProductionRelayCreatesCurrentMainWindowEvent() throws {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: ShellStaticStartupRecoverer(),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)

        AreaMatrixExternalCreatedFileRelay.publish(
            repoPath: "/tmp/repo",
            relativePath: "docs/external-created.pdf",
            fsEventID: 7_100
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertEqual(
            model.externalCreatedEvent(for: opening),
            MainExternalCreatedFileEvent(relativePath: "docs/external-created.pdf", fsEventID: 7_100)
        )
        let handledEvent = try XCTUnwrap(model.externalCreatedEvent(for: opening))
        model.finishExternalCreatedFileEvent(handledEvent)
        XCTAssertNil(model.externalCreatedEvent(for: opening))
    }

    @MainActor
    func testS113C117ProductionRelayIgnoresInvalidOrOtherRepositoryEvents() {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: ShellStaticStartupRecoverer(),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)

        AreaMatrixExternalCreatedFileRelay.publish(repoPath: "/tmp/repo", relativePath: "../bad.pdf", fsEventID: 7_101)
        AreaMatrixExternalCreatedFileRelay.publish(
            repoPath: "/tmp/other-repo",
            relativePath: "docs/other.pdf",
            fsEventID: 7_102
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertNil(model.externalCreatedEvent(for: opening))
    }

    func testS113C117WatcherBuildsCreatedSignalForUserFileOnly() {
        let createdFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)

        let signal = MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs/external-created.pdf",
            flags: createdFlags,
            eventID: 7_103
        )

        XCTAssertEqual(signal?.repoPath, "/tmp/repo")
        XCTAssertEqual(signal?.relativePath, "docs/external-created.pdf")
        XCTAssertEqual(signal?.fsEventID, 7_103)
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/.areamatrix/index.db",
            flags: createdFlags,
            eventID: 7_104
        ))
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs",
            flags: createdFlags | FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir),
            eventID: 7_105
        ))
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/other-repo/docs/new.pdf",
            flags: createdFlags,
            eventID: 7_106
        ))
    }

    @MainActor
    func testS113C117ConsumesRealExternalCreatedEventThenRefreshesListDetailAndLog() async throws {
        let existing = FileEntrySnapshot.detailMetaFixture(id: 22, currentName: "selected.pdf")
        let created = FileEntrySnapshot.detailMetaFixture(id: 23, currentName: "external-created.pdf", origin: "External")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(relativePath: created.path, fsEventID: 7_001))
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: created.id, action: "external_modified")
        let lister = DetailLogRecordingLister(results: [.success([entry])])
        let syncer = DetailLogExternalCreatedSyncer(result: .success(.detailCreatedFixture()))
        let fileLister = DetailLogExternalCreatedLister(files: [existing, created])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [existing]),
            fileLister: fileLister,
            fileDetailer: DetailMetaImmediateDetailer(result: .success(created)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([existing.id])
        await model.syncExternalCreated(event)
        let syncRequests = await syncer.recordedCreatedRequests()
        let listRequests = await fileLister.recordedRequests()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(syncRequests, [
            DetailLogExternalCreatedRequest(repoPath: "/tmp/repo", relativePath: created.path, fsEventID: 7_001),
        ])
        XCTAssertEqual(listRequests, [DetailLogExternalCreatedListRequest(
            repoPath: "/tmp/repo",
            filter: .currentCategory(nil)
        )])
        XCTAssertEqual(model.selection, .single(created.id))
        XCTAssertEqual(model.selectedFileDetail, created)
        XCTAssertEqual(model.detailExternalCreateSyncState, .synced(event: event, fileID: created.id, .detailCreatedFixture()))
        XCTAssertEqual(logRequests, [DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: created.id))])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: created.id, entries: [entry]))
    }

    @MainActor
    func testS113C117MapsCoreFailureWithoutRefreshingLog() async throws {
        let existing = FileEntrySnapshot.detailMetaFixture(id: 24, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(relativePath: "docs/icloud-created.pdf", fsEventID: 7_002))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalCreated(kind: .iCloudPlaceholder)
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncer = DetailLogExternalCreatedSyncer(
            result: .failure(CoreError.ICloudPlaceholder(path: event.relativePath))
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [existing]),
            fileLister: DetailLogExternalCreatedLister(files: [existing]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(existing)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: mapper
        )

        await model.selectFiles([existing.id])
        await model.syncExternalCreated(event)
        let mappedErrors = await mapper.recordedErrors()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(mappedErrors, [CoreError.ICloudPlaceholder(path: event.relativePath)])
        XCTAssertEqual(logRequests, [])
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testS113C117TreatsSyncResultErrorsAsFailure() async throws {
        let created = FileEntrySnapshot.detailMetaFixture(id: 25, currentName: "partial.pdf", origin: "External")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(relativePath: created.path, fsEventID: 7_003))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalCreated(kind: .internal)
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncer = DetailLogExternalCreatedSyncer(result: .success(.detailCreatedWithErrorsFixture()))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            fileLister: DetailLogExternalCreatedLister(files: [created]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(created)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: mapper
        )

        await model.syncExternalCreated(event)
        let mappedErrors = await mapper.recordedErrors()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(logRequests, [])
        guard case .Internal(let message) = mappedErrors.first else {
            return XCTFail("expected internal error for partial sync result")
        }
        XCTAssertTrue(message.contains("created event 7003 returned sync errors"))
    }

    func testS113C117RejectsInvalidExternalCreatedEventsBeforeCoreBridge() {
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "/tmp/repo/docs/new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "docs/../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "docs/new.pdf", fsEventID: 0))
    }

    func testS113C117DefaultCoreBridgeSyncsRealExternalCreatedFileIntoListTreeDetailAndLog() async throws {
        let repoURL = try makeDetailLogExternalCreatedTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let createdURL = repoURL.appendingPathComponent("docs/external-created.pdf")
        try FileManager.default.createDirectory(
            at: createdURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("external created bytes".utf8).write(to: createdURL)

        let result = try await bridge.syncExternalCreated(
            repoPath: repoURL.path,
            relativePath: "docs/external-created.pdf",
            fsEventID: 8_001
        )
        let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(nil))
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: try XCTUnwrap(files.first?.id))
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: detail.id))
        let cursor = try await bridge.getFSEventCursor(repoPath: repoURL.path)

        XCTAssertEqual(result, .detailCreatedFixture())
        XCTAssertEqual(files.map(\.path), ["docs/external-created.pdf"])
        XCTAssertEqual(files.first?.origin, "External")
        XCTAssertEqual(files.first?.storageMode, "Indexed")
        XCTAssertEqual(tree.totalFileCount, 1)
        XCTAssertEqual(detail.path, "docs/external-created.pdf")
        XCTAssertEqual(changes.map(\.action), ["external_modified"])
        XCTAssertEqual(cursor, 8_001)
    }
}

private struct DetailLogExternalCreatedRequest: Equatable {
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

private struct DetailLogExternalCreatedListRequest: Equatable {
    var repoPath: String
    var filter: FileFilterSnapshot
}

private actor DetailLogExternalCreatedSyncer: CoreExternalChangesSyncing {
    private let result: Result<SyncResultSnapshot, Error>
    private var createdRequests: [DetailLogExternalCreatedRequest] = []

    init(result: Result<SyncResultSnapshot, Error>) {
        self.result = result
    }

    func syncExternalCreated(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        createdRequests.append(DetailLogExternalCreatedRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        return try result.get()
    }

    func syncExternalRemoved(repoPath: String, relativePath: String, fsEventID: Int64) async throws -> SyncResultSnapshot {
        throw CoreError.Internal(message: "external removed is outside S1-13 C1-17")
    }

    func getFSEventCursor(repoPath: String) async throws -> Int64? { nil }
    func setFSEventCursor(repoPath: String, lastEventID: Int64) async throws {}

    func recordedCreatedRequests() -> [DetailLogExternalCreatedRequest] { createdRequests }
}

private actor DetailLogExternalCreatedLister: CoreFileListing {
    private let files: [FileEntrySnapshot]
    private var requests: [DetailLogExternalCreatedListRequest] = []

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(DetailLogExternalCreatedListRequest(repoPath: repoPath, filter: filter))
        return files
    }

    func recordedRequests() -> [DetailLogExternalCreatedListRequest] { requests }
}

private extension SyncResultSnapshot {
    static func detailCreatedFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 1,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: []
        )
    }

    static func detailCreatedWithErrorsFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: ["metadata read failed"]
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailLogExternalCreated(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "外部新增文件同步失败",
            severity: .medium,
            suggestedAction: "请确认文件已经可读取，然后等待下一次文件系统事件或刷新。",
            recoverability: .userActionRequired,
            rawContext: "S1-13 C1-17 sync_external_changes Created"
        )
    }
}

private extension FileEntrySnapshot {
    static func detailMetaFixture(
        id: Int64,
        currentName: String,
        storageMode: String = "Copied",
        sourcePath: String? = "~/Downloads/source.pdf",
        origin: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 256,
            hashSha256: "detail-meta-\(id)",
            storageMode: storageMode,
            origin: origin,
            sourcePath: sourcePath,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private func makeDetailLogExternalCreatedTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixDetailExternalCreated-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
