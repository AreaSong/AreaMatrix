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
            return L10n.string("No valid file URL")
        }
        if urls.count == 1 {
            return firstURL.path
        }
        return L10n.format("import.entry.additional-files", firstURL.path, urls.count - 1)
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
            Text(L10n.string("The selected file context is no longer available."))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
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
            Picker(L10n.string("导入到"), selection: $selectedDestination) {
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
            Picker(L10n.string("存储模式"), selection: $selectedStorageMode) {
                ForEach(ImportSingleFileStorageMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
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
    @EnvironmentObject private var localizer: AppLocalizer
    let itemCount: Int
    let rows: [ImportBatchCopyImportRow]
    let selectedDestination: ImportBatchDestinationOption
    let isImporting: Bool
    let categoryOptions: (ImportBatchCopyImportRow, ImportBatchDestinationOption) -> [String]
    let onUpdateCategory: (ImportBatchCopyImportRow.ID, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(L10n.plural("import.batch.view-items", count: itemCount)) {
                Table(rows) {
                    TableColumn(L10n.string("原文件名")) { row in
                        sourceCell(for: row)
                    }
                    TableColumn(L10n.string("建议分类")) { row in
                        categoryPicker(for: row)
                    }
                    TableColumn(L10n.string("建议新名称")) { row in
                        Text(row.suggestedName)
                    }
                    TableColumn(L10n.string("状态")) { row in
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
        Picker(L10n.string("建议分类"), selection: categoryBinding(for: row)) {
            ForEach(categoryOptions(row, selectedDestination), id: \.self) {
                Text($0 == "repo root" ? L10n.string("repo root") : $0).tag($0)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160)
        .disabled(isImporting)
    }

    private func statusCell(for row: ImportBatchCopyImportRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(localizer.resolve(row.status.tagMessage))
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
