@testable import AreaMatrix
import XCTest

final class ImportResultCopyRetryTests: XCTestCase {
    @MainActor
    func testImportResultImportCopyFileCoreRetryFailedCopyItemUsesCoreBridgeImporterAndUpdatesResult() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let importer = ImportSingleFileRecordingImporter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            ImportSingleFileImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: importResultFailedFilename(),
                duplicateStrategy: .ask
            )
        ])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 2, failed 0, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .imported])
        XCTAssertFalse(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }

    @MainActor
    func testImportResultRetryFailedRoutesThroughImportProgressProgressBeforeReturningResults() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let gate = ImportSingleFileImportGate()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: ImportSingleFileSuspendingImporter(gate: gate),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.failedCopyProgress)
        let retryTask = Task { await model.retryImportResultFailedItems() }
        await gate.waitUntilStarted()

        guard case let .importProgress(progress) = model.route else {
            await gate.finish()
            await retryTask.value
            return XCTFail("Expected import-progress import progress while retrying failed import-result items")
        }
        XCTAssertEqual(progress.resultSummaryText, "Imported 0, failed 0, stopped 0, pending 1.")
        XCTAssertEqual(progress.items.map(\.sourcePath), [importResultFailedSourcePath()])
        XCTAssertEqual(progress.items.map(\.phase), [.copying])

        await gate.finish()
        await retryTask.value
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result after retry completes")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 2, failed 0, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .imported])
    }

    @MainActor
    func testImportResultImportCopyFileCoreRetryFailedCopyItemMapsErrorAndKeepsRetryableRow() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let importer = ImportSingleFileFailingImporter(
            error: CoreError.PermissionDenied(path: importResultFailedSourcePath())
        )
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            errorMapper: errorMapper,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: importResultFailedSourcePath())])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.last?.status, .failed)
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
        XCTAssertTrue(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }
}
