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
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(
            requests,
            [ImportSingleFilePredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf")]
        )
        XCTAssertEqual(dropModel.presentation?.destinationLabel, "finance")
        XCTAssertEqual(dropModel.presentation?.headline, "Drop files to import")

        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)
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
        XCTAssertEqual(duplicateModel.importDisabledReason, nil)
        let blockedImport = await duplicateModel.importSelectedFile()
        let requestsBeforeConfirmation = await importer.recordedRequests()

        XCTAssertNil(blockedImport)
        XCTAssertEqual(requestsBeforeConfirmation, [])
        XCTAssertEqual(duplicateModel.importStatus, .blocked("Replace 必须先进入二次确认"))

        duplicateModel.beginReplaceConfirmation()
        let duplicateContext = try XCTUnwrap(duplicateModel.pendingReplaceConfirmation)
        duplicateModel.applyReplaceConfirmation(duplicateContext.decision(understandsReplace: true))
        _ = await duplicateModel.importSelectedFile()

        let requests = await importer.recordedRequests()
        XCTAssertEqual(requests, [
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
        XCTAssertNil(nameModel.importDisabledReason)
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
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let blockedOutcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let requestsBeforeConfirmation = await importer.recordedRequests()

        XCTAssertNil(blockedOutcome)
        XCTAssertEqual(requestsBeforeConfirmation, [])

        let context = try XCTUnwrap(model.beginReplaceConfirmation(for: rows[0].id))
        XCTAssertTrue(model.applyReplaceConfirmation(
            for: rows[0].id,
            decision: context.decision(understandsReplace: true)
        ))
        model.renameIncomingFile(for: rows[1].id, to: "contract-renamed.pdf")
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let requests = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 2)
        XCTAssertEqual(requests, importConflictExpectedBatchRequests())
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
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let blockedOutcome = await model.importReadyFiles()
        XCTAssertNil(blockedOutcome)

        let context = try XCTUnwrap(model.beginReplaceConfirmation(for: duplicateURL.path))
        XCTAssertTrue(model.applyReplaceConfirmation(
            for: duplicateURL.path,
            decision: context.decision(understandsReplace: true)
        ))
        let outcome = await model.importReadyFiles()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(requests.map(\.duplicateStrategy), [.overwrite])
        XCTAssertEqual(model.rows.first?.status.tag, "IMPORTED")
    }

    @MainActor
    func verifyProgressResultAndChangeLogRoutes() async throws {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let lister = ImportConflictChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.importConflictFixture(filename: "Invoice_2026Q1.pdf")
        ])])
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let progress = importBatchProgress(
            completed: 1,
            failed: 1,
            total: 3,
            remaining: 0,
            currentPath: "docs/contract.pdf",
            skipped: 1,
            items: importConflictProgressItems()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        guard case let .importProgress(route) = model.route else {
            return XCTFail("Expected import-progress import progress route")
        }
        XCTAssertEqual(route.resultSummaryText, "Imported 1, failed 1, stopped 1, pending 0.")

        model.showImportEntryResults(progress)
        await model.loadImportResultChangeLog()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [ImportConflictChangeLogRequest(repoPath: "/tmp/repo", filter: .importResultRecent)])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 1, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed, .skipped])
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
        let blockedApplyRequests = await blockedBatcher.applyRequests()
        XCTAssertEqual(blockedApplyRequests, [])
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
        XCTAssertEqual(model.conflictBatchScopeSummary, "Will apply to 1 selected conflicts.")
        XCTAssertNil(model.conflictBatchApplyDisabledReason)
        let unconfirmedApply = await model.applyImportConflictBatch(replaceConfirmed: false)
        let unconfirmedApplyRequests = await batcher.applyRequests()
        XCTAssertNil(unconfirmedApply)
        XCTAssertEqual(unconfirmedApplyRequests, [])

        let applied = await model.applyImportConflictBatch(replaceConfirmed: true)
        await model.undoImportConflictBatchAction()
        let previewStrategies = await batcher.previewRequests().map(\.request.duplicateStrategy)
        let applyRequests = await batcher.applyRequests()
        let listRequests = await undoStore.listRequests()
        let undoRequests = await undoStore.undoRequests()

        XCTAssertEqual(applied?.report?.replacedCount, 1)
        XCTAssertEqual(model.conflictBatchUndoState, .undone(undoResult))
        XCTAssertEqual(previewStrategies, [.replace, .replace])
        let previewScopes = await batcher.previewRequests().map(\.request.applyToAllSimilarConflicts)
        XCTAssertEqual(previewScopes, [true, false])
        XCTAssertEqual(applyRequests, [
            ImportConflictApplyRequest(
                repoPath: "/tmp/repo",
                request: .testFixture(applyToAllSimilarConflicts: false),
                previewToken: "token-replace"
            )
        ])
        XCTAssertEqual(listRequests, ["/tmp/repo"])
        XCTAssertEqual(undoRequests, ["/tmp/repo|undo-import-conflict-batch"])
    }
}
