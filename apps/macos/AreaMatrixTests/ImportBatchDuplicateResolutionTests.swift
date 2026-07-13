@testable import AreaMatrix
import XCTest

final class ImportBatchDuplicateResolutionTests: XCTestCase {
    @MainActor
    func testImportConflictBatchManualScopeWithoutSelectionShowsSelectAtLeastOneConflict() async {
        let invoiceURL = importBatchInvoiceURL()
        let batcher = ImportConflictBatcher(previews: [.importConflictBatchMixedPreview()])
        let model = importConflictBatchIntegrationModel(
            conflictBatcher: batcher,
            undoStore: ImportConflictBatchIntegrationUndoStore()
        )

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchIntegrationRequest(
                urls: [invoiceURL],
                conflictIDs: ["dup-1", "name-1"]
            ),
            selectedDestination: .autoClassify
        )
        await model.loadImportConflictBatchPreview()
        model.updateConflictBatchScope(appliesToAll: false)
        await model.refreshImportConflictBatchPreview()
        let applyResult = await model.applyImportConflictBatch()
        let askResult = await model.askConflictBatchPerItem()

        XCTAssertEqual(model.conflictBatchScopeSummary, "Select at least one conflict.")
        XCTAssertEqual(model.conflictBatchApplyDisabledReason, "Select at least one conflict.")
        XCTAssertEqual(model.conflictBatchAskPerItemDisabledReason, "Select at least one conflict.")
        XCTAssertEqual(model.coreConflictBatchRows.map(\.status), [.pending, .pending])
        XCTAssertNil(applyResult)
        XCTAssertNil(askResult)
        await batcher.assertImportConflictPreviewRequestCount(1)
        await batcher.assertNoImportConflictApplyRequests()
    }

    @MainActor
    func testImportConflictBatchAskPerItemRoutesSelectedConflicts() async {
        let invoiceURL = importBatchInvoiceURL()
        let batcher = ImportConflictBatcher(previews: [
            .importConflictBatchMixedPreview(),
            .importConflictBatchMixedPreview()
        ])
        let model = importConflictBatchIntegrationModel(
            conflictBatcher: batcher,
            undoStore: ImportConflictBatchIntegrationUndoStore()
        )

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchIntegrationRequest(
                urls: [invoiceURL],
                conflictIDs: ["dup-1", "name-1"]
            ),
            selectedDestination: .autoClassify
        )
        await model.loadImportConflictBatchPreview()
        model.updateConflictBatchScope(appliesToAll: false)
        model.setConflictBatchItemSelected("name-1", isSelected: true)
        let result = await model.askConflictBatchPerItem()

        XCTAssertEqual(result?.report?.queuedForPerItemCount, 1)
        XCTAssertEqual(model.conflictBatchPerItemRouteLabels, ["name-conflict conflict-name"])
        XCTAssertEqual(model.conflictBatchPerItemQueue?.routes.map(\.conflictID), ["name-1"])
        XCTAssertEqual(model.conflictBatchPerItemQueue?.routes.map(\.replaceConfirmationRouteLabel), [
            "replace-confirm replace-confirm"
        ])
        await batcher.assertLastImportConflictApplyRequest(
            duplicateStrategy: .askPerItem,
            conflictIDs: ["name-1"]
        )
    }

    @MainActor
    func testDuplicateFileErrorFromCoreImportBecomesVisibleConflictAndStopsBatch() async {
        let fixture = importBatchStandardBatchFixture()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.importSingleFileFixture(currentName: "2026Q1_合同.pdf", category: "docs"))
        ])
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: errorMapper
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(fixture.rows, request: fixture.request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify) { progress in
            progressSnapshots.append(progress)
        }

        await importer.assertImportedBatchFiles([importBatchExpectedInvoiceRequest()])
        await errorMapper.assertMappedCoreErrors([])
        XCTAssertEqual(outcome?.succeededEntries.count, 0)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.total, 2)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 1)
        assertImportRowStatusTags(model.rows, ["DUP", "OK"])
        assertImportRowStatusDetails(model.rows, [0: "Skip: finance/existing-invoice.pdf"])
        XCTAssertEqual(model.status, .idle)
        XCTAssertEqual(progressSnapshots.last, importBatchProgress(
            completed: 0,
            total: 2,
            currentPath: "finance/Invoice_2026Q1.pdf"
        ))
    }

    @MainActor
    func testCoreDetectedDuplicateSurvivesPreviewReapplyAndCanRetryKeepBoth() async {
        let invoiceURL = importBatchInvoiceURL()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1 2.pdf", category: "finance"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let rows = [importBatchReadyBatchRow(url: invoiceURL)]
        let request = importBatchBatchRequest(urls: [invoiceURL])

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        await importer.assertImportedBatchFiles([
            importBatchExpectedInvoiceRequest(),
            importBatchExpectedInvoiceRequest(duplicateStrategy: .keepBoth)
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        assertImportRowStatusTags(model.rows, ["IMPORTED"])
    }

    @MainActor
    func testCoreDetectedDuplicateDefaultsToSkipAfterUserRetriesImport() async {
        let fixture = importBatchStandardBatchFixture()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.importSingleFileFixture(currentName: "2026Q1_合同.pdf", category: "docs"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(fixture.rows, request: fixture.request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        await importer.assertImportedBatchFiles(importBatchExpectedAutoClassifyRequests())
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.total, 1)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        XCTAssertEqual(model.skippedDuplicateCount, 1)
        assertImportRowStatusTags(model.rows, ["SKIPPED", "IMPORTED"])
        assertImportRowStatusDetails(model.rows, [0: "Duplicate skipped: finance/existing-invoice.pdf"])
    }

    @MainActor
    func testCoreDetectedDuplicateCanImportKeepBothThroughCoreDuplicateStrategy() async {
        let invoiceURL = importBatchInvoiceURL()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1 2.pdf", category: "finance"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let rows = [importBatchReadyBatchRow(url: invoiceURL)]
        let request = importBatchBatchRequest(urls: [invoiceURL])

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        await importer.assertImportedBatchFiles([
            importBatchExpectedInvoiceRequest(),
            importBatchExpectedInvoiceRequest(duplicateStrategy: .keepBoth)
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        assertImportRowStatusTags(model.rows, ["IMPORTED"])
    }

    @MainActor
    func testShowExistingFileRevealsDuplicatePathFromPendingBatchRequest() {
        let revealer = RecordingRepositoryFileRevealer()
        let model = importBatchOnboardingModel(fileRevealer: revealer)
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importBatchRepoPath())

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: importBatchStandardBatchFixture().urls
        )
        model.showImportEntryExistingFile(relativePath: "finance/existing-invoice.pdf")

        revealer.assertRevealRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: importBatchRepoPath(),
            relativePath: "finance/existing-invoice.pdf"
        )])
        XCTAssertNil(model.toastMessage)
    }

    @MainActor
    func testShowExistingFileFailureReportsActionError() {
        let revealer =
            RecordingRepositoryFileRevealer(result: .failure(RepositoryFileActionError.fileMissing("missing.pdf")))
        let model = importBatchOnboardingModel(fileRevealer: revealer)
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importBatchRepoPath())

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: importBatchStandardBatchFixture().urls
        )
        model.showImportEntryExistingFile(relativePath: "finance/missing.pdf")

        revealer.assertRevealRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: importBatchRepoPath(),
            relativePath: "finance/missing.pdf"
        )])
        XCTAssertEqual(model.toastMessage, "Existing file cannot be shown in Finder.")
    }

    @MainActor
    func testCoreDetectedDuplicateKeepBothSurvivesFooterPreviewRowReapplyBeforeImport() async {
        let invoiceURL = importBatchInvoiceURL()
        let importer = ImportBatchSequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1 2.pdf", category: "finance"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let rows = [importBatchReadyBatchRow(url: invoiceURL)]
        let request = importBatchBatchRequest(urls: [invoiceURL])

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        await importer.assertImportedBatchFiles([
            importBatchExpectedInvoiceRequest(),
            importBatchExpectedInvoiceRequest(duplicateStrategy: .keepBoth)
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        assertImportRowStatusTags(model.rows, ["IMPORTED"])
    }
}

extension ImportConflictBatchPreviewReportSnapshot {
    static func importConflictBatchMixedPreview() -> ImportConflictBatchPreviewReportSnapshot {
        var preview = importConflictBatchPreview(canApply: true)
        preview.previewToken = "token-mixed"
        preview.duplicateConflictCount = 1
        preview.sameNameConflictCount = 1
        preview.replaceCount = 0
        preview.skipCount = 1
        preview.keepBothCount = 1
        preview.replaceConfirmationRequired = false
        preview.replaceConfirmationSummary = nil
        preview.items = [
            .importConflictBatchItem(conflictID: "dup-1", strategy: .skip, status: .ready),
            .importConflictBatchItem(conflictID: "name-1", strategy: .keepBoth, status: .ready)
                .withConflictType(.sameNameDifferentContent)
        ]
        return preview
    }
}

extension ImportConflictBatchPreviewItemSnapshot {
    func withConflictType(_ type: ImportConflictBatchConflictTypeSnapshot) -> ImportConflictBatchPreviewItemSnapshot {
        var item = self
        item.conflictType = type
        if type == .sameNameDifferentContent {
            item.existingPath = "docs/contract.pdf"
            item.incomingPath = "/tmp/contract.pdf"
            item.targetPath = "docs/contract 2.pdf"
        }
        return item
    }
}
