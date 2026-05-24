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
