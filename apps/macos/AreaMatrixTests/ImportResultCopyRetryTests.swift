@testable import AreaMatrix
import XCTest

final class ImportResultCopyRetryTests: XCTestCase {
    @MainActor
    func testImportResultImportCopyFileCoreRetryFailedCopyItemUsesCoreBridgeImporterAndUpdatesResult() async {
        let importer = ImportSingleFileRecordingImporter()
        let model = makeImportResultMainListFixture(importProgressImporter: importer).model

        guard showImportResultRoute(model, progress: ImportResultFixtures.failedCopyProgress) != nil else { return }
        await model.retryImportResultFailedItems()

        await importer.assertImportedFiles([
            ImportSingleFileImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: importResultFailedFilename(),
                duplicateStrategy: .ask
            )
        ])
        guard let result = requireImportResultRoute(model) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 2, failed 0, stopped 0, pending 0.",
            statuses: [.imported, .imported]
        )
        assertImportResultRetryAvailability(
            result,
            canRetryFailedItems: false,
            isRetryingFailedItems: false
        )
    }

    @MainActor
    func testImportResultRetryFailedRoutesThroughImportProgressProgressBeforeReturningResults() async {
        let gate = ImportSingleFileImportGate()
        let model = makeImportResultMainListFixture(
            importProgressImporter: ImportSingleFileSuspendingImporter(gate: gate)
        )
        .model

        guard showImportResultRoute(model, progress: ImportResultFixtures.failedCopyProgress) != nil else { return }
        let retryTask = Task { await model.retryImportResultFailedItems() }
        await gate.waitUntilStarted()

        guard let progress = requireImportProgressRoute(
            model,
            message: "Expected import-progress import progress while retrying failed import-result items"
        ) else {
            await gate.finish()
            await retryTask.value
            return
        }
        XCTAssertEqual(progress.resultSummaryText, "Imported 0, failed 0, stopped 0, pending 1.")
        XCTAssertEqual(progress.items.map(\.sourcePath), [importResultFailedSourcePath()])
        XCTAssertEqual(progress.items.map(\.phase), [.copying])

        await gate.finish()
        await retryTask.value
        guard let result = requireImportResultRoute(
            model,
            message: "Expected import-result import result after retry completes"
        ) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 2, failed 0, stopped 0, pending 0.",
            statuses: [.imported, .imported]
        )
    }

    @MainActor
    func testImportResultImportCopyFileCoreRetryFailedCopyItemMapsErrorAndKeepsRetryableRow() async {
        let importer = ImportSingleFileFailingImporter(
            error: CoreError.PermissionDenied(path: importResultFailedSourcePath())
        )
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = makeImportResultMainListFixture(
            importProgressImporter: importer,
            errorMapper: errorMapper
        ).model

        guard showImportResultRoute(model, progress: ImportResultFixtures.failedCopyProgress) != nil else { return }
        await model.retryImportResultFailedItems()

        await errorMapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: importResultFailedSourcePath())])
        guard let result = requireImportResultRoute(model) else { return }
        assertImportResultSummary(result, summaryText: "Imported 1, failed 1, stopped 0, pending 0.")
        guard let failedItem = requireImportResultItem(
            result,
            matching: { $0.status == .failed },
            message: "Expected failed retry import result item"
        ) else { return }
        XCTAssertEqual(failedItem.reason, L10n.string("error.unmapped.message"))
        assertImportResultRetryAvailability(
            result,
            canRetryFailedItems: true,
            isRetryingFailedItems: false
        )
    }
}
