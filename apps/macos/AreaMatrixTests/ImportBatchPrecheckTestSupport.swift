@testable import AreaMatrix
import Foundation

actor S118StaticBatchFileLoader: ImportBatchCoreFileLoading {
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

func s118BatchRequest(
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

func s118ReadyBatchRows(
    invoiceURL: URL,
    contractURL: URL
) -> [ImportBatchPreviewRow] {
    [
        s118ReadyBatchRow(url: invoiceURL),
        ImportBatchPreviewRow.ready(
            url: contractURL,
            prediction: .s118Prediction(category: "docs", suggestedName: "2026Q1_合同.pdf", confidence: 0.82)
        )
    ]
}

func s118ReadyBatchRow(
    url: URL,
    suggestedName: String = "Invoice_2026Q1.pdf"
) -> ImportBatchPreviewRow {
    ImportBatchPreviewRow.ready(
        url: url,
        prediction: .s118Prediction(category: "finance", suggestedName: suggestedName)
    )
}

func s118ExpectedAutoClassifyRequests(
    duplicateStrategy: DuplicateStrategy = .ask
) -> [S118BatchImportRequest] {
    [
        S118BatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "finance",
            overrideFilename: "Invoice_2026Q1.pdf",
            duplicateStrategy: duplicateStrategy
        ),
        S118BatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "2026Q1_合同.pdf",
            duplicateStrategy: duplicateStrategy
        )
    ]
}

func s118ExpectedCategoryRequests() -> [S118BatchImportRequest] {
    [
        S118BatchImportRequest(
            destination: .category("finance"),
            suggestedCategory: "finance",
            overrideFilename: "Invoice_2026Q1.pdf",
            duplicateStrategy: .ask
        ),
        S118BatchImportRequest(
            destination: .category("finance"),
            suggestedCategory: "docs",
            overrideFilename: "2026Q1_合同.pdf",
            duplicateStrategy: .ask
        )
    ]
}

extension ClassifyResultSnapshot {
    static func s118Prediction(
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

struct S221IntegrationPreviewRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchPreviewRequestSnapshot
}

struct S221IntegrationApplyRequest: Equatable {
    var repoPath: String
    var request: ImportConflictBatchApplyRequestSnapshot
    var previewToken: String
}

actor S221IntegrationConflictBatcher: CoreImportConflictBatching {
    private var previews: [ImportConflictBatchPreviewReportSnapshot]
    private var recordedPreviewRequests: [S221IntegrationPreviewRequest] = []
    private var recordedApplyRequests: [S221IntegrationApplyRequest] = []

    init(previews: [ImportConflictBatchPreviewReportSnapshot]) { self.previews = previews }

    func previewImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchPreviewRequestSnapshot
    ) async throws -> ImportConflictBatchPreviewReportSnapshot {
        recordedPreviewRequests.append(S221IntegrationPreviewRequest(repoPath: repoPath, request: request))
        guard !previews.isEmpty else { throw CoreError.Conflict(path: "missing S2-21 preview") }
        return previews.removeFirst().withS221Request(request)
    }

    func applyImportConflictBatch(
        repoPath: String,
        request: ImportConflictBatchApplyRequestSnapshot,
        previewToken: String
    ) async throws -> ImportConflictBatchApplyReportSnapshot {
        recordedApplyRequests.append(S221IntegrationApplyRequest(
            repoPath: repoPath,
            request: request,
            previewToken: previewToken
        ))
        return .s221IntegrationReport(for: request)
    }

    func previewRequests() -> [S221IntegrationPreviewRequest] { recordedPreviewRequests }

    func applyRequests() -> [S221IntegrationApplyRequest] { recordedApplyRequests }
}

actor S221IntegrationUndoStore: CoreUndoActionLogging {
    private let actions: Swift.Result<[UndoActionRecordSnapshot], Error>
    private let undoResult: Swift.Result<UndoActionResultSnapshot, Error>
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(
        actions: Swift.Result<[UndoActionRecordSnapshot], Error> = .success([]),
        undoResult: Swift.Result<UndoActionResultSnapshot, Error> = .success(.s221IntegrationResult())
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

    func listRequests() -> [String] { recordedListRequests }

    func undoRequests() -> [String] { recordedUndoRequests }
}

extension ImportConflictBatchPreviewReportSnapshot {
    static func s221Preview(canApply: Bool) -> ImportConflictBatchPreviewReportSnapshot {
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
            items: [.s221Item(
                conflictID: canApply ? "dup-1" : "dup-blocked",
                strategy: .replace,
                status: status
            )]
        )
    }

    func withS221Request(_ request: ImportConflictBatchPreviewRequestSnapshot) -> ImportConflictBatchPreviewReportSnapshot {
        var copy = self
        copy.importSessionID = request.importSessionID
        copy.applyToAllSimilarConflicts = request.applyToAllSimilarConflicts
        copy.requestedConflictCount = Int64(request.conflictIDs.count)
        copy.includedCount = Int64(request.conflictIDs.count)
        copy.items = request.conflictIDs.map { conflictID in
            let source = items.first { $0.conflictID == conflictID }
            let type = source?.conflictType ?? .duplicateHash
            let strategy = type == .duplicateHash ? request.duplicateStrategy : request.sameNameStrategy
            let status = copy.previewStatusForS221Request(strategy: strategy)
            return .s221Item(conflictID: conflictID, strategy: strategy, status: status).withConflictType(type)
        }
        return copy
    }

    private func previewStatusForS221Request(
        strategy: ImportConflictBatchStrategySnapshot
    ) -> ImportConflictBatchPreviewStatusSnapshot {
        guard canApply else { return .blocked }
        return strategy == .replace ? .needsConfirmation : .ready
    }
}

