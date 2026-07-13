@testable import AreaMatrix
import XCTest

final class ImportBatchResultSummaryTests: XCTestCase {
    @MainActor
    func testImportBatchPreviewErrorAndPartialSuccessSurfaceFailedItemInResultSummary() async {
        let readyURL = importBatchInvoiceURL()
        let failedPreviewURL = importBatchUnreadablePreviewURL()
        let rows = [
            importBatchReadyBatchRow(url: readyURL),
            ImportBatchPreviewRow.failed(
                url: failedPreviewURL,
                message: importBatchUnreadablePreviewMessage(url: failedPreviewURL)
            )
        ]
        let importer = ImportBatchRecordingBatchImporter()
        let model = importBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(
            rows,
            request: importBatchResultSummaryRequest(urls: [readyURL, failedPreviewURL]),
            selectedDestination: .autoClassify
        )
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        await importer.assertImportedBatchFiles([importBatchExpectedInvoiceRequest()])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.previewErrorCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), importBatchProgress(
            completed: 1,
            failed: 1,
            total: 2,
            currentPath: "finance/Invoice_2026Q1.pdf",
            items: [
                importBatchProgressItem(
                    fileID: 42,
                    sourcePath: importBatchSourcePath(),
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .done
                )
            ]
        ))
    }

    @MainActor
    func testImportBatchSkippedDuplicateAndPendingICloudSurfaceInProgressResultSummary() async {
        let duplicateURL = importBatchInvoiceURL()
        let cloudURL = importBatchICloudPlaceholderURL()
        let rows = [
            importBatchDuplicateInvoiceRow(url: duplicateURL),
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: cloudURL,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        ]
        let model = importBatchCopyImportModel()

        model.applyPreviewRows(
            rows,
            request: importBatchResultSummaryRequest(urls: [duplicateURL, cloudURL]),
            selectedDestination: .autoClassify
        )
        model.markICloudPlaceholderPending(rowID: rows[1].id)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries, [])
        XCTAssertEqual(outcome?.skippedDuplicateCount, 1)
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), importBatchProgress(
            completed: 0,
            total: 2,
            remaining: 0,
            currentPath: "Import ready only",
            skipped: 1,
            pending: 1
        ))
    }
}
