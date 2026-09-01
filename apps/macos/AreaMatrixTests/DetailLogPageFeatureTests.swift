@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import XCTest

final class DetailLogPageFeatureTests: XCTestCase {
    @MainActor
    func testDetailLogLoadsSelectedFileChangeLogThroughListChangeLogCoreListChanges() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 16, currentName: "logged.pdf")
        let entry = ChangeLogEntrySnapshot.detailLogFixture(fileID: detail.id, action: "imported")
        let lister = DetailLogRecordingLister(results: [.success([entry])])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: lister,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()

        await lister.assertChangeLogListRequests([
            DetailLogRequest(repoPath: "/tmp/repo", filter: .detailLog(fileID: detail.id))
        ])
        XCTAssertEqual(model.detailLogState, .loaded(fileID: detail.id, entries: [entry]))
    }

    @MainActor
    func testDetailLogMapsListChangesFailureInline() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 17, currentName: "locked.pdf")
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: DetailLogRecordingLister(results: [.failure(CoreError.Db(message: "change log locked"))]),
            errorMapper: mapper
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()

        XCTAssertEqual(model.detailLogState, .failed(fileID: detail.id, mapping))
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "change log locked")])
    }

    @MainActor
    func testDetailLogStaleChangeLogRequestDoesNotOverwriteNewSelection() async {
        let oldFile = FileEntrySnapshot.detailMetaFixture(id: 18, currentName: "old.pdf")
        let newFile = FileEntrySnapshot.detailMetaFixture(id: 19, currentName: "new.pdf")
        let lister = DetailLogSuspendedLister(entries: [
            ChangeLogEntrySnapshot.detailLogFixture(fileID: oldFile.id, action: "imported")
        ])
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [oldFile, newFile]),
            fileLister: NoopFileLister(),
            fileDetailer: RecordingFileDetailer(results: [.success(oldFile), .success(newFile)]),
            changeLogLister: lister,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await model.selectFiles([oldFile.id])
        let loadTask = Task { await model.loadSelectedFileChangeLog() }
        await lister.waitForRequest()
        await model.selectFiles([newFile.id])
        await lister.finish()
        await loadTask.value

        XCTAssertEqual(model.selection, .single(newFile.id))
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testDetailLogDetailLogDiagnosticsRequiresPrivacyConfirmationAndCollectsCoreSnapshot() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 20, currentName: "diagnostics.pdf")
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(
            snapshotPath: "/tmp/repo/.areamatrix/diagnostics/detail-log.db",
            createdAt: 1_700_000_300,
            warnings: ["index.db-wal disappeared during snapshot"]
        )
        let diagnosticsCollector = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: DetailLogRecordingLister(results: [.failure(CoreError.Db(message: "change log locked"))]),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            diagnosticsCollector: diagnosticsCollector
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()
        await model.collectDetailLogDiagnostics()

        await diagnosticsCollector.assertNoRepoPathRequests()
        XCTAssertEqual(model.detailLogDiagnosticsState, .idle)

        model.requestDetailLogDiagnosticsPrivacyConfirmation()
        await model.collectDetailLogDiagnostics()

        await diagnosticsCollector.assertRequestedRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.detailLogDiagnosticsState, .collected(fileID: detail.id, snapshot))
    }

    @MainActor
    func testDetailLogDetailLogDiagnosticsFailureMapsCoreErrorInline() async {
        let detail = FileEntrySnapshot.detailMetaFixture(id: 21, currentName: "diagnostics-fail.pdf")
        let mapping = CoreErrorMappingSnapshot.detailLogDb()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let diagnosticsCollector = ShellRecordingDiagnosticsCollector(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))
        )
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [detail]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(detail)),
            changeLogLister: DetailLogRecordingLister(results: [.failure(CoreError.Db(message: "change log locked"))]),
            errorMapper: mapper,
            diagnosticsCollector: diagnosticsCollector
        )

        await model.selectFiles([detail.id])
        await model.loadSelectedFileChangeLog()
        model.requestDetailLogDiagnosticsPrivacyConfirmation()
        await model.collectDetailLogDiagnostics()

        XCTAssertEqual(model.detailLogDiagnosticsState, .failed(fileID: detail.id, mapping))
        await mapper.assertMappedCoreErrors([
            CoreError.Db(message: "change log locked"),
            CoreError.PermissionDenied(path: "/tmp/repo")
        ])
    }
}

private actor DetailLogSuspendedLister: CoreChangeLogListing {
    private let entries: [ChangeLogEntrySnapshot]
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    init(entries: [ChangeLogEntrySnapshot]) {
        self.entries = entries
    }

    func listChanges(repoPath _: String, filter _: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return entries
    }

    func waitForRequest() async {
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for detail log request" },
            value: {
                didReceiveRequest ? true : nil
            }
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
