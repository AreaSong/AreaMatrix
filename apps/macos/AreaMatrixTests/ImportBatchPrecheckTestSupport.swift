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
        importBatchExpectedInvoiceRequest(duplicateStrategy: duplicateStrategy),
        importBatchExpectedContractRequest(duplicateStrategy: duplicateStrategy)
    ]
}

func importBatchExpectedCategoryRequests() -> [ImportBatchBatchImportRequest] {
    [
        importBatchExpectedInvoiceRequest(destination: .category("finance")),
        importBatchExpectedContractRequest(destination: .category("finance"))
    ]
}

func importBatchExpectedInvoiceRequest(
    storageMode: ImportSingleFileStorageMode = .copy,
    destination: ImportEntryDestination = .autoClassify,
    suggestedCategory: String = "finance",
    overrideFilename: String = "Invoice_2026Q1.pdf",
    duplicateStrategy: DuplicateStrategy = .ask
) -> ImportBatchBatchImportRequest {
    ImportBatchBatchImportRequest(
        storageMode: storageMode,
        destination: destination,
        suggestedCategory: suggestedCategory,
        overrideFilename: overrideFilename,
        duplicateStrategy: duplicateStrategy
    )
}

func importBatchExpectedContractRequest(
    storageMode: ImportSingleFileStorageMode = .copy,
    destination: ImportEntryDestination = .autoClassify,
    suggestedCategory: String = "docs",
    overrideFilename: String = "2026Q1_合同.pdf",
    duplicateStrategy: DuplicateStrategy = .ask
) -> ImportBatchBatchImportRequest {
    ImportBatchBatchImportRequest(
        storageMode: storageMode,
        destination: destination,
        suggestedCategory: suggestedCategory,
        overrideFilename: overrideFilename,
        duplicateStrategy: duplicateStrategy
    )
}
