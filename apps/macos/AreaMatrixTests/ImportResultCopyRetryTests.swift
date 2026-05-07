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
}

private extension ImportResultCopyRetryTests {
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
