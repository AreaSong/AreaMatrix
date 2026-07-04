@testable import AreaMatrix
import Foundation

func importBatchResultSummaryRequest(urls: [URL]) -> ImportEntryRequest {
    importBatchBatchRequest(urls: urls, availableCategories: ["inbox", "finance"])
}
