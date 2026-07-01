@testable import AreaMatrix
import Foundation

func importBatchRepoPath() -> String {
    "/tmp/repo"
}

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
    repoPath: String = importBatchRepoPath(),
    destination: ImportEntryDestination = .autoClassify,
    urls: [URL],
    availableCategories: [String] = ["inbox", "docs", "finance"],
    allowReplaceDuringImport: Bool = false,
    isTrashAvailable: Bool = true
) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: repoPath,
        source: .dropZone,
        destination: destination,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: availableCategories,
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

typealias ImportConflictBatchIntegrationUndoStore = LenientUndoActionRecordingTestStore
