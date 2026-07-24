@testable import AreaMatrix
import XCTest

final class ImportBatchCopyPageIntegrationTests: XCTestCase {
    @MainActor
    func testImportBatchBatchCopyImportExposesLastImportedEntryForExistingRefreshFlow() async {
        let fixture = importBatchStandardBatchFixture()
        let model = importBatchCopyImportModel()

        model.applyPreviewRows(fixture.rows, request: fixture.request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries.count, 2)
        XCTAssertEqual(outcome?.succeededEntries.last?.currentName, "2026Q1_合同.pdf")
        XCTAssertEqual(outcome?.lastImportedPath, "docs/2026Q1_合同.pdf")
        XCTAssertEqual(model.status, .imported(successful: 2, failed: 0))
    }

    @MainActor
    func testImportBatchBatchCopyImportFailureKeepsProgressAndMappedErrorVisible() async {
        let fixture = importBatchStandardBatchFixture(destination: .category("finance"))
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .failure(CoreError.PermissionDenied(path: fixture.contractURL.path))
        ])
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = importBatchCopyImportModel(importer: importer, errorMapper: errorMapper)
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(fixture.rows, request: fixture.request, selectedDestination: .category("finance"))
        let outcome = await model.importReadyFiles(selectedDestination: .category("finance")) { progress in
            progressSnapshots.append(progress)
        }

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 1)
        XCTAssertEqual(outcome?.lastImportedPath, "finance/Invoice_2026Q1.pdf")
        XCTAssertEqual(model.lastFailureMapping?.userMessage, L10n.string("error.unmapped.message"))
        XCTAssertEqual(progressSnapshots.last, importBatchProgress(
            completed: 1,
            failed: 1,
            currentPath: "finance/2026Q1_合同.pdf"
        ))
    }

    @MainActor
    func testImportBatchBatchImportRoutesThroughImportProgressProgressWithBatchCounts() {
        let fixture = makeImportBatchMainListFixture()
        let opening = fixture.opening
        let model = fixture.model
        let progress = importBatchProgress(
            completed: 1,
            currentPath: "docs/合同.pdf"
        )

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [importBatchInvoiceURL(), importBatchContractURL()]
        )
        model.updateImportEntryProgress(progress)

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: "docs/合同.pdf",
            status: .running,
            completed: 1,
            failed: 0,
            remaining: 1
        )))
        guard let state = requireImportProgressRoute(
            model,
            message: "Expected import-progress import progress route"
        ) else { return }
        XCTAssertEqual(state.titleText, "Importing 2 files")
        XCTAssertEqual(state.toolbarText, "Importing 1 / 2")
    }

    @MainActor
    func testImportBatchBatchImportFailureRoutesToImportResultResultInsteadOfFatalPause() {
        let fixture = makeImportBatchMainListFixture()
        let model = fixture.model
        let progress = importBatchProgress(
            completed: 1,
            failed: 1,
            currentPath: "finance/合同.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.importSingleFileError(kind: .permissionDenied)

        model.updateImportEntryProgress(progress)
        model.failImportEntry(progress: progress, mapping: mapping)

        guard let result = requireImportResultRoute(
            model,
            message: "Expected import-result import result route"
        ) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 1, stopped 0, pending 0.",
            statuses: [.failed]
        )
    }

    @MainActor
    func testImportProgressViewDetailsRoutesToImportResultImportResult() {
        let fixture = makeImportBatchMainListFixture()
        let model = fixture.model
        let progress = importBatchProgress(
            completed: 1,
            currentPath: "finance/合同.pdf"
        )

        model.updateImportEntryProgress(progress)
        model.viewImportProgressDetails()

        guard let result = requireImportResultRoute(
            model,
            message: "Expected import-result import result route"
        ) else { return }
        assertImportResultSummary(result, summaryText: "Imported 1, failed 0, stopped 0, pending 1.")
        XCTAssertEqual(result.currentPath, "finance/合同.pdf")
    }
}

