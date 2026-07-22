@testable import AreaMatrix
import XCTest

final class ImportConflictIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testImportConflictLoopsUseRealWiring() async throws {
        XCTAssertEqual(Self.coveredCoreCapabilities, [
            "classify-preview", "import-copy-file", "import-move-file", "import-index-file", "detect-duplicate",
            "resolve-name-conflict",
            "change-log-core", "undo-action-log", "import-conflict-batch-core"
        ])

        try await verifyHoverAndEntryRouting()
        try await verifySingleFileProgressStartsBeforeCoreImportCompletes()
        try await verifySingleFileConflictPagesBlockReplaceUntilConfirmation()
        try await verifyBatchAndFolderConflictImports()
        try await verifyProgressResultAndChangeLogRoutes()
        try await verifyImportConflictBatchImportConflictBatchPageIntegration()
    }
}

private extension ImportConflictIntegrationVerifyTests {
    static let coveredCoreCapabilities: Set<String> = [
        "classify-preview", "import-copy-file", "import-move-file", "import-index-file", "detect-duplicate",
        "resolve-name-conflict",
        "change-log-core", "undo-action-log", "import-conflict-batch-core"
    ]

    @MainActor
    func verifyHoverAndEntryRouting() async throws {
        let sourceURL = importBatchInvoiceURL()
        let predictor = ImportSingleFileRecordingPredictor(result: .testFixture(
            category: "finance",
            suggestedName: "Invoice_2026Q1.pdf",
            reason: .keyword,
            confidence: 0.9
        ))
        let dropModel = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await dropModel.preview(target: .autoClassify, urls: [sourceURL])
        await predictor.assertCategoryPredictionRequests([
            ImportSingleFilePredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf")
        ])
        XCTAssertEqual(dropModel.presentation?.destinationLabel, "finance")
        XCTAssertEqual(dropModel.presentation?.headline, "Drop files to import")

        let fixture = makeImportSingleFileMainListFixture()
        let opening = fixture.opening
        let model = fixture.model
        model.startImportEntry(opening: opening, source: .dropZone, urls: [sourceURL])

        XCTAssertEqual(model.pendingImportEntry?.kind, .singleFile)
        XCTAssertEqual(model.pendingImportEntry?.destination, .autoClassify)
    }

    @MainActor
    func verifySingleFileProgressStartsBeforeCoreImportCompletes() async throws {
        let gate = ImportSingleFileImportGate()
        let importer = ImportSingleFileSuspendingImporter(gate: gate)
        var events: [String] = []
        let previewModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let runner = ImportEntrySingleFileImportRunner(
            request: .importSingleFileFixture(),
            previewModel: previewModel,
            onImportStarted: { path, mode in
                events.append("progress:\(path):\(mode.rawValue)")
            },
            onImportStartedWithRetryContext: { path, _, mode, _, _, _ in
                events.append("progress-context:\(path):\(mode.rawValue)")
            },
            onImportFailed: { _, _ in
                events.append("failed")
            },
            onImported: { _, entry in
                events.append("imported:\(entry.path)")
            }
        )

        await previewModel.load(request: .importSingleFileFixture())
        let task = Task { @MainActor in
            await runner.run()
        }
        await gate.waitUntilStarted()

        XCTAssertEqual(events, ["progress-context:docs/source.pdf:Copy"])

        await gate.finish()
        await task.value

        XCTAssertEqual(events, [
            "progress-context:docs/source.pdf:Copy",
            "imported:docs/source.pdf"
        ])
    }

    @MainActor
    func verifySingleFileConflictPagesBlockReplaceUntilConfirmation() async throws {
        let importer = ImportSingleFileRecordingImporter()
        let duplicateModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: importConflictDuplicatePreflight()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        await duplicateModel.load(request: .importSingleFileFixture())
        duplicateModel.updateDuplicateResolution(.replace)
        XCTAssertEqual(duplicateModel.activeConflictPage, .duplicate)
        assertImportEnabled(duplicateModel.importDisabledReason)
        let blockedImport = await duplicateModel.importSelectedFile()

        XCTAssertNil(blockedImport)
        await importer.assertNoImportedFiles()
        XCTAssertEqual(duplicateModel.importStatus, .blocked("Confirm Replace before continuing"))

        duplicateModel.beginReplaceConfirmation()
        let duplicateContext = try XCTUnwrap(duplicateModel.pendingReplaceConfirmation)
        duplicateModel.applyReplaceConfirmation(duplicateContext.decision(understandsReplace: true))
        _ = await duplicateModel.importSelectedFile()

        await importer.assertImportedFiles([
            ImportSingleFileImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "source.pdf",
                duplicateStrategy: .overwrite
            )
        ])

