@testable import AreaMatrix
import Foundation

func importBatchRepoPath() -> String {
    "/tmp/repo"
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
