import SwiftUI

enum ImportEntrySheetHelper {
    static func categoryOptions(
        availableCategories: [String],
        selectedCategory: String,
        predictedCategory: String?
    ) -> [String] {
        let values = availableCategories + [selectedCategory, predictedCategory, "inbox"]
        var uniqueValues: [String] = []
        for value in values.compactMap({ $0 }).filter({ !$0.isEmpty }) where !uniqueValues.contains(value) {
            uniqueValues.append(value)
        }
        return uniqueValues
    }

    static func primaryFileLabel(urls: [URL]) -> String {
        guard let firstURL = urls.first else {
            return "No valid file URL"
        }
        if urls.count == 1 {
            return firstURL.path
        }
        return "\(firstURL.path) and \(urls.count - 1) more"
    }
}

extension ImportEntrySheetView {
    func batchCategoryOptions(
        row: ImportBatchCopyImportRow,
        destination: ImportBatchDestinationOption
    ) -> [String] {
        ImportEntrySheetHelper.categoryOptions(
            availableCategories: request.availableCategories,
            selectedCategory: row.displayCategory(for: destination),
            predictedCategory: row.predictedCategory
        )
    }
}

extension ImportEntryRequest {
    var initialBatchDestination: ImportBatchDestinationOption {
        switch destination {
        case .autoClassify:
            .autoClassify
        case let .category(slug):
            .category(slug)
        case .repositoryRoot:
            .repositoryRoot
        }
    }
}
