@testable import AreaMatrix
import XCTest

final class ImportConflictIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testImportConflictLoopsUseRealWiring() async throws {
        XCTAssertEqual(Self.coveredCoreCapabilities, [
            "C1-05", "C1-06", "C1-07", "C1-08", "C1-09", "C1-10", "C1-13", "C2-07", "C2-17"
        ])

        try await verifyHoverAndEntryRouting()
        try await verifySingleFileProgressStartsBeforeCoreImportCompletes()
        try await verifySingleFileConflictPagesBlockReplaceUntilConfirmation()
        try await verifyBatchAndFolderConflictImports()
        try await verifyProgressResultAndChangeLogRoutes()
        try await verifyS221ImportConflictBatchPageIntegration()
    }
}

private extension ImportConflictIntegrationVerifyTests {
    static let coveredCoreCapabilities: Set<String> = [
        "C1-05", "C1-06", "C1-07", "C1-08", "C1-09", "C1-10", "C1-13", "C2-07", "C2-17"
    ]

    @MainActor
    func verifyHoverAndEntryRouting() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let predictor = S117RecordingPredictor(result: ClassifyResultSnapshot(
            category: "finance",
            suggestedName: "Invoice_2026Q1.pdf",
            reason: .keyword,
            confidence: 0.9
        ))
        let dropModel = ImportDropPreviewModel(repoPath: "/tmp/repo", predictor: predictor)

        await dropModel.preview(target: .autoClassify, urls: [sourceURL])
        let requests = await predictor.recordedRequests()

        XCTAssertEqual(requests, [S117PredictRequest(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf")])
        XCTAssertEqual(dropModel.presentation?.destinationLabel, "finance")
        XCTAssertEqual(dropModel.presentation?.headline, "Drop files to import")

        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        model.route = .mainList(opening)
        model.startImportEntry(opening: opening, source: .dropZone, urls: [sourceURL])

        XCTAssertEqual(model.pendingImportEntry?.kind, .singleFile)
        XCTAssertEqual(model.pendingImportEntry?.destination, .autoClassify)
    }

    @MainActor
    func verifySingleFileProgressStartsBeforeCoreImportCompletes() async throws {
        let gate = S117ImportGate()
        let importer = S117SuspendingImporter(gate: gate)
        var events: [String] = []
        let previewModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight.ready(),
            errorMapper: S117RecordingErrorMapper()
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
        let importer = S117RecordingImporter()
        let duplicateModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: importer,
            preflight: ImportSingleFileStaticPreflight(result: duplicatePreflight()),
            errorMapper: S117RecordingErrorMapper()
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
            S117ImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "source.pdf",
                duplicateStrategy: .overwrite
            )
        ])

        let nameModel = ImportSingleFilePreviewModel(
            predictor: S117RecordingPredictor(result: .s117Fixture()),
            importer: S117RecordingImporter(),
            preflight: ImportSingleFileStaticPreflight(result: namePreflight()),
            errorMapper: S117RecordingErrorMapper()
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
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/contract.pdf")
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )
        let rows = [
            ImportBatchPreviewRow.duplicate(
                url: invoiceURL,
                prediction: .s119Prediction(category: "finance", suggestedName: "Invoice_2026Q1.pdf"),
                existingPath: "finance/Invoice_2026Q1.pdf"
            ),
            ImportBatchPreviewRow.nameConflict(
                url: contractURL,
                prediction: .s119Prediction(category: "docs", suggestedName: "contract.pdf"),
                existingPath: "docs/contract.pdf"
            )
        ]

        model.applyPreviewRows(
            rows,
            request: batchRequest(urls: [invoiceURL, contractURL]),
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
        XCTAssertEqual(requests, expectedConflictBatchRequests())
    }

