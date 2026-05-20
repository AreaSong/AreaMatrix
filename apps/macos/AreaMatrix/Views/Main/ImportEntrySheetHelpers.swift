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

struct ImportBatchDestinationSection: View {
    @Binding var selectedDestination: ImportBatchDestinationOption
    let destinationOptions: [ImportBatchDestinationOption]
    @Binding var selectedStorageMode: ImportSingleFileStorageMode
    @Binding var selectedNamingStrategy: ImportBatchNamingStrategy
    @Binding var namingPrefix: String
    let isImporting: Bool
    let destinationHelperMessage: String?
    let storageModeRiskMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("导入到", selection: $selectedDestination) {
                ForEach(destinationOptions, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isImporting)

            storageModePicker

            ImportBatchNamingOptionsSection(
                selectedStrategy: $selectedNamingStrategy,
                prefix: $namingPrefix,
                isDisabled: isImporting
            )

            if let destinationHelperMessage {
                Text(destinationHelperMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var storageModePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("存储模式", selection: $selectedStorageMode) {
                ForEach(ImportSingleFileStorageMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .disabled(isImporting)

            Text(selectedStorageMode.explanation)
                .font(.caption)
                .foregroundStyle(selectedStorageMode == .copy ? Color.secondary : Color.orange)

            if let storageModeRiskMessage {
                Text(storageModeRiskMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct ImportBatchRowsSection: View {
    let itemCount: Int
    let rows: [ImportBatchCopyImportRow]
    let selectedDestination: ImportBatchDestinationOption
    let isImporting: Bool
    let categoryOptions: (ImportBatchCopyImportRow, ImportBatchDestinationOption) -> [String]
    let onUpdateCategory: (ImportBatchCopyImportRow.ID, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("查看 \(itemCount) 个项目") {
                Table(rows) {
                    TableColumn("原文件名") { row in
                        sourceCell(for: row)
                    }
                    TableColumn("建议分类") { row in
                        categoryPicker(for: row)
                    }
                    TableColumn("建议新名称") { row in
                        Text(row.suggestedName)
                    }
                    TableColumn("状态") { row in
                        statusCell(for: row)
                    }
                }
                .frame(minHeight: 240)
            }
            .disabled(rows.isEmpty)
        }
    }

    private func sourceCell(for row: ImportBatchCopyImportRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.originalName)
            Text(row.sourcePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func categoryPicker(for row: ImportBatchCopyImportRow) -> some View {
        Picker("建议分类", selection: categoryBinding(for: row)) {
            ForEach(categoryOptions(row, selectedDestination), id: \.self) {
                Text($0).tag($0)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .disabled(isImporting)
    }

    private func statusCell(for row: ImportBatchCopyImportRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.status.tag)
                .font(.caption.weight(.semibold))
            if let detail = row.status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func categoryBinding(for row: ImportBatchCopyImportRow) -> Binding<String> {
        Binding(
            get: { row.displayCategory(for: selectedDestination) },
            set: { onUpdateCategory(row.id, $0) }
        )
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

struct DetailMetaMetadataRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String {
        label
    }
}

func detailMetaMetadataRows(for detail: FileEntrySnapshot) -> [DetailMetaMetadataRow] {
    [
        DetailMetaMetadataRow(label: "Category", value: detail.category),
        DetailMetaMetadataRow(label: "Path", value: detail.path),
        DetailMetaMetadataRow(label: "Size", value: detail.sizeDisplay),
        DetailMetaMetadataRow(label: "Storage", value: detail.storageMode),
        DetailMetaMetadataRow(label: "Origin", value: detail.origin),
        DetailMetaMetadataRow(label: "Imported", value: detail.importedAtDisplay),
        DetailMetaMetadataRow(label: "Modified", value: detail.updatedAtDisplay),
        DetailMetaMetadataRow(label: "SHA-256", value: detail.hashSha256),
        DetailMetaMetadataRow(label: "Source", value: detailMetaDisplayValue(detail.sourcePath)),
        DetailMetaMetadataRow(label: "Status", value: detail.statusDisplay)
    ]
}

private func detailMetaDisplayValue(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Not available" }
    return value
}
