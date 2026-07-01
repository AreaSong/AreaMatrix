@testable import AreaMatrix
import XCTest

final class ImportFolderConflictResolutionTests: XCTestCase {
    @MainActor
    func testImportConflictBatchUndoActionLogCoreLoadsUndoActionFromCoreActionLogAfterReplaceApply() async {
        let action = UndoActionRecordSnapshot.importConflictBatchPendingImportConflictBatch()
        let undoStore = ImportConflictBatchUndoStore(results: [.list(.success([action]))])
        let model = importConflictBatchUndoModel(
            conflictBatcher: ImportConflictBatchUndoConflictBatcher(preview: .importConflictBatchUndoReplacePreview),
            undoStore: undoStore
        )
        let invoiceURL = importBatchInvoiceURL()

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchUndoRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
            selectedDestination: .autoClassify
        )
        model.updateConflictBatchDuplicateStrategy(.replace)
        await model.loadImportConflictBatchPreview()
        _ = await model.applyImportConflictBatch(replaceConfirmed: true)
        let listRequests = await undoStore.listRequests()
        let undoRequests = await undoStore.undoRequests()

        XCTAssertEqual(model.conflictBatchUndoState, .ready(action))
        XCTAssertEqual(listRequests, ["/tmp/repo"])
        XCTAssertEqual(undoRequests, [])
    }

    @MainActor
    func testImportConflictBatchUndoActionLogCoreReportsUnavailableWhenUndoTokenIsMissing() async {
        let model = importConflictBatchUndoModel(
            conflictBatcher: ImportConflictBatchUndoConflictBatcher(),
            undoStore: ImportConflictBatchUndoStore(results: [])
        )
        let invoiceURL = importBatchInvoiceURL()

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchUndoRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
            selectedDestination: .autoClassify
        )
        await model.loadImportConflictBatchPreview()
        _ = await model.applyImportConflictBatch()

        XCTAssertEqual(
            model.conflictBatchUndoState,
            .unavailable(reason: "Undo is unavailable for this import conflict result.")
        )
    }

    @MainActor
    func testImportConflictBatchUndoActionLogCoreUndoButtonExecutesCoreUndoAction() async {
        let action = UndoActionRecordSnapshot.importConflictBatchPendingImportConflictBatch()
        let result = UndoActionResultSnapshot.importConflictBatchExecutedImportConflictBatch()
        let undoStore = ImportConflictBatchUndoStore(results: [
            .list(.success([action])),
            .undo(.success(result))
        ])
        let model = importConflictBatchUndoModel(
            conflictBatcher: ImportConflictBatchUndoConflictBatcher(preview: .importConflictBatchUndoReplacePreview),
            undoStore: undoStore
        )
        let invoiceURL = importBatchInvoiceURL()

        model.applyPreviewRows(
            [importBatchReadyBatchRow(url: invoiceURL)],
            request: importConflictBatchUndoRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
            selectedDestination: .autoClassify
        )
        model.updateConflictBatchDuplicateStrategy(.replace)
        await model.loadImportConflictBatchPreview()
        _ = await model.applyImportConflictBatch(replaceConfirmed: true)
        await model.undoImportConflictBatchAction()
        let undoRequests = await undoStore.undoRequests()

        XCTAssertEqual(model.conflictBatchUndoState, .undone(result))
        XCTAssertEqual(undoRequests, ["/tmp/repo|undo-import-conflict-batch"])
    }

    @MainActor
    func testImportFolderFolderConflictPrecheckMapsDuplicateNameAndBlockedRows() async {
        let fixture = ImportFolderFolderConflictFixture.make()
        let model = ImportFolderPreviewModel(
            predictor: fixture.predictor,
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: fixture.rootURL))
        let requests = await fixture.prechecker.recordedRequests()

        XCTAssertEqual(requests.map(\.destination), [.autoClassify])
        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "NAME", "BLOCKED"])
        XCTAssertEqual(model.duplicateCount, 1)
        XCTAssertEqual(model.nameConflictCount, 1)
        XCTAssertEqual(model.blockedCount, 1)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        XCTAssertEqual(model.rows[0].status.detail, "Skip: docs/existing-dup.pdf")
        XCTAssertEqual(model.rows[1].status.detail, "Keep both (auto-number): docs/name.pdf")
    }

    @MainActor
    func testImportFolderFolderConflictStrategiesControlImportQueueAndSummary() async {
        let fixture = ImportFolderFolderConflictFixture.make(includeBlocked: false)
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: fixture.predictor,
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: fixture.rootURL))
        model.renameIncomingFile(for: fixture.nameURL.path, to: "renamed-name.pdf")
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "renamed-name.pdf",
                duplicateStrategy: .keepBoth
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.skippedDuplicateCount, 1)
        XCTAssertEqual(outcome?.total, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "IMPORTED"])
    }

    @MainActor
    func testImportFolderFolderReplaceRequiresReplaceConfirmConfirmationBeforeImport() async throws {
        let duplicateURL = URL(fileURLWithPath: "/tmp/client-a/dup.pdf")
        let scanner = importFolderStaticScanner(urls: [duplicateURL])
        let prechecker = ImportFolderStaticConflictPrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf")
        ])
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction())]),
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: prechecker,
            scanner: scanner
        )
        let request = importFolderFolderRequest(
            rootURL: URL(fileURLWithPath: "/tmp/client-a"),
            allowReplaceDuringImport: true
        )

        await model.load(request: request)
        model.updateDuplicateStrategy(
            for: duplicateURL.path,
            strategy: ImportBatchDuplicateResolutionStrategy.replace
        )
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let blockedOutcome = await model.importReadyFiles()
        XCTAssertNil(blockedOutcome)

        let context: SingleFileReplaceConfirmationContext = try XCTUnwrap(
            model.beginReplaceConfirmation(for: duplicateURL.path)
        )
        model.applyReplaceConfirmation(
            for: duplicateURL.path,
            decision: context.decision(understandsReplace: true)
        )
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [importFolderFolderOverwriteRequest()])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "IMPORTED")
    }
}