    @MainActor
    func verifyFolderConflictImport() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/client-a")
        let duplicateURL = rootURL.appendingPathComponent("dup.pdf")
        let importer = S118RecordingBatchImporter()
        let scanner = S119StaticFolderScanner(result: s119FolderScanResult(rows: [
            ImportFolderPreviewRow.loading(fileURL: duplicateURL, rootURL: rootURL)
        ]))
        let prechecker = S119StaticConflictPrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf")
        ])
        let model = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction(suggestedName: "dup.pdf"))]),
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: prechecker,
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(rootURL: rootURL, allowReplaceDuringImport: true))
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
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let lister = Task27ChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.task27Fixture(filename: "Invoice_2026Q1.pdf")
        ])])
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let progress = ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 3,
            remaining: 0,
            currentPath: "docs/contract.pdf",
            skipped: 1,
            items: progressItems()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        guard case let .importProgress(route) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }
        XCTAssertEqual(route.resultSummaryText, "Imported 1, failed 1, stopped 1, pending 0.")

        model.showImportEntryResults(progress)
        await model.loadImportResultChangeLog()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [Task27ChangeLogRequest(repoPath: "/tmp/repo", filter: .importResultRecent)])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 1, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed, .skipped])
        XCTAssertEqual(result.items[2].existingRelativePath, "finance/Invoice_2026Q1.pdf")
        XCTAssertEqual(result.changeLog, .loaded([
            ChangeLogEntrySnapshot.task27Fixture(filename: "Invoice_2026Q1.pdf")
        ]))
    }

    @MainActor
    func verifyS221ImportConflictBatchPageIntegration() async throws {
        try await verifyS221BlockedPreviewDoesNotApply()
        try await verifyS221SelectedScopeRefreshesBeforeApplyAndUndo()
    }

    @MainActor
    func verifyS221BlockedPreviewDoesNotApply() async throws {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let blockedBatcher = S221IntegrationConflictBatcher(previews: [.s221Preview(canApply: false)])
        let blockedModel = s221IntegrationModel(conflictBatcher: blockedBatcher, undoStore: S221IntegrationUndoStore())

        blockedModel.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221IntegrationRequest(urls: [invoiceURL], conflictIDs: ["dup-blocked"]),
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
    // swiftlint:disable:next function_body_length
    func verifyS221SelectedScopeRefreshesBeforeApplyAndUndo() async throws {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let action = UndoActionRecordSnapshot.s221IntegrationAction()
        let undoResult = UndoActionResultSnapshot.s221IntegrationResult()
        let undoStore = S221IntegrationUndoStore(actions: .success([action]), undoResult: .success(undoResult))
        let batcher = S221IntegrationConflictBatcher(previews: [
            .s221Preview(canApply: true),
            .s221Preview(canApply: true)
        ])
        let model = s221IntegrationModel(conflictBatcher: batcher, undoStore: undoStore)

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221IntegrationRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
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
            S221IntegrationApplyRequest(
                repoPath: "/tmp/repo",
                request: ImportConflictBatchApplyRequestSnapshot(
                    importSessionID: "session-221",
                    conflictIDs: ["dup-1"],
                    duplicateStrategy: .replace,
                    sameNameStrategy: .keepBoth,
                    applyToAllSimilarConflicts: false,
                    replaceConfirmed: true
                ),
                previewToken: "token-replace"
            )
        ])
        XCTAssertEqual(listRequests, ["/tmp/repo"])
        XCTAssertEqual(undoRequests, ["/tmp/repo|undo-import-conflict-batch"])
    }
}

private func duplicatePreflight() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 12,
        hashSha256: "same-hash",
        targetRelativePath: "docs/source.pdf",
        conflict: .duplicate(existingPath: "docs/existing-source.pdf"),
        keepBothTargetRelativePath: "docs/source_1.pdf"
    )
}

private func namePreflight() -> ImportSingleFilePreflightResult {
    ImportSingleFilePreflightResult(
        sourceSizeBytes: 12,
        hashSha256: "different-hash",
        targetRelativePath: "docs/source.pdf",
        conflict: .name(path: "docs/source.pdf"),
        keepBothTargetRelativePath: "docs/source_1.pdf",
        existingPaths: ["docs/source.pdf"]
    )
}

private func batchRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: true,
        isTrashAvailable: true
    )
}

private func expectedConflictBatchRequests() -> [S118BatchImportRequest] {
    [
        S118BatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "finance",
            overrideFilename: "Invoice_2026Q1.pdf",
            duplicateStrategy: .overwrite
        ),
        S118BatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "contract-renamed.pdf",
            duplicateStrategy: .keepBoth
        )
    ]
}

private func progressItems() -> [ImportBatchProgressSnapshot.Item] {
    [
        ImportBatchProgressSnapshot.Item(
            sourcePath: "/tmp/imported.pdf",
            targetPath: "docs/imported.pdf",
            phase: .done,
            errorMessage: nil
        ),
        ImportBatchProgressSnapshot.Item(
            sourcePath: "/tmp/failed.pdf",
            targetPath: "docs/failed.pdf",
            phase: .failed,
            errorMessage: "Storage write failed"
        ),
        ImportBatchProgressSnapshot.Item(
            sourcePath: "/tmp/duplicate.pdf",
            targetPath: "finance/Invoice_2026Q1.pdf",
            phase: .pending,
            errorMessage: nil,
            existingRelativePath: "finance/Invoice_2026Q1.pdf"
        )
    ]
}

private struct Task27ChangeLogRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

private actor Task27ChangeLogLister: CoreChangeLogListing {
    enum Result {
        case success([ChangeLogEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [Task27ChangeLogRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requests.append(Task27ChangeLogRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }
        switch results.removeFirst() {
        case let .success(entries):
            return entries
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [Task27ChangeLogRequest] {
        requests
    }
}

private extension ChangeLogEntrySnapshot {
    static func task27Fixture(filename: String) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: 27,
            fileID: 117,
            filename: filename,
            category: "finance",
            action: "imported",
            detailJSON: #"{"source":"/tmp/\#(filename)","mode":"copy","category":"finance"}"#,
            occurredAt: 1_700_000_000
        )
    }
}
