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

        XCTAssertEqual(model.conflictBatchUndoState, .ready(action))
        await undoStore.assertUndoActionListRequests(["/tmp/repo"])
        await undoStore.assertUndoActionRequests([])
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

        XCTAssertEqual(model.conflictBatchUndoState, .undone(result))
        await undoStore.assertUndoActionRequests(["/tmp/repo|undo-import-conflict-batch"])
    }

    func testImportConflictBatchUndoActionLogCoreFallbackUsesAppSemanticFailureSnapshot() {
        XCTAssertEqual(
            CoreErrorMappingSnapshot.internalFailure(rawContext: "undo_action returned no result"),
            CoreErrorMappingSnapshot.testFixture(
                kind: .internal,
                userMessage: "Internal application error",
                severity: .critical,
                suggestedAction: "Record the error information and restart the app",
                recoverability: .fatal,
                rawContext: "undo_action returned no result"
            )
        )
    }

    @MainActor
    func testImportConflictBatchBlockedApplyMapsAppConflictWithoutCallingCoreApply() async {
        var preview = ImportConflictBatchPreviewReportSnapshot.importConflictBatchDefaultUndoPreview
        preview.canApply = false
        preview.applyBlockedReason = "Select at least one conflict."
        let batcher = ImportConflictBatcher(previews: [])
        let request = ImportConflictBatchApplyRequestSnapshot.testFixture(
            importSessionID: preview.importSessionID,
            duplicateStrategy: .skip,
            sameNameStrategy: .skip,
            replaceConfirmed: false
        )

        let result = await ImportConflictBatchAction.apply(
            repoPath: "/tmp/repo",
            request: request,
            preview: preview,
            batcher: batcher,
            errorMapper: CoreBridge()
        )

        XCTAssertNil(result.report)
        XCTAssertEqual(result.failure, .conflict(rawContext: "Select at least one conflict."))
        await batcher.assertNoImportConflictApplyRequests()
    }

    @MainActor
    func testImportFolderFolderConflictPrecheckMapsDuplicateNameAndBlockedRows() async {
        let fixture = ImportFolderFolderConflictFixture.make()
        let model = makeImportFolderPreviewModel(
            predictor: fixture.predictor,
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: fixture.rootURL))

        await fixture.prechecker.assertImportFolderPrecheckDestinations([.autoClassify])
        assertImportRowStatusTags(model.rows, ["DUP", "NAME", "BLOCKED"])
        XCTAssertEqual(model.duplicateCount, 1)
        XCTAssertEqual(model.nameConflictCount, 1)
        XCTAssertEqual(model.blockedCount, 1)
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)
        assertImportRowStatusDetails(model.rows, [
            0: "Skip: docs/existing-dup.pdf",
            1: "Keep both (auto-number): docs/name.pdf"
        ])
    }

    @MainActor
    func testImportFolderFolderConflictStrategiesControlImportQueueAndSummary() async {
        let fixture = ImportFolderFolderConflictFixture.make(includeBlocked: false)
        let importer = ImportBatchRecordingBatchImporter()
        let model = makeImportFolderPreviewModel(
            predictor: fixture.predictor,
            importer: importer,
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: fixture.rootURL))
        model.renameIncomingFile(for: fixture.nameURL.path, to: "renamed-name.pdf")
        let outcome = await model.importReadyFiles()

        await importer.assertImportedBatchFiles([
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
        assertImportRowStatusTags(model.rows, ["DUP", "IMPORTED"])
    }

    @MainActor
    func testImportFolderFolderReplaceRequiresReplaceConfirmConfirmationBeforeImport() async throws {
        let duplicateURL = URL(fileURLWithPath: "/tmp/client-a/dup.pdf")
        let scanner = importFolderStaticScanner(urls: [duplicateURL])
        let prechecker = ImportFolderStaticConflictPrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf")
        ])
        let importer = ImportBatchRecordingBatchImporter()
        let model = makeImportFolderPreviewModel(
            predictor: ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction())]),
            importer: importer,
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
        assertImportBlockedByUnresolvedConflicts(model.importDisabledReason)
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

        await importer.assertImportedBatchFiles([importFolderFolderOverwriteRequest()])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        assertImportRowStatusTags(model.rows, ["IMPORTED"])
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
        .testFixture(
            previewToken: "token-default",
            replaceCount: 0,
            skipCount: 1,
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
        var item = ImportConflictBatchPreviewItemSnapshot.testFixture(
            conflictID: conflictID,
            selectedStrategy: strategy,
            status: strategy == .replace ? .needsConfirmation : .ready
        )
        item.willKeepBoth = false
        item.willAskPerItem = false
        return item
    }
}

private extension ImportConflictBatchApplyReportSnapshot {
    static func importConflictBatchUndoReport(
        for request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchApplyReportSnapshot {
        let isReplace = request.duplicateStrategy == .replace || request.sameNameStrategy == .replace
        return .testFixture(
            importSessionID: request.importSessionID,
            requestedConflictCount: Int64(request.conflictIDs.count),
            resolvedCount: Int64(request.conflictIDs.count),
            skippedCount: isReplace ? 0 : Int64(request.conflictIDs.count),
            replacedCount: isReplace ? Int64(request.conflictIDs.count) : 0,
            itemResults: [],
            undoToken: isReplace ? "undo-import-conflict-batch" : nil,
            changeLogActions: ["import_conflict_batch"]
        )
    }
}

private extension UndoActionRecordSnapshot {
    static func importConflictBatchPendingImportConflictBatch() -> UndoActionRecordSnapshot {
        importConflictBatchUndoAction()
    }
}

private extension UndoActionResultSnapshot {
    static func importConflictBatchExecutedImportConflictBatch() -> UndoActionResultSnapshot {
        importConflictBatchUndoResult()
    }
}