private func importFolderFolderOverwriteRequest() -> ImportBatchBatchImportRequest {
    ImportBatchBatchImportRequest(
        destination: .autoClassify,
        suggestedCategory: "docs",
        overrideFilename: "ready.pdf",
        duplicateStrategy: .overwrite
    )
}

private struct ImportFolderFolderConflictFixture {
    var rootURL: URL
    var nameURL: URL
    var scanner: ImportFolderStaticFolderScanner
    var predictor: ImportFolderMappedPredictor
    var prechecker: ImportFolderStaticConflictPrechecker

    static func make(includeBlocked: Bool = true) -> ImportFolderFolderConflictFixture {
        let rootURL = URL(fileURLWithPath: "/tmp/client-a")
        let duplicateURL = rootURL.appendingPathComponent("dup.pdf")
        let nameURL = rootURL.appendingPathComponent("name.pdf")
        let blockedURL = rootURL.appendingPathComponent("blocked.pdf")
        var rows = [
            ImportFolderPreviewRow.loading(fileURL: duplicateURL, rootURL: rootURL),
            ImportFolderPreviewRow.loading(fileURL: nameURL, rootURL: rootURL)
        ]
        var predictions: [String: Result<ClassifyResultSnapshot, Error>] = [
            "dup.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "dup.pdf")),
            "name.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "name.pdf"))
        ]
        var results: [String: ImportFolderConflictPrecheckResult] = [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf"),
            nameURL.path: .nameConflict(existingPath: "docs/name.pdf")
        ]

        if includeBlocked {
            rows.append(ImportFolderPreviewRow.loading(fileURL: blockedURL, rootURL: rootURL))
            predictions["blocked.pdf"] = .success(.importFolderPrediction(
                category: "docs",
                suggestedName: "blocked.pdf"
            ))
            results[blockedURL.path] = .blocked("Conflict precheck failed: permission denied")
        }

        return ImportFolderFolderConflictFixture(
            rootURL: rootURL,
            nameURL: nameURL,
            scanner: ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
                rows: rows,
                folderCount: 0,
                skippedRules: [],
                errors: []
            )),
            predictor: ImportFolderMappedPredictor(resultsByFilename: predictions),
            prechecker: ImportFolderStaticConflictPrechecker(results: results)
        )
    }
}

@MainActor
private func importConflictBatchUndoModel(
    conflictBatcher: any CoreImportConflictBatching,
    undoStore: any CoreUndoActionLogging
) -> ImportBatchCopyImportModel {
    ImportBatchCopyImportModel(
        importer: ImportBatchRecordingBatchImporter(),
        errorMapper: RecordingCoreErrorMapper.importSingleFile(),
        conflictBatcher: conflictBatcher,
        undoActionStore: undoStore
    )
}

private func importConflictBatchUndoRequest(urls: [URL], conflictIDs: [String]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: true,
        isTrashAvailable: true,
        importSessionID: "session-221",
        importConflictIDs: conflictIDs
    )
}

private actor ImportConflictBatchUndoConflictBatcher: CoreImportConflictBatching {
    private let preview: ImportConflictBatchPreviewReportSnapshot

    init(preview: ImportConflictBatchPreviewReportSnapshot = .importConflictBatchDefaultUndoPreview) {
        self.preview = preview
    }

    func previewImportConflictBatch(
        repoPath _: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        preview.withUndoRequest(request)
    }

    func applyImportConflictBatch(
        repoPath _: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken _: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        .importConflictBatchUndoReport(for: request)
    }
}

