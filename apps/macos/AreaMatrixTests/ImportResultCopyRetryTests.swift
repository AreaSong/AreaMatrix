import XCTest
@testable import AreaMatrix

final class ImportResultCopyRetryTests: XCTestCase {
    @MainActor
    func testS121C106RetryFailedCopyItemUsesCoreBridgeImporterAndUpdatesResult() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let importer = S117RecordingImporter()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            S117ImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "failed.pdf",
                duplicateStrategy: .ask
            ),
        ])
        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 2, failed 0, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .imported])
        XCTAssertFalse(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }

    @MainActor
    func testS121C106RetryFailedCopyItemMapsErrorAndKeepsRetryableRow() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let importer = S117FailingImporter(error: CoreError.PermissionDenied(path: "/tmp/failed.pdf"))
        let errorMapper = S117RecordingErrorMapper()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            errorMapper: errorMapper,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/failed.pdf")])
        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.last?.status, .failed)
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
        XCTAssertTrue(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }

    @MainActor
    func testS121C113LoadsImportChangeLogThroughCoreBridge() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let lister = S121RecordingChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: "imported.pdf"),
        ])])
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.importedProgress)
        await model.loadImportResultChangeLog()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [S121ChangeLogRequest(repoPath: "/tmp/repo", filter: .importResultRecent)])
        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.changeLog, .loaded([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: "imported.pdf"),
        ]))
    }

    @MainActor
    func testS121C113MapsListChangesFailureInline() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let lister = S121RecordingChangeLogLister(results: [.failure(CoreError.Db(message: "change log locked"))])
        let errorMapper = S117RecordingErrorMapper()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            errorMapper: errorMapper,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.importedProgress)
        await model.loadImportResultChangeLog()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "change log locked")])
        guard case .importResult(let result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.changeLog, .failed(.s117Error(kind: .db)))
    }

    func testS121ChangeLogDetailSummaryRedactsImportedSourcePath() {
        let entry = ChangeLogEntrySnapshot.importResultFixture(
            detailJSON: #"{"source":"/Users/as/private/imported.pdf","mode":"copied","category":"docs"}"#
        )

        XCTAssertTrue(entry.detailSummary.contains("source: .../imported.pdf"))
        XCTAssertFalse(entry.detailSummary.contains("/Users/as/private"))
    }
}

private extension ImportResultCopyRetryTests {
    static let importedProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 1,
        remaining: 0,
        currentPath: "docs/imported.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            ),
        ]
    )

    static let failedCopyProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "docs/failed.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/failed.pdf",
                targetPath: "docs/failed.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            ),
        ]
    )
}

private struct S121ChangeLogRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

private actor S121RecordingChangeLogLister: CoreChangeLogListing {
    enum Result {
        case success([ChangeLogEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [S121ChangeLogRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requests.append(S121ChangeLogRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case .success(let entries):
            return entries
        case .failure(let error):
            throw error
        }
    }

    func recordedRequests() -> [S121ChangeLogRequest] {
        requests
    }
}

private extension ChangeLogEntrySnapshot {
    static func importResultFixture(
        id: Int64 = 1,
        filename: String = "imported.pdf",
        detailJSON: String = #"{"source":"/tmp/imported.pdf","mode":"copied","category":"docs"}"#
    ) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: id,
            fileID: 10,
            filename: filename,
            category: "docs",
            action: "imported",
            detailJSON: detailJSON,
            occurredAt: 1_700_000_000
        )
    }
}
