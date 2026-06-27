@testable import AreaMatrix
import Foundation

actor ImportBatchStaticBatchFileLoader: ImportBatchCoreFileLoading {
    private let pagesByCategory: [String: [[FileEntrySnapshot]]]
    private var requests: [FileFilterSnapshot] = []

    init(pagesByCategory: [String: [[FileEntrySnapshot]]]) {
        self.pagesByCategory = pagesByCategory
    }

    func loadImportPreviewFiles(repoPath: String, categories: Set<String?>) async throws -> [FileEntrySnapshot] {
        try await ImportBatchCoreFileLoader.load(repoPath: repoPath, categories: categories) { _, filter in
            requests.append(filter)
            let categoryKey = filter.category ?? "__all__"
            let pages = pagesByCategory[categoryKey] ?? []
            let pageIndex = Int(filter.offset / max(filter.limit, 1))
            guard pageIndex < pages.count else { return [] }
            return pages[pageIndex]
        }
    }

    func recordedRequests() -> [FileFilterSnapshot] {
        requests
    }
}

func importBatchBatchRequest(
    repoPath: String = "/tmp/repo",
    destination: ImportEntryDestination = .autoClassify,
    urls: [URL],
    allowReplaceDuringImport: Bool = false,
    isTrashAvailable: Bool = true
) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: repoPath,
        source: .dropZone,
        destination: destination,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"],
        allowReplaceDuringImport: allowReplaceDuringImport,
        isTrashAvailable: isTrashAvailable
    )
}

func importBatchReadyBatchRows(
    invoiceURL: URL,
    contractURL: URL
) -> [ImportBatchPreviewRow] {
    [
        importBatchReadyBatchRow(url: invoiceURL),
        ImportBatchPreviewRow.ready(
            url: contractURL,
            prediction: .importBatchPrediction(category: "docs", suggestedName: "2026Q1_合同.pdf", confidence: 0.82)
        )
    ]
}

func importBatchReadyBatchRow(
    url: URL,
    suggestedName: String = "Invoice_2026Q1.pdf"
) -> ImportBatchPreviewRow {
    ImportBatchPreviewRow.ready(
        url: url,
        prediction: .importBatchPrediction(category: "finance", suggestedName: suggestedName)
    )
}

func importBatchExpectedAutoClassifyRequests(
    duplicateStrategy: DuplicateStrategy = .ask
) -> [ImportBatchBatchImportRequest] {
    [
        ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "finance",
            overrideFilename: "Invoice_2026Q1.pdf",
            duplicateStrategy: duplicateStrategy
        ),
        ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "2026Q1_合同.pdf",
            duplicateStrategy: duplicateStrategy
        )
    ]
}

func importBatchExpectedCategoryRequests() -> [ImportBatchBatchImportRequest] {
    [
        ImportBatchBatchImportRequest(
            destination: .category("finance"),
            suggestedCategory: "finance",
            overrideFilename: "Invoice_2026Q1.pdf",
            duplicateStrategy: .ask
        ),
        ImportBatchBatchImportRequest(
            destination: .category("finance"),
            suggestedCategory: "docs",
            overrideFilename: "2026Q1_合同.pdf",
            duplicateStrategy: .ask
        )
    ]
}

extension ClassifyResultSnapshot {
    static func importBatchPrediction(
        category: String,
        suggestedName: String,
        confidence: Float = 0.9
    ) -> ClassifyResultSnapshot {
        ClassifyResultSnapshot(
            category: category,
            suggestedName: suggestedName,
            reason: .keyword,
            confidence: confidence
        )
    }
}

struct ImportConflictPreviewRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchPreviewRequestSnapshot
}

struct ImportConflictApplyRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchApplyRequestSnapshot
    var previewToken: String
}

actor ImportConflictBatcher: CoreImportConflictBatching {
    private var previews: [ImportConflictBatchPreviewReportSnapshot]
    private var recordedPreviewRequests: [ImportConflictPreviewRequest] = []
    private var recordedApplyRequests: [ImportConflictApplyRequest] = []

    init(previews: [ImportConflictBatchPreviewReportSnapshot]) {
        self.previews = previews
    }

    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        recordedPreviewRequests.append(ImportConflictPreviewRequest(
            repoPath: repoPath,
            request: request
        ))
        guard !previews.isEmpty else { throw CoreError.Conflict(path: "missing import-conflict-batch preview") }
        return previews.removeFirst().withImportConflictBatchRequest(request)
    }

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        recordedApplyRequests.append(ImportConflictApplyRequest(
            repoPath: repoPath,
            request: request,
            previewToken: previewToken
        ))
        return .importConflictBatchIntegrationReport(for: request)
    }

    func previewRequests() -> [ImportConflictPreviewRequest] {
        recordedPreviewRequests
    }

    func applyRequests() -> [ImportConflictApplyRequest] {
        recordedApplyRequests
    }
}

actor ImportConflictBatchIntegrationUndoStore: CoreUndoActionLogging {
    private let actions: Swift.Result<[UndoActionRecordSnapshot], Error>
    private let undoResult: Swift.Result<UndoActionResultSnapshot, Error>
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(
        actions: Swift.Result<[UndoActionRecordSnapshot], Error> = .success([]),
        undoResult: Swift.Result<UndoActionResultSnapshot, Error> = .success(.importConflictBatchIntegrationResult())
    ) {
        self.actions = actions
        self.undoResult = undoResult
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        return try actions.get()
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        return try undoResult.get()
    }

    func listRequests() -> [String] {
        recordedListRequests
    }

    func undoRequests() -> [String] {
        recordedUndoRequests
    }
}

