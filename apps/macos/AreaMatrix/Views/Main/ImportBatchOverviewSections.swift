import SwiftUI

struct ImportBatchSummarySection: View {
    let totalSizeDescription: String?
    let sourceLabel: String
    let duplicateCount: Int
    let nameConflictCount: Int
    let iCloudPlaceholderCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批量导入摘要")
                .font(.headline)
            HStack(spacing: 16) {
                if let totalSizeDescription {
                    LabeledContent("总大小", value: totalSizeDescription)
                }
                LabeledContent("来源", value: sourceLabel)
                LabeledContent("预计重复", value: "\(duplicateCount) 个")
                LabeledContent("重名冲突", value: "\(nameConflictCount) 个")
                LabeledContent("iCloud", value: "\(iCloudPlaceholderCount) 个")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
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
