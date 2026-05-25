@testable import AreaMatrix
import XCTest

final class ImportFolderConflictResolutionTests: XCTestCase {
    @MainActor
    func testS221C207LoadsUndoActionFromCoreActionLogAfterReplaceApply() async {
        let action = UndoActionRecordSnapshot.s221PendingImportConflictBatch()
        let undoStore = S221UndoStore(results: [.list(.success([action]))])
        let model = s221UndoModel(
            conflictBatcher: S221UndoConflictBatcher(preview: .s221UndoReplacePreview),
            undoStore: undoStore
        )
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221UndoRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
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
    func testS221C207ReportsUnavailableWhenUndoTokenIsMissing() async {
        let model = s221UndoModel(
            conflictBatcher: S221UndoConflictBatcher(),
            undoStore: S221UndoStore(results: [])
        )
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221UndoRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
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
    func testS221C207UndoButtonExecutesCoreUndoAction() async {
        let action = UndoActionRecordSnapshot.s221PendingImportConflictBatch()
        let result = UndoActionResultSnapshot.s221ExecutedImportConflictBatch()
        let undoStore = S221UndoStore(results: [
            .list(.success([action])),
            .undo(.success(result))
        ])
        let model = s221UndoModel(
            conflictBatcher: S221UndoConflictBatcher(preview: .s221UndoReplacePreview),
            undoStore: undoStore
        )
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")

        model.applyPreviewRows(
            [s118ReadyBatchRow(url: invoiceURL)],
            request: s221UndoRequest(urls: [invoiceURL], conflictIDs: ["dup-1"]),
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
    func testS119FolderConflictPrecheckMapsDuplicateNameAndBlockedRows() async {
        let fixture = S119FolderConflictFixture.make()
        let model = ImportFolderPreviewModel(
            predictor: fixture.predictor,
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: s119FolderRequest(rootURL: fixture.rootURL))
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
    func testS119FolderConflictStrategiesControlImportQueueAndSummary() async {
        let fixture = S119FolderConflictFixture.make(includeBlocked: false)
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: fixture.predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: s119FolderRequest(rootURL: fixture.rootURL))
        model.renameIncomingFile(for: fixture.nameURL.path, to: "renamed-name.pdf")
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
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
    func testS119FolderReplaceRequiresS124ConfirmationBeforeImport() async throws {
        let duplicateURL = URL(fileURLWithPath: "/tmp/client-a/dup.pdf")
        let scanner = s119StaticScanner(urls: [duplicateURL])
        let prechecker = S119StaticConflictPrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf")
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction())]),
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: prechecker,
            scanner: scanner
        )
        let request = s119FolderRequest(
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

        XCTAssertEqual(recordedRequests, [s119FolderOverwriteRequest()])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "IMPORTED")
    }
}

private func s119FolderOverwriteRequest() -> S118BatchImportRequest {
    S118BatchImportRequest(
        destination: .autoClassify,
        suggestedCategory: "docs",
        overrideFilename: "ready.pdf",
        duplicateStrategy: .overwrite
    )
}

private struct S119FolderConflictFixture {
    var rootURL: URL
    var nameURL: URL
    var scanner: S119StaticFolderScanner
    var predictor: S119MappedPredictor
    var prechecker: S119StaticConflictPrechecker

