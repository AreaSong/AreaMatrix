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

struct MainFileActionSheetContainer<Content: View>: View {
    let title: String
    let pageID: String
    private let content: Content

    init(title: String, pageID: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.pageID = pageID
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(22)
        .frame(width: 420, alignment: .leading)
        .accessibilityIdentifier("\(pageID)-file-action-sheet")
    }
}

struct MissingFileActionContext: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The selected file context is no longer available.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}

func metadataRow(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.callout)
            .textSelection(.enabled)
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
