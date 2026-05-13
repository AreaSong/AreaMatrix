@testable import AreaMatrix
import XCTest

final class DetailLogExternalRenamedPageFeatureTests: XCTestCase {
    @MainActor
    func testS113C118ProductionRelayCreatesCurrentMainWindowRenamedEvent() throws {
        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: "/tmp/repo", files: [])
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: ShellStaticStartupRecoverer(),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)

        AreaMatrixExternalCreatedFileRelay.publish(
            kind: .renamed,
            repoPath: "/tmp/repo",
            relativePath: "docs/renamed.pdf",
            fsEventID: 9100
        )
        model.consumePendingExternalCreatedFileSignals()

        XCTAssertEqual(
            model.externalCreatedEvent(for: opening),
            MainExternalCreatedFileEvent(kind: .renamed, relativePath: "docs/renamed.pdf", fsEventID: 9100)
        )
        let handledEvent = try XCTUnwrap(model.externalCreatedEvent(for: opening))
        model.finishExternalCreatedFileEvent(handledEvent)
        XCTAssertNil(model.externalCreatedEvent(for: opening))
    }

    func testS113C118WatcherBuildsRenamedSignalForUserFileOnly() {
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
    func testS113C118ConsumesRealExternalRenamedEventThenRefreshesListDetailAndLog() async throws {
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
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([original.id])
        await model.syncExternalCreated(event)
        let syncRequests = await syncer.recordedRenamedRequests()
        let listRequests = await fileLister.recordedRequests()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(syncRequests, [
            DetailLogExternalRenamedRequest(repoPath: "/tmp/repo", relativePath: renamed.path, fsEventID: 9001)
        ])
        XCTAssertEqual(listRequests, [DetailLogExternalRenamedListRequest(
            repoPath: "/tmp/repo",
            filter: .currentCategory(nil)
        )])
        XCTAssertEqual(model.selection, .single(renamed.id))
        XCTAssertEqual(model.selectedFileDetail, renamed)
        XCTAssertEqual(model.files, [renamed])
        XCTAssertEqual(model.statusBanner, .renamedPreservedSelection(fileID: renamed.id))
        XCTAssertEqual(
            model.detailExternalCreateSyncState,
            .synced(event: event, fileID: renamed.id, .detailRenamedFixture())
        )
        XCTAssertEqual(logRequests, [DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: renamed.id))])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: renamed.id, entries: [entry]))
    }

    @MainActor
    func testS113C118MapsCoreFailureWithoutRefreshingLog() async throws {
        let existing = FileEntrySnapshot.detailMetaFixture(id: 31, currentName: "selected.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: "docs/renamed.pdf",
            fsEventID: 9002
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalRenamed(kind: .conflict)
        let mapper = DetailMetaErrorMapper(mapping: mapping)
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
        let mappedErrors = await mapper.recordedErrors()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: event.relativePath)])
        XCTAssertEqual(logRequests, [])
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testS113C118TreatsSyncResultErrorsAsFailure() async throws {
        let renamed = FileEntrySnapshot.detailMetaFixture(id: 32, currentName: "partial.pdf")
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            kind: .renamed,
            relativePath: renamed.path,
            fsEventID: 9003
        ))
        let mapping = CoreErrorMappingSnapshot.detailLogExternalRenamed(kind: .internal)
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let lister = DetailLogRecordingLister(results: [.success([])])
        let syncer = DetailLogExternalRenamedSyncer(result: .success(.detailRenamedWithErrorsFixture()))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [renamed]),
            fileLister: DetailLogExternalRenamedLister(files: [renamed]),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(renamed)),
            changeLogLister: lister,
            externalChangesSyncer: syncer,
            errorMapper: mapper
        )

        await model.syncExternalCreated(event)
        let mappedErrors = await mapper.recordedErrors()
        let logRequests = await lister.recordedRequests()

        XCTAssertEqual(model.detailExternalCreateSyncState, .failed(event: event, mapping))
        XCTAssertEqual(logRequests, [])
        guard case let .Internal(message) = mappedErrors.first else {
            return XCTFail("expected internal error for partial sync result")
        }
        XCTAssertTrue(message.contains("renamed event 9003 returned sync errors"))
    }

    func testS113C118RejectsInvalidExternalRenamedEventsBeforeCoreBridge() {
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "/tmp/repo/docs/new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "docs/../new.pdf", fsEventID: 1))
        XCTAssertNil(MainExternalCreatedFileEvent(kind: .renamed, relativePath: "docs/new.pdf", fsEventID: 0))
    }

    func testS113C118DefaultCoreBridgeSyncsRealExternalRenamedFileIntoListDetailAndLog() async throws {
        let repoURL = try makeDetailLogExternalRenamedTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

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

private struct DetailLogExternalRenamedRequest: Equatable {
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

private struct DetailLogExternalRenamedListRequest: Equatable {
    var repoPath: String
    var filter: FileFilterSnapshot
}

private actor DetailLogExternalRenamedSyncer: CoreExternalChangesSyncing {
    private let result: Result<SyncResultSnapshot, Error>
    private var renamedRequests: [DetailLogExternalRenamedRequest] = []

    init(result: Result<SyncResultSnapshot, Error>) {
        self.result = result
    }

    func syncExternalCreated(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        throw CoreError.Internal(message: "external created is outside S1-13 C1-18")
    }

    func syncExternalRenamed(repoPath: String, relativePath: String,
                             fsEventID: Int64) async throws -> SyncResultSnapshot {
        renamedRequests.append(DetailLogExternalRenamedRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        return try result.get()
    }

    func syncExternalRemoved(repoPath _: String, relativePath _: String,
                             fsEventID _: Int64) async throws -> SyncResultSnapshot {
        throw CoreError.Internal(message: "external removed is outside S1-13 C1-18")
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        nil
    }

    func setFSEventCursor(repoPath _: String, lastEventID _: Int64) async throws {}

    func recordedRenamedRequests() -> [DetailLogExternalRenamedRequest] {
        renamedRequests
    }
}

private actor DetailLogExternalRenamedLister: CoreFileListing {
    private let files: [FileEntrySnapshot]
    private var requests: [DetailLogExternalRenamedListRequest] = []

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(DetailLogExternalRenamedListRequest(repoPath: repoPath, filter: filter))
        return files
    }

    func recordedRequests() -> [DetailLogExternalRenamedListRequest] {
        requests
    }
}

private extension SyncResultSnapshot {
    static func detailRenamedFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 1,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: []
        )
    }

    static func detailRenamedWithErrorsFixture() -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: 0,
            detectedRenames: 0,
            detectedDeletes: 0,
            detectedModifies: 0,
            errors: ["rename pairing failed"]
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func detailLogExternalRenamed(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "外部重命名同步失败",
            severity: .medium,
            suggestedAction: "请确认重命名后的文件仍在资料库内，并重试改动时间线。",
            recoverability: .userActionRequired,
            rawContext: "S1-13 C1-18 sync_external_changes Renamed"
        )
    }
}

private func makeDetailLogExternalRenamedTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixDetailExternalRenamed-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