    static func make(includeBlocked: Bool = true) -> S119FolderConflictFixture {
        let rootURL = URL(fileURLWithPath: "/tmp/client-a")
        let duplicateURL = rootURL.appendingPathComponent("dup.pdf")
        let nameURL = rootURL.appendingPathComponent("name.pdf")
        let blockedURL = rootURL.appendingPathComponent("blocked.pdf")
        var rows = [
            ImportFolderPreviewRow.loading(fileURL: duplicateURL, rootURL: rootURL),
            ImportFolderPreviewRow.loading(fileURL: nameURL, rootURL: rootURL)
        ]
        var predictions: [String: Result<ClassifyResultSnapshot, Error>] = [
            "dup.pdf": .success(.s119Prediction(category: "docs", suggestedName: "dup.pdf")),
            "name.pdf": .success(.s119Prediction(category: "docs", suggestedName: "name.pdf"))
        ]
        var results: [String: ImportFolderConflictPrecheckResult] = [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf"),
            nameURL.path: .nameConflict(existingPath: "docs/name.pdf")
        ]

        if includeBlocked {
            rows.append(ImportFolderPreviewRow.loading(fileURL: blockedURL, rootURL: rootURL))
            predictions["blocked.pdf"] = .success(.s119Prediction(category: "docs", suggestedName: "blocked.pdf"))
            results[blockedURL.path] = .blocked("Conflict precheck failed: permission denied")
        }

        return S119FolderConflictFixture(
            rootURL: rootURL,
            nameURL: nameURL,
            scanner: S119StaticFolderScanner(result: ImportFolderScanResult(
                rows: rows,
                folderCount: 0,
                skippedRules: [],
                errors: []
            )),
            predictor: S119MappedPredictor(resultsByFilename: predictions),
            prechecker: S119StaticConflictPrechecker(results: results)
        )
    }
}

@MainActor
private func s221UndoModel(
    conflictBatcher: any CoreImportConflictBatching,
    undoStore: any CoreUndoActionLogging
) -> ImportBatchCopyImportModel {
    ImportBatchCopyImportModel(
        importer: S118RecordingBatchImporter(),
        errorMapper: S117RecordingErrorMapper(),
        conflictBatcher: conflictBatcher,
        undoActionStore: undoStore
    )
}

private func s221UndoRequest(urls: [URL], conflictIDs: [String]) -> ImportEntryRequest {
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

private actor S221UndoConflictBatcher: CoreImportConflictBatching {
    private let preview: ImportConflictBatchPreviewReportSnapshot

    init(preview: ImportConflictBatchPreviewReportSnapshot = .s221DefaultUndoPreview) {
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
        .s221UndoReport(for: request)
    }
}

private actor S221UndoStore: CoreUndoActionLogging {
    enum Result {
        case list(Swift.Result<[UndoActionRecordSnapshot], Error>)
        case undo(Swift.Result<UndoActionResultSnapshot, Error>)
    }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard case let .list(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
        }
        return try result.get()
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard case let .undo(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected undo_action result")
        }
        return try result.get()
    }

    func listRequests() -> [String] { recordedListRequests }

    func undoRequests() -> [String] { recordedUndoRequests }

    private func consumeResult() throws -> Result {
        guard !results.isEmpty else { throw CoreError.Db(message: "missing undo action result") }
        return results.removeFirst()
    }
}

private extension ImportConflictBatchPreviewReportSnapshot {
    static var s221DefaultUndoPreview: ImportConflictBatchPreviewReportSnapshot {
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
            items: [.s221UndoDuplicate(strategy: .skip)]
        )
    }

    static var s221UndoReplacePreview: ImportConflictBatchPreviewReportSnapshot {
        var preview = s221DefaultUndoPreview
        preview.previewToken = "token-replace"
        preview.replaceCount = 1
        preview.skipCount = 0
        preview.replaceConfirmationRequired = true
        preview.replaceConfirmationSummary = "1 duplicate conflict"
        preview.items = [.s221UndoDuplicate(strategy: .replace)]
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
            .s221UndoDuplicate(conflictID: conflictID, strategy: request.duplicateStrategy)
        }
        return copy
    }
}

private extension ImportConflictBatchPreviewItemSnapshot {
    static func s221UndoDuplicate(
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
    static func s221UndoReport(
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
    static func s221PendingImportConflictBatch() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-import-conflict-batch",
            kind: "import_conflict_batch",
            summary: "Replaced 1 import conflict.",
            affectedCount: 1,
            affectedFileNames: ["Invoice_2026Q1.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_400,
            updatedAt: 1_700_000_400
        )
    }
}

private extension UndoActionResultSnapshot {
    static func s221ExecutedImportConflictBatch() -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: "undo-import-conflict-batch",
            status: .executed,
            summary: "Undone: replaced 1 import conflict.",
            affectedCount: 1,
            refreshTargets: ["files", "change_log", "undo_actions"],
            completedAt: 1_700_000_420
        )
    }
}