extension ImportConflictBatchPreviewReportSnapshot {
    static func importConflictBatchPreview(canApply: Bool) -> ImportConflictBatchPreviewReportSnapshot {
        let status: ImportConflictBatchPreviewStatusSnapshot = canApply ? .needsConfirmation : .blocked
        return ImportConflictBatchPreviewReportSnapshot(
            importSessionID: "session-221",
            previewToken: canApply ? "token-replace" : "token-blocked",
            applyToAllSimilarConflicts: true,
            requestedConflictCount: 1,
            duplicateConflictCount: 1,
            sameNameConflictCount: 0,
            includedCount: 1,
            pendingCount: 0,
            blockedCount: canApply ? 0 : 1,
            replaceCount: 1,
            skipCount: 0,
            keepBothCount: 0,
            askPerItemCount: 0,
            trashAvailable: canApply,
            undoAvailable: canApply,
            canApply: canApply,
            applyBlockedReason: canApply ? nil : "Blocked: Trash unavailable",
            replaceConfirmationRequired: true,
            replaceConfirmationSummary: "Replace 1 existing file?",
            items: [.importConflictBatchItem(
                conflictID: canApply ? "dup-1" : "dup-blocked",
                strategy: .replace,
                status: status
            )]
        )
    }

    func withImportConflictBatchRequest(_ request: ImportConflictBatchPreviewRequestSnapshot)
        -> ImportConflictBatchPreviewReportSnapshot {
        var copy = self
        copy.importSessionID = request.importSessionID
        copy.applyToAllSimilarConflicts = request.applyToAllSimilarConflicts
        copy.requestedConflictCount = Int64(request.conflictIDs.count)
        copy.includedCount = Int64(request.conflictIDs.count)
        copy.items = request.conflictIDs.map { conflictID in
            let source = items.first { $0.conflictID == conflictID }
            let type = source?.conflictType ?? .duplicateHash
            let strategy = type == .duplicateHash ? request.duplicateStrategy : request.sameNameStrategy
            let status = copy.previewStatusForImportConflictBatchRequest(strategy: strategy)
            return .importConflictBatchItem(conflictID: conflictID, strategy: strategy, status: status)
                .withConflictType(type)
        }
        return copy
    }

    private func previewStatusForImportConflictBatchRequest(
        strategy: ImportConflictBatchStrategySnapshot
    ) -> ImportConflictBatchPreviewStatusSnapshot {
        guard canApply else { return .blocked }
        return strategy == .replace ? .needsConfirmation : .ready
    }
}

extension ImportConflictBatchPreviewItemSnapshot {
    static func importConflictBatchItem(
        conflictID: String,
        strategy: ImportConflictBatchStrategySnapshot,
        status: ImportConflictBatchPreviewStatusSnapshot
    ) -> ImportConflictBatchPreviewItemSnapshot {
        ImportConflictBatchPreviewItemSnapshot(
            conflictID: conflictID,
            conflictType: .duplicateHash,
            existingFileID: 42,
            existingPath: "finance/existing-invoice.pdf",
            incomingPath: "/tmp/Invoice_2026Q1.pdf",
            targetPath: "finance/Invoice_2026Q1.pdf",
            selectedStrategy: strategy,
            status: status,
            willReplace: strategy == .replace,
            willKeepBoth: strategy == .keepBoth,
            willSkip: strategy == .skip,
            willAskPerItem: strategy == .askPerItem,
            indexOnly: false,
            riskSummary: "Existing file remains unless Replace is confirmed.",
            reason: status == .blocked ? "Trash unavailable" : nil
        )
    }
}

extension ImportConflictBatchApplyReportSnapshot {
    static func importConflictBatchIntegrationReport(
        for request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchApplyReportSnapshot {
        let isAskPerItem = request.duplicateStrategy == .askPerItem && request.sameNameStrategy == .askPerItem
        return ImportConflictBatchApplyReportSnapshot(
            importSessionID: request.importSessionID,
            requestedConflictCount: Int64(request.conflictIDs.count),
            resolvedCount: isAskPerItem ? 0 : Int64(request.conflictIDs.count),
            skippedCount: 0, keptBothCount: 0,
            replacedCount: isAskPerItem ? 0 : Int64(request.conflictIDs.count),
            queuedForPerItemCount: isAskPerItem ? Int64(request.conflictIDs.count) : 0,
            pendingCount: 0, failedCount: 0,
            itemResults: request.conflictIDs.map { conflictID in
                let type: ImportConflictBatchConflictTypeSnapshot = conflictID.hasPrefix("name")
                    ? .sameNameDifferentContent
                    : .duplicateHash
                return ImportConflictBatchItemResultSnapshot(
                    conflictID: conflictID,
                    conflictType: type,
                    appliedStrategy: request.duplicateStrategy,
                    status: isAskPerItem ? .queuedForPerItem : .replaced,
                    fileID: isAskPerItem ? nil : 42,
                    finalPath: "finance/Invoice_2026Q1.pdf",
                    error: nil
                )
            },
            affectedFileIDs: isAskPerItem ? [] : [42],
            undoToken: isAskPerItem ? nil : "undo-import-conflict-batch",
            changeLogActions: isAskPerItem ? [] : ["import_conflict_batch"],
            failureSummary: nil
        )
    }
}

extension UndoActionRecordSnapshot {
    static func importConflictBatchIntegrationAction() -> UndoActionRecordSnapshot {
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

extension UndoActionResultSnapshot {
    static func importConflictBatchIntegrationResult() -> UndoActionResultSnapshot {
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