        let nameModel = ImportSingleFilePreviewModel(
            predictor: ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
            importer: ImportSingleFileRecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: importConflictNamePreflight()),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        await nameModel.load(request: .importSingleFileFixture())
        nameModel.updateNameConflictResolution(.renameIncoming("renamed.pdf"))

        XCTAssertEqual(nameModel.activeConflictPage, .name)
        XCTAssertEqual(nameModel.resolvedImportRelativePath, "docs/renamed.pdf")
        assertImportEnabled(nameModel.importDisabledReason)
    }

    @MainActor
    func verifyBatchAndFolderConflictImports() async throws {
        try await verifyBatchConflictImport()
        try await verifyFolderConflictImport()
    }

    @MainActor
    func verifyBatchConflictImport() async throws {
        let invoiceURL = importBatchInvoiceURL()
        let contractURL = URL(fileURLWithPath: "/tmp/contract.pdf")
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let rows = [
            ImportBatchPreviewRow.duplicate(
                url: invoiceURL,
                prediction: .importFolderPrediction(category: "finance", suggestedName: "Invoice_2026Q1.pdf"),
                existingPath: "finance/Invoice_2026Q1.pdf"
            ),
            ImportBatchPreviewRow.nameConflict(
                url: contractURL,
                prediction: .importFolderPrediction(category: "docs", suggestedName: "contract.pdf"),
                existingPath: "docs/contract.pdf"
            )
        ]

        model.applyPreviewRows(
            rows,
            request: importConflictBatchRequest(urls: [invoiceURL, contractURL]),
            selectedDestination: .autoClassify
        )
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .replace)
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)
        let blockedOutcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertNil(blockedOutcome)
        await importer.assertNoImportedBatchFiles()

        let context = try XCTUnwrap(model.beginReplaceConfirmation(for: rows[0].id))
        XCTAssertTrue(model.applyReplaceConfirmation(
            for: rows[0].id,
            decision: context.decision(understandsReplace: true)
        ))
        model.renameIncomingFile(for: rows[1].id, to: "contract-renamed.pdf")
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries.count, 2)
        await importer.assertImportedBatchFiles(importConflictExpectedBatchRequests())
    }

    @MainActor
    func verifyFolderConflictImport() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/client-a")
        let duplicateURL = rootURL.appendingPathComponent("dup.pdf")
        let importer = ImportBatchRecordingBatchImporter()
        let scanner = ImportFolderStaticFolderScanner(result: importFolderFolderScanResult(rows: [
            ImportFolderPreviewRow.loading(fileURL: duplicateURL, rootURL: rootURL)
        ]))
        let prechecker = ImportFolderStaticConflictPrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf")
        ])
        let model = ImportFolderPreviewModel(
            predictor: ImportFolderRecordingPredictor(
                results: [.success(.importFolderPrediction(suggestedName: "dup.pdf"))]
            ),
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: prechecker,
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: rootURL, allowReplaceDuringImport: true))
        model.updateDuplicateStrategy(for: duplicateURL.path, strategy: .replace)
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)
        let blockedOutcome = await model.importReadyFiles()
        XCTAssertNil(blockedOutcome)

        let context = try XCTUnwrap(model.beginReplaceConfirmation(for: duplicateURL.path))
        XCTAssertTrue(model.applyReplaceConfirmation(
            for: duplicateURL.path,
            decision: context.decision(understandsReplace: true)
        ))
        let outcome = await model.importReadyFiles()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        await importer.assertImportedDuplicateStrategies([.overwrite])
        assertImportRowStatusTags(model.rows, ["IMPORTED"])
    }

    @MainActor
    func verifyProgressResultAndChangeLogRoutes() async throws {
        let lister = ImportConflictChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.importConflictFixture(filename: "Invoice_2026Q1.pdf")
        ])])
        let model = makeImportResultMainListFixture(importResultChangeLister: lister).model
        let progress = importBatchProgress(
            completed: 1,
            failed: 1,
            total: 3,
            remaining: 0,
            currentPath: "docs/contract.pdf",
            skipped: 1,
            items: importConflictProgressItems()
        )

        model.updateImportEntryProgress(progress)
        guard let route = requireImportProgressRoute(
            model,
            message: "Expected import-progress import progress route"
        ) else { return }
        XCTAssertEqual(route.resultSummaryText, "Imported 1, failed 1, stopped 1, pending 0.")

        model.showImportEntryResults(progress)
        await model.loadImportResultChangeLog()

        await lister.assertChangeLogListRequests([
            ImportConflictChangeLogRequest(repoPath: "/tmp/repo", filter: .importResultRecent)
        ])
        guard let result = requireImportResultRoute(
            model,
            message: "Expected import-result import result route"
        ) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 1, stopped 1, pending 0.",
            statuses: [.imported, .failed, .skipped]
        )
        XCTAssertEqual(result.items[2].existingRelativePath, "finance/Invoice_2026Q1.pdf")
        XCTAssertEqual(result.changeLog, .loaded([
            ChangeLogEntrySnapshot.importConflictFixture(filename: "Invoice_2026Q1.pdf")
        ]))
    }

    @MainActor
    func verifyImportConflictBatchImportConflictBatchPageIntegration() async throws {
        try await verifyImportConflictBatchBlockedPreviewDoesNotApply()
        try await verifyImportConflictBatchSelectedScopeRefreshesBeforeApplyAndUndo()
    }

    @MainActor
    func verifyImportConflictBatchBlockedPreviewDoesNotApply() async throws {
        let invoiceURL = importBatchInvoiceURL()
        let blockedBatcher =
            ImportConflictBatcher(previews: [.importConflictBatchPreview(canApply: false)])
        let blockedModel = importConflictBatchIntegrationModel(
            conflictBatcher: blockedBatcher,
            undoStore: ImportConflictBatchIntegrationUndoStore()
        )

        blockedModel.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchIntegrationRequest(urls: [invoiceURL], conflictIDs: ["dup-blocked"]),
            selectedDestination: .autoClassify
        )
        await blockedModel.loadImportConflictBatchPreview()
        let blockedResult = await blockedModel.applyImportConflictBatch(replaceConfirmed: true)

        XCTAssertNil(blockedResult)
        XCTAssertEqual(blockedModel.conflictBatchApplyDisabledReason, "Blocked: Trash unavailable")
        await blockedBatcher.assertNoImportConflictApplyRequests()
    }

    @MainActor
    func verifyImportConflictBatchSelectedScopeRefreshesBeforeApplyAndUndo() async throws {
        let invoiceURL = importBatchInvoiceURL()
        let action = UndoActionRecordSnapshot.importConflictBatchIntegrationAction()
        let undoResult = UndoActionResultSnapshot.importConflictBatchIntegrationResult()
        let undoStore = ImportConflictBatchIntegrationUndoStore(
            actions: .success([action]),
            undoResult: .success(undoResult)
        )
        let batcher = ImportConflictBatcher(previews: [
            .importConflictBatchPreview(canApply: true),
            .importConflictBatchPreview(canApply: true)
        ])
        let model = importConflictBatchIntegrationModel(conflictBatcher: batcher, undoStore: undoStore)

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchIntegrationRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
            selectedDestination: .autoClassify
        )
        model.updateConflictBatchDuplicateStrategy(.replace)
        await model.loadImportConflictBatchPreview()
        model.updateConflictBatchScope(appliesToAll: false)
        model.setConflictBatchItemSelected("dup-1", isSelected: true)
        await model.refreshImportConflictBatchPreview()

        XCTAssertTrue(model.showsCoreConflictBatchReview)
        XCTAssertEqual(model.conflictBatchScopeSummary, "Will apply to 1 selected conflict.")
        XCTAssertNil(model.conflictBatchApplyDisabledReason)
        let unconfirmedApply = await model.applyImportConflictBatch(replaceConfirmed: false)
        XCTAssertNil(unconfirmedApply)
        await batcher.assertNoImportConflictApplyRequests()

        let applied = await model.applyImportConflictBatch(replaceConfirmed: true)
        await model.undoImportConflictBatchAction()

        XCTAssertEqual(applied?.report?.replacedCount, 1)
        XCTAssertEqual(model.conflictBatchUndoState, .undone(undoResult))
        await batcher.assertImportConflictPreviewStrategies([.replace, .replace])
        await batcher.assertImportConflictPreviewScopes([true, false])
        await batcher.assertImportConflictApplyRequests([
            ImportConflictApplyRequest(
                repoPath: "/tmp/repo",
                request: .testFixture(applyToAllSimilarConflicts: false),
                previewToken: "token-replace"
            )
        ])
        await undoStore.assertUndoActionListRequests(["/tmp/repo"])
        await undoStore.assertUndoActionRequests(["/tmp/repo|undo-import-conflict-batch"])
    }
}
