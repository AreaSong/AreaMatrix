@testable import AreaMatrix
import Foundation

func importBatchInvoiceURL() -> URL {
    importBatchFixtureFileURL("Invoice_2026Q1.pdf")
}

func importBatchContractURL() -> URL {
    importBatchFixtureFileURL("合同.pdf")
}

func importBatchICloudPlaceholderURL(variant: String = "") -> URL {
    importBatchFixtureFileURL("iCloudOnly\(variant).pdf.icloud")
}

func importBatchFixtureRootURL() -> URL {
    URL(fileURLWithPath: "/tmp", isDirectory: true)
}

func importBatchFixtureFileURL(_ filename: String) -> URL {
    importBatchFixtureRootURL().appendingPathComponent(filename)
}

func importBatchUnreadablePreviewURL() -> URL {
    importBatchFixtureFileURL("unreadable.mov")
}

func importBatchUnreadablePreviewMessage(url: URL = importBatchUnreadablePreviewURL()) -> String {
    "无法读取分类预览路径：\(url.path)"
}

func importBatchSourcePath() -> String {
    importBatchFixtureFileURL("source.pdf").path
}

struct ImportBatchStandardBatchFixture {
    let invoiceURL: URL
    let contractURL: URL
    let request: ImportEntryRequest
    let rows: [ImportBatchPreviewRow]

    var urls: [URL] {
        [invoiceURL, contractURL]
    }
}

func importBatchStandardBatchFixture(
    destination: ImportEntryDestination = .autoClassify,
    availableCategories: [String] = ["inbox", "docs", "finance"],
    allowReplaceDuringImport: Bool = false,
    isTrashAvailable: Bool = true
) -> ImportBatchStandardBatchFixture {
    let invoiceURL = importBatchInvoiceURL()
    let contractURL = importBatchContractURL()
    return ImportBatchStandardBatchFixture(
        invoiceURL: invoiceURL,
        contractURL: contractURL,
        request: importBatchBatchRequest(
            destination: destination,
            urls: [invoiceURL, contractURL],
            availableCategories: availableCategories,
            allowReplaceDuringImport: allowReplaceDuringImport,
            isTrashAvailable: isTrashAvailable
        ),
        rows: importBatchReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
    )
}

func importBatchNameConflictContractRow(
    url: URL,
    suggestedName: String = "合同.pdf",
    existingPath: String = "docs/合同.pdf"
) -> ImportBatchPreviewRow {
    ImportBatchPreviewRow.nameConflict(
        url: url,
        prediction: .importBatchPrediction(category: "docs", suggestedName: suggestedName, confidence: 0.82),
        existingPath: existingPath
    )
}

func importBatchDuplicateInvoiceRow(
    url: URL,
    existingPath: String = "finance/Invoice_2026Q1.pdf"
) -> ImportBatchPreviewRow {
    ImportBatchPreviewRow.duplicate(
        url: url,
        prediction: .importBatchPrediction(category: "finance", suggestedName: "Invoice_2026Q1.pdf"),
        existingPath: existingPath
    )
}
