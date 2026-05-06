import XCTest
@testable import AreaMatrix

final class ImportBatchCopyPageIntegrationTests: XCTestCase {
    @MainActor
    func testS118BatchCopyImportExposesLastImportedEntryForExistingRefreshFlow() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )
        let rows = [
            ImportBatchPreviewRow.ready(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            ),
            ImportBatchPreviewRow.ready(
                url: contractURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "2026Q1_合同.pdf",
                    reason: .keyword,
                    confidence: 0.82
                )
            ),
        ]
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries.count, 2)
        XCTAssertEqual(outcome?.succeededEntries.last?.currentName, "2026Q1_合同.pdf")
        XCTAssertEqual(outcome?.lastImportedPath, "docs/2026Q1_合同.pdf")
        XCTAssertEqual(model.status, .imported(successful: 2, failed: 0))
    }

    @MainActor
    func testS118BatchCopyImportFailureKeepsProgressAndMappedErrorVisible() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .category("finance"),
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )
        let rows = [
            ImportBatchPreviewRow.ready(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            ),
            ImportBatchPreviewRow.ready(
                url: contractURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "2026Q1_合同.pdf",
                    reason: .keyword,
                    confidence: 0.82
                )
            ),
        ]
        let importer = S118SequenceBatchImporter(results: [
            .success(.s117Fixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .failure(CoreError.PermissionDenied(path: contractURL.path)),
        ])
        let errorMapper = S117RecordingErrorMapper()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: errorMapper
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(rows, request: request, selectedDestination: .category("finance"))
        let outcome = await model.importReadyFiles(selectedDestination: .category("finance")) { progress in
            progressSnapshots.append(progress)
        }

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 1)
        XCTAssertEqual(outcome?.lastImportedPath, "finance/Invoice_2026Q1.pdf")
        XCTAssertEqual(model.lastFailureMapping?.userMessage, "无访问权限")
        XCTAssertEqual(progressSnapshots.last, ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/2026Q1_合同.pdf"
        ))
    }
}