extension ImportConflictBatchPreviewItemSnapshot {
    static func s221Item(
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
    static func s221IntegrationReport(
        for request: ImportConflictBatchApplyRequestSnapshot
    ) -> ImportConflictBatchApplyReportSnapshot {
        let isAskPerItem = request.duplicateStrategy == .askPerItem && request.sameNameStrategy == .askPerItem
        ImportConflictBatchApplyReportSnapshot(
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
                ImportConflictBatchItemResultSnapshot(
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
    static func s221IntegrationAction() -> UndoActionRecordSnapshot {
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
    static func s221IntegrationResult() -> UndoActionResultSnapshot {
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

struct BatchRenamePreviewRequest: Equatable {
    var repoPath: String
    var fileIDs: [Int64]
    var rule: BatchRenameRuleSnapshot
}

struct BatchRenameApplyRequest: Equatable {
    var repoPath: String
    var fileIDs: [Int64]
    var rule: BatchRenameRuleSnapshot
    var token: String
}

actor BatchRenameRecordingRenamer: CoreBatchRenaming {
    private let previewResult: Result<BatchRenamePreviewReportSnapshot, Error>
    private let applyResult: Result<BatchRenameReportSnapshot, Error>
    private(set) var previewRequests: [BatchRenamePreviewRequest] = []
    private(set) var applyRequests: [BatchRenameApplyRequest] = []

    init(preview: Result<BatchRenamePreviewReportSnapshot, Error>, apply: Result<BatchRenameReportSnapshot, Error>) {
        previewResult = preview
        applyResult = apply
    }

    func previewBatchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot {
        previewRequests.append(BatchRenamePreviewRequest(repoPath: repoPath, fileIDs: fileIDs, rule: rule))
        return try previewResult.get()
    }

    func batchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken: String
    ) async throws -> BatchRenameReportSnapshot {
        applyRequests.append(BatchRenameApplyRequest(
            repoPath: repoPath,
            fileIDs: fileIDs,
            rule: rule,
            token: previewToken
        ))
        return try applyResult.get()
    }
}

actor BatchRenameErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private(set) var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }
}

extension CoreErrorMappingSnapshot {
    static var batchRenameConflict: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Could not preview rename",
            severity: .medium,
            suggestedAction: "Refresh preview, then retry.",
            recoverability: .refreshRequired,
            rawContext: "S2-14 C2-10 batch_rename"
        )
    }
}

extension BatchRenameRuleSnapshot {
    static func batchRenameRule(
        _ mode: BatchRenameModeSnapshot,
        prefix: String? = nil,
        dateSource: BatchRenameDateSourceSnapshot? = nil,
        dateFormat: String? = nil,
        separator: String? = nil,
        startNumber: Int64? = nil,
        padding: Int64? = nil,
        find: String? = nil,
        replacement: String? = nil,
        caseSensitive: Bool = false
    ) -> BatchRenameRuleSnapshot {
        BatchRenameRuleSnapshot(
            mode: mode,
            prefix: prefix,
            dateSource: dateSource,
            dateFormat: dateFormat,
            separator: separator,
            startNumber: startNumber,
            padding: padding,
            find: find,
            replacement: replacement,
            caseSensitive: caseSensitive
        )
    }
}

extension BatchRenamePreviewReportSnapshot {
    static func preview(
        rule: BatchRenameRuleSnapshot,
        token: String,
        fileIDs: [Int64],
        canApply: Bool = true
    ) -> BatchRenamePreviewReportSnapshot {
        BatchRenamePreviewReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            rule: rule,
            previewToken: token,
            willRenameCount: Int64(fileIDs.count),
            displayOnlyCount: 0,
            unchangedCount: 0,
            blockedCount: 0,
            conflictCount: 0,
            items: fileIDs.map { .item(id: $0) },
            canApply: canApply,
            applyBlockedReason: canApply ? nil : "No filename changes."
        )
    }

    func with(canApply: Bool) -> BatchRenamePreviewReportSnapshot {
        .preview(rule: rule, token: previewToken, fileIDs: items.map(\.fileID), canApply: canApply)
    }
}

extension BatchRenamePreviewItemSnapshot {
    static func item(id: Int64) -> BatchRenamePreviewItemSnapshot {
        BatchRenamePreviewItemSnapshot(
            fileID: id,
            currentPath: "docs/\(id).pdf",
            originalName: "\(id).pdf",
            newName: "renamed-\(id).pdf",
            targetPath: "docs/renamed-\(id).pdf",
            status: .ok,
            reason: nil
        )
    }
}

extension BatchRenameReportSnapshot {
    static func report(token: String? = nil) -> BatchRenameReportSnapshot {
        BatchRenameReportSnapshot(
            requestedFileCount: 1,
            renamedCount: 1,
            displayNameUpdatedCount: 0,
            unchangedCount: 0,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [],
            updatedFiles: [],
            undoToken: token
        )
    }
}
