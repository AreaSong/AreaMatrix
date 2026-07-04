@testable import AreaMatrix
import XCTest

final class ImportBatchResultSummaryTests: XCTestCase {
    @MainActor
    // swiftlint:disable:next function_body_length
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
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.previewErrorCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            skipped: 0,
            pending: 0,
            items: [
                ImportBatchProgressSnapshot.Item(
                    fileID: 42,
                    sourcePath: importBatchSourcePath(),
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .done,
                    errorMessage: nil
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
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "Import ready only",
            skipped: 1,
            pending: 1
        ))
    }
}
