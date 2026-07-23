@testable import AreaMatrix
import XCTest

final class ImportFolderPreviewImportTests: XCTestCase {
    @MainActor
    func testImportFolderFolderCopyImportUsesRealImporterForReadyRowsOnly() async {
        let invoiceURL = importBatchInvoiceURL()
        let cloudURL = importBatchICloudPlaceholderURL()
        let errorURL = importBatchUnreadablePreviewURL()
        let scanner = ImportFolderStaticFolderScanner(result: importFolderFolderScanResult(rows: [
            importFolderLoadingRow(invoiceURL),
            importFolderLoadingRow(cloudURL).withStatus(.iCloudPlaceholder(path: cloudURL.path)),
            importFolderLoadingRow(errorURL).withStatus(
                .error(L10n.verbatim("无法读取文件属性", reason: .technicalDetail))
            )
        ]))
        let predictor = ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction(
            category: "finance",
            suggestedName: "Invoice_2026Q1.pdf"
        ))])
        let importer = ImportBatchRecordingBatchImporter()
        let model = makeImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            scanner: scanner
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        await model.load(request: importFolderFolderRequest(rootURL: importBatchFixtureRootURL()))
        let outcome = await model.importReadyFiles { progress in
            progressSnapshots.append(progress)
        }

        await importer.assertImportedBatchFiles([importBatchExpectedInvoiceRequest()])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.previewErrorCount, 1)
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        assertImportRowStatusTags(model.rows, ["IMPORTED", "ICLOUD", "ERROR"])
        XCTAssertEqual(progressSnapshots.last?.completed, 1)
        XCTAssertEqual(progressSnapshots.last?.failed, 0)
        XCTAssertEqual(progressSnapshots.last?.total, 1)
        XCTAssertEqual(progressSnapshots.last?.remaining, 0)
        XCTAssertEqual(progressSnapshots.last?.currentPath, "finance/Invoice_2026Q1.pdf")
        XCTAssertEqual(progressSnapshots.last?.items.map(\.phase), [.done, .pending, .failed])
        XCTAssertEqual(progressSnapshots.last?.items.last?.errorMessage, "Cannot preview category: missing test result")
    }

    @MainActor
    func testImportFolderFolderResultSummaryKeepsPerRowStatusesForFailureAndPendingRows() async {
        let invoiceURL = importBatchInvoiceURL()
        let cloudURL = importBatchICloudPlaceholderURL()
        let scanner = ImportFolderStaticFolderScanner(result: importFolderFolderScanResult(rows: [
            importFolderLoadingRow(invoiceURL),
            importFolderLoadingRow(cloudURL).withStatus(.iCloudPlaceholder(path: cloudURL.path))
        ]))
        let predictor = ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction(
            category: "finance",
            suggestedName: "Invoice_2026Q1.pdf"
        ))])
        let importer = ImportBatchSequenceBatchImporter(results: [
            .failure(CoreError.PermissionDenied(path: invoiceURL.path))
        ])
        let model = makeImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: importBatchFixtureRootURL()))
        let outcome = await model.importReadyFiles()
        let summary = outcome?.progressSnapshot(currentPath: "finance/Invoice_2026Q1.pdf")
            .withItems(model.progressItems())

        XCTAssertEqual(summary, importBatchProgress(
            completed: 0,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            pending: 1,
            items: [
                importBatchProgressItem(
                    sourcePath: invoiceURL.path,
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .failed,
                    errorMessage: "无访问权限"
                ),
                importBatchProgressItem(
                    sourcePath: cloudURL.path,
                    targetPath: cloudURL.lastPathComponent,
                    phase: .pending
                )
            ]
        ))
    }

    @MainActor
    func testImportFolderFolderCopyImportMapsCoreFailureWithoutStaticSuccess() async {
        let invoiceURL = importBatchInvoiceURL()
        let scanner = ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: invoiceURL,
                rootURL: importBatchFixtureRootURL()
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = ImportFolderRecordingPredictor(results: [
            .success(.importFolderPrediction(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf"
            ))
        ])
        let importer = ImportBatchSequenceBatchImporter(results: [
            .failure(CoreError.PermissionDenied(path: invoiceURL.path))
        ])
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = makeImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: errorMapper,
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: importBatchFixtureRootURL()))
        let outcome = await model.importReadyFiles()

        await errorMapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: invoiceURL.path)])
        XCTAssertEqual(outcome?.succeededEntries, [])
        XCTAssertEqual(outcome?.failedCount, 1)
        assertImportRowStatusTags(model.rows, ["ERROR"])
        assertImportRowStatusDetails(model.rows, [0: "无访问权限"])
        XCTAssertEqual(model.lastFailureMapping?.kind, .permissionDenied)
    }

    @MainActor
    func testImportFolderFolderCopyImportHonorsDropDestinationCategory() async {
        let invoiceURL = importBatchInvoiceURL()
        let scanner = ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: invoiceURL,
                rootURL: importBatchFixtureRootURL()
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = ImportFolderRecordingPredictor(results: [
            .success(.importFolderPrediction(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf"
            ))
        ])
        let importer = ImportBatchRecordingBatchImporter()
        let model = makeImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            scanner: scanner
        )
        let request = importFolderFolderRequest(
            rootURL: importBatchFixtureRootURL(),
            destination: .category("docs")
        )

        await model.load(request: request)
        _ = await model.importReadyFiles()

        await importer.assertImportedBatchFiles([
            importBatchExpectedInvoiceRequest(destination: .category("docs"), suggestedCategory: "docs")
        ])
    }

    @MainActor
    func testImportFolderFolderIndexOnlyImportCallsImportIndexFileCoreImporterForReadyRows() async {
        let sourceURL = importBatchFixtureFileURL("reference.pdf")
        let scanner = ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: sourceURL,
                rootURL: importBatchFixtureRootURL()
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = ImportFolderRecordingPredictor(results: [
            .success(.importFolderPrediction(
                category: "finance",
                suggestedName: "indexed-reference.pdf"
            ))
        ])
        let importer = ImportBatchRecordingBatchImporter()
        let model = makeImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: importBatchFixtureRootURL()))
        model.selectedStorageMode = .indexOnly
        let outcome = await model.importReadyFiles()

        await importer.assertImportedBatchFiles([
            importBatchExpectedInvoiceRequest(
                storageMode: .indexOnly,
                overrideFilename: "indexed-reference.pdf"
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.first?.storageMode, "Indexed")
        assertImportRowStatusDetails(model.rows, [0: "Added to index"])
    }

    @MainActor
    func testImportFolderFolderMoveUsesRealCoreImportMode() async {
        let sourceURL = importBatchFixtureFileURL("move-later.pdf")
        let scanner = ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: sourceURL,
                rootURL: importBatchFixtureRootURL()
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = ImportFolderRecordingPredictor(results: [
            .success(.importFolderPrediction(
                suggestedName: "move-later.pdf",
                reason: .extension,
                confidence: 0.7
            ))
        ])
        let importer = ImportBatchRecordingBatchImporter()
        let model = makeImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: importBatchFixtureRootURL()))
        model.selectedStorageMode = .move
        assertImportEnabled(model.importDisabledReason)
        let outcome = await model.importReadyFiles()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        await importer.assertImportedBatchFiles([
            importBatchExpectedInvoiceRequest(
                storageMode: .move,
                suggestedCategory: "docs",
                overrideFilename: "move-later.pdf"
            )
        ])
    }
}