final class ImportBatchCopyProgressIntegrationTests: XCTestCase {
    @MainActor
    func testImportBatchBatchImportProgressCanStartBeforeFirstCoreImportCompletes() async {
        let fixture = importBatchStandardBatchFixture()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .success(.importSingleFileFixture(currentName: "2026Q1_合同.pdf", category: "docs"))
        ])
        let model = importBatchCopyImportModel(importer: importer)
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(fixture.rows, request: fixture.request, selectedDestination: .autoClassify)
        let initialProgress = importBatchProgress(
            completed: 0,
            total: model.importableRows.count,
            remaining: model.importableRows.count,
            currentPath: model.currentImportPath ?? fixture.request.sheetTitle
        )
        progressSnapshots.append(initialProgress)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify) { progress in
            progressSnapshots.append(progress)
        }

        XCTAssertEqual(progressSnapshots.first, importBatchProgress(
            completed: 0,
            currentPath: "finance/Invoice_2026Q1.pdf"
        ))
        XCTAssertEqual(progressSnapshots.last, importBatchProgress(
            completed: 2,
            currentPath: "docs/2026Q1_合同.pdf"
        ))
    }

    @MainActor
    func testImportBatchPageIntegrationCoversNameConflictRenameAndReplaceConfirmation() async {
        let invoiceURL = importBatchInvoiceURL()
        let contractURL = importBatchContractURL()
        let request = importBatchBatchRequest(
            urls: [invoiceURL, contractURL],
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        )
        let rows = [
            importBatchReadyBatchRow(url: invoiceURL),
            importBatchNameConflictContractRow(url: contractURL)
        ]
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .success(.importSingleFileFixture(currentName: "合同-renamed.pdf", category: "docs"))
        ])
        let model = importBatchCopyImportModel(importer: importer)

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.nameConflictCount, 1)
        assertImportRowStatusTags(model.rows, ["OK", "NAME"])
        assertImportEnabled(model.importDisabledReason)

        model.renameIncomingFile(for: rows[1].id, to: "合同-renamed.pdf")
        let renamedOutcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        XCTAssertEqual(renamedOutcome?.succeededEntries.count, 2)

        await importer.assertLastImportedBatchFile(importBatchExpectedContractRequest(
            overrideFilename: "合同-renamed.pdf",
            duplicateStrategy: .keepBoth
        ))
    }

    @MainActor
    func testImportBatchReplaceRowsBlockImportUntilReplaceConfirmConfirmation() async {
        let invoiceURL = importBatchInvoiceURL()
        let request = importBatchBatchRequest(
            urls: [invoiceURL],
            availableCategories: ["inbox", "finance"],
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        )
        let rows = [importBatchDuplicateInvoiceRow(url: invoiceURL)]
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance"))
        ])
        let model = importBatchCopyImportModel(importer: importer)

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .replace)
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)

        guard let context = model.beginReplaceConfirmation(for: rows[0].id) else {
            return XCTFail("Expected replace-confirm replace-confirm context")
        }
        model.applyReplaceConfirmation(for: rows[0].id, decision: context.decision(understandsReplace: true))
        assertImportEnabled(model.importDisabledReason)

        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        await importer.assertImportedBatchFiles([importBatchExpectedInvoiceRequest(duplicateStrategy: .overwrite)])
    }

    @MainActor
    func testImportBatchTrashUnavailableKeepsNonReplaceDuplicateStrategiesSelectable() async {
        let invoiceURL = importBatchInvoiceURL()
        let request = importBatchBatchRequest(
            urls: [invoiceURL],
            availableCategories: ["inbox", "finance"],
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        )
        let rows = [importBatchDuplicateInvoiceRow(url: invoiceURL)]
        let importer = ImportBatchRecordingBatchImporter()
        let model = importBatchCopyImportModel(importer: importer)

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.replaceOptionVisibility, .disabled)

        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        assertImportEnabled(model.importDisabledReason)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        await importer.assertImportedBatchFiles([importBatchExpectedInvoiceRequest(duplicateStrategy: .keepBoth)])
    }

    @MainActor
    func testImportBatchTrashUnavailableRejectsReplaceButKeepsRenameIncomingSelectable() async {
        let contractURL = importBatchContractURL()
        let request = importBatchBatchRequest(
            urls: [contractURL],
            availableCategories: ["inbox", "docs"],
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        )
        let rows = [importBatchNameConflictContractRow(url: contractURL)]
        let importer = ImportBatchRecordingBatchImporter()
        let model = importBatchCopyImportModel(importer: importer)

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.updateNameConflictResolution(for: rows[0].id, resolution: .replace(isConfirmed: false))
        XCTAssertEqual(model.rows.first?.nameConflictResolution, .keepBoth)

        model.renameIncomingFile(for: rows[0].id, to: "合同-renamed.pdf")
        assertImportEnabled(model.importDisabledReason)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        await importer.assertImportedBatchFiles([importBatchExpectedContractRequest(
            overrideFilename: "合同-renamed.pdf",
            duplicateStrategy: .keepBoth
        )])
    }
}