private typealias ImportConflictBatchUndoStore = UndoActionRecordingTestStore

private extension ImportConflictBatchPreviewReportSnapshot {
    static var importConflictBatchDefaultUndoPreview: ImportConflictBatchPreviewReportSnapshot {
        ImportConflictBatchPreviewReportSnapshot(
            importSessionID: "session-221",
            previewToken: "token-default",
            applyToAllSimilarConflicts: true,
            requestedConflictCount: 1,
            duplicateConflictCount: 1,
            sameNameConflictCount: 0,
            includedCount: 1,
            pendingCount: 0,
            blockedCount: 0,
            replaceCount: 0,
            skipCount: 1,
            keepBothCount: 0,
            askPerItemCount: 0,
            trashAvailable: true,
            undoAvailable: true,
            canApply: true,
            applyBlockedReason: nil,
            replaceConfirmationRequired: false,
            replaceConfirmationSummary: nil,
            items: [.importConflictBatchUndoDuplicate(strategy: .skip)]
        )
    }

    static var importConflictBatchUndoReplacePreview: ImportConflictBatchPreviewReportSnapshot {
        var preview = importConflictBatchDefaultUndoPreview
        preview.previewToken = "token-replace"
        preview.replaceCount = 1
        preview.skipCount = 0
        preview.replaceConfirmationRequired = true
        preview.replaceConfirmationSummary = "1 duplicate conflict"
        preview.items = [.importConflictBatchUndoDuplicate(strategy: .replace)]
        return preview
    }

    func withUndoRequest(
        _ request: ImportConflictBatchPreviewRequestSnapshot
    ) -> ImportConflictBatchPreviewReportSnapshot {
        var copy = self
        copy.importSessionID = request.importSessionID
        copy.requestedConflictCount = Int64(request.conflictIDs.count)
        copy.includedCount = Int64(request.conflictIDs.count)
        copy.items = request.conflictIDs.map { conflictID in
            .importConflictBatchUndoDuplicate(conflictID: conflictID, strategy: request.duplicateStrategy)
        }
        return copy
    }
}

private extension ImportConflictBatchPreviewItemSnapshot {
    static func importConflictBatchUndoDuplicate(
        conflictID: String = "dup-1",
        strategy: ImportConflictBatchStrategySnapshot
    ) -> ImportConflictBatchPreviewItemSnapshot {
        ImportConflictBatchPreviewItemSnapshot(
            conflictID: conflictID,
            conflictType: .duplicateHash,
            existingFileID: 42,
            existingPath: "finance/existing-invoice.pdf",
            incomingPath: "/tmp/Invoice_2026Q1.pdf",
            targetPath: "finance/Invoice_2026Q1.pdf",
            selectedStrategy: strategy,
            status: strategy == .replace ? .needsConfirmation : .ready,
            willReplace: strategy == .replace,
            willKeepBoth: false,
            willSkip: strategy == .skip,
            willAskPerItem: false,
            indexOnly: false,
            riskSummary: "Existing file remains unless Replace is confirmed.",
            reason: nil
        )
    }
}

private extension ImportConflictBatchApplyReportSnapshot {
    static func importConflictBatchUndoReport(
        for request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchApplyReportSnapshot {
        let isReplace = request.duplicateStrategy == .replace || request.sameNameStrategy == .replace
        return ImportConflictBatchApplyReportSnapshot(
            importSessionID: request.importSessionID,
            requestedConflictCount: Int64(request.conflictIDs.count),
            resolvedCount: Int64(request.conflictIDs.count),
            skippedCount: isReplace ? 0 : Int64(request.conflictIDs.count),
            keptBothCount: 0,
            replacedCount: isReplace ? Int64(request.conflictIDs.count) : 0,
            queuedForPerItemCount: 0,
            pendingCount: 0,
            failedCount: 0,
            itemResults: [],
            affectedFileIDs: [42],
            undoToken: isReplace ? "undo-import-conflict-batch" : nil,
            changeLogActions: ["import_conflict_batch"],
            failureSummary: nil
        )
    }
}

private extension UndoActionRecordSnapshot {
    static func importConflictBatchPendingImportConflictBatch() -> UndoActionRecordSnapshot {
        testImportConflictBatchUndoAction()
    }
}

private extension UndoActionResultSnapshot {
    static func importConflictBatchExecutedImportConflictBatch() -> UndoActionResultSnapshot {
        testExecutedImportConflictBatchUndoResult()
    }
}
