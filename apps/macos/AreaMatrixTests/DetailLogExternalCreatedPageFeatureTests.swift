@testable import AreaMatrix
import XCTest

final class DetailLogExternalCreatedPageFeatureTests: XCTestCase {
    @MainActor
    func testDetailLogSyncExternalCreatedCoreProductionRelayCreatesCurrentMainWindowEvent() throws {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)

        AreaMatrixExternalCreatedFileRelay.publish(
            repoPath: "/tmp/repo",
            relativePath: "docs/external-created.pdf",
            fsEventID: 7100
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertEqual(
            model.externalCreatedEvent(for: opening),
            MainExternalCreatedFileEvent(relativePath: "docs/external-created.pdf", fsEventID: 7100)
        )
        let handledEvent = try XCTUnwrap(model.externalCreatedEvent(for: opening))
        model.finishExternalCreatedFileEvent(handledEvent)
        XCTAssertNil(model.externalCreatedEvent(for: opening))
    }

    @MainActor
    func testDetailLogSyncExternalCreatedCoreProductionRelayIgnoresInvalidOrOtherRepositoryEvents() {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)

        AreaMatrixExternalCreatedFileRelay.publish(repoPath: "/tmp/repo", relativePath: "../bad.pdf", fsEventID: 7101)
        AreaMatrixExternalCreatedFileRelay.publish(
            repoPath: "/tmp/other-repo",
            relativePath: "docs/other.pdf",
            fsEventID: 7102
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertNil(model.externalCreatedEvent(for: opening))
    }

    func testDetailLogSyncExternalCreatedCoreWatcherBuildsCreatedSignalForUserFileOnly() {
        let createdFlags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)

        let signal = MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs/external-created.pdf",
            flags: createdFlags,
            eventID: 7103
        )

        XCTAssertEqual(signal?.repoPath, "/tmp/repo")
        XCTAssertEqual(signal?.relativePath, "docs/external-created.pdf")
        XCTAssertEqual(signal?.fsEventID, 7103)
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/.areamatrix/index.db",
            flags: createdFlags,
            eventID: 7104
        ))
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/repo/docs",
            flags: createdFlags | FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir),
            eventID: 7105
        ))
        XCTAssertNil(MainExternalCreatedFileWatcher.signal(
            repoPath: "/tmp/repo",
            absolutePath: "/tmp/other-repo/docs/new.pdf",
            flags: createdFlags,
            eventID: 7106
        ))
    }

    @MainActor
    func testDetailLogSyncExternalCreatedCoreConsumesRealExternalCreatedEventThenRefreshesListDetailAndLog(
    ) async throws {
        let existing = FileEntrySnapshot.detailMetaFixture(id: 22, currentName: "selected.pdf")
        let created = FileEntrySnapshot.detailMetaFixture(
            id: 23,
            currentName: "external-created.pdf",
            origin: "External"
        )
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(relativePath: created.path, fsEventID: 7001))
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
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([existing.id])
        await model.syncExternalCreated(event)
        let syncRequests = await syncer.recordedCreatedRequests()
        let listRequests = await fileLister.recordedListRequests()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(syncRequests, [
            ExternalSyncRequest(
                kind: .created,
                repoPath: "/tmp/repo",
                relativePath: created.path,
                fsEventID: 7001
            )
        ])
        XCTAssertEqual(listRequests, [DetailLogExternalCreatedListRequest(
            repoPath: "/tmp/repo",
            filter: .currentCategory(nil)
        )])
        XCTAssertEqual(model.selection, .single(created.id))
        XCTAssertEqual(model.selectedFileDetail, created)
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(event: event, fileID: created.id, .detailCreatedFixture())
        )
        XCTAssertEqual(logRequests, [DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: created.id))])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: created.id, entries: [entry]))
    }

    @MainActor
    func testDetailLogSyncExternalCreatedCoreMapsCoreFailureWithoutRefreshingLog() async throws {
        let existing = FileEntrySnapshot.detailMetaFixture(id: 24, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: "docs/icloud-created.pdf",
            fsEventID: 7002
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalCreated(kind: .iCloudPlaceholder)
        let mapper = StaticCoreErrorMapper(mapping: mapping)
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
    func testDetailLogSyncExternalCreatedCoreTreatsSyncResultErrorsAsFailure() async throws {
        let created = FileEntrySnapshot.detailMetaFixture(id: 25, currentName: "partial.pdf", origin: "External")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(relativePath: created.path, fsEventID: 7003))
        let mapper = StaticCoreErrorMapper(mapping: .detailLogExternalCreated(kind: .internal))
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncResult = SyncResultSnapshot.detailCreatedWithErrorsFixture()
        let syncer = DetailLogExternalCreatedSyncer(result: .success(syncResult))
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
        let rawContext = "created event 7003 returned sync errors: \(syncResult.errors.joined(separator: "; "))"
        let mapping = CoreErrorMappingSnapshot.internalFailure(rawContext: rawContext)

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(mappedErrors, [])
        XCTAssertEqual(logRequests, [])
        XCTAssertTrue(mapping.rawContext.contains("created event 7003 returned sync errors"))
    }

    func testDetailLogSyncExternalCreatedCoreRejectsInvalidExternalCreatedEventsBeforeCoreBridge() {
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "/tmp/repo/docs/new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "docs/../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(relativePath: "docs/new.pdf", fsEventID: 0))
    }

    func testDetailLogSyncExternalCreatedCoreDefaultCoreBridgeSyncsRealExternalCreatedFileIntoListTreeDetailAndLog(
    ) async throws {
        let repoURL = try makeDetailLogExternalCreatedTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

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
            fsEventID: 8001
        )
        let files = try await bridge.listFiles(repoPath: repoURL.path, filter: .currentCategory(nil))
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: XCTUnwrap(files.first?.id))
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: detail.id))
        let cursor = try await bridge.getFSEventCursor(repoPath: repoURL.path)

        XCTAssertEqual(result, .detailCreatedFixture())
        XCTAssertEqual(files.map(\.path), ["docs/external-created.pdf"])
        XCTAssertEqual(files.first?.origin, "External")
        XCTAssertEqual(files.first?.storageMode, "Indexed")
        XCTAssertEqual(tree.totalFileCount, 1)
        XCTAssertEqual(detail.path, "docs/external-created.pdf")
        XCTAssertEqual(changes.map(\.action), ["external_modified"])
        XCTAssertEqual(cursor, 8001)
    }
}

private typealias DetailLogExternalCreatedListRequest = FileListRequest
private typealias DetailLogExternalCreatedSyncer = RecordingExternalChangesSyncer

private typealias DetailLogExternalCreatedLister = RecordingFileLister

private extension SyncResultSnapshot {
    static func detailCreatedFixture() -> SyncResultSnapshot {
        .createdFixture()
    }

    static func detailCreatedWithErrorsFixture() -> SyncResultSnapshot {
        .errorFixture("metadata read failed")
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailLogExternalCreated(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "外部新增文件同步失败",
            severity: .medium,
            suggestedAction: "请确认文件已经可读取，然后等待下一次文件系统事件或刷新。",
            recoverability: .userActionRequired,
            rawContext: "detail-change-log sync-external-created sync_external_changes Created"
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
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/contracts/\(currentName)",
            currentName: currentName,
            category: "docs"
        ) {
            $0.sizeBytes = 256
            $0.hashSha256 = "detail-meta-\(id)"
            $0.storageMode = storageMode
            $0.origin = origin
            $0.sourcePath = sourcePath
        }
    }
}

private func makeDetailLogExternalCreatedTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixDetailExternalCreated")
}
