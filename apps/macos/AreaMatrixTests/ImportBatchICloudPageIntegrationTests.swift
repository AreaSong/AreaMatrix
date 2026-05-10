@testable import AreaMatrix
import XCTest

final class ImportBatchICloudPageIntegrationTests: XCTestCase {
    @MainActor
    func testS118ICloudPendingRowsDoNotSilentlyImportUnavailableRows() async {
        let localURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let request = s118BatchRequest(urls: [localURL, cloudURL])
        let rows = [
            s118ReadyBatchRow(url: localURL),
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: cloudURL,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        ]
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.iCloudPlaceholderCount, 1)
        XCTAssertNil(model.importDisabledReason)

        model.markICloudPlaceholderPending(rowID: rows[1].id)
        XCTAssertNil(model.importDisabledReason)

        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.succeededEntries.first?.storageMode, "Copied")
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            skipped: 0,
            pending: 1
        ))
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
    }

    @MainActor
    func testS118AllICloudPendingStillBlocksImport() {
        let cloudURLs = [
            URL(fileURLWithPath: "/tmp/iCloudOnlyA.pdf.icloud"),
            URL(fileURLWithPath: "/tmp/iCloudOnlyB.pdf.icloud")
        ]
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: cloudURLs,
            kind: .multipleItems(2),
            availableCategories: ["inbox", "finance"]
        )
        let rows = cloudURLs.map { url in
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: url,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        }
        let model = ImportBatchCopyImportModel(
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)

        XCTAssertEqual(model.iCloudPlaceholderCount, 2)
        XCTAssertEqual(model.importDisabledReason, "没有可导入的批量项目")
    }
}
