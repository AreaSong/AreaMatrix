import SwiftUI

struct MainRepositoryDetailPane: View {
    let selection: MainFileSelectionState
    let detailErrorMapping: CoreErrorMappingSnapshot?
    let isDetailLoading: Bool
    let selectedFileDetail: FileEntrySnapshot?
    let selectedImportProgressRow: ImportProgressListRow?
    let onRetrySelectedFileDetail: () -> Void

    var body: some View {
        Group {
            if let selectedImportProgressRow {
                ImportProgressDetailPane(row: selectedImportProgressRow)
            } else if selection.isMultiple {
                multiSelectionDetailPane
            } else if let detail = selectedFileDetail {
                detailMetadataPane(detail)
            } else if let error = detailErrorMapping {
                detailErrorPane(error)
            } else if isDetailLoading {
                detailLoadingPane
            } else {
                emptyDetailPane
            }
        }
    }

    private var multiSelectionDetailPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Multiple files selected")
                .font(.headline)
            Text("S1-15 detail-multi summary is active. Single-file actions are hidden until one file is selected.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private var emptyDetailPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选择一个文件查看详情")
                .font(.headline)
            Text("文件的元数据、改动时间线和伴生笔记会显示在这里。")
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private var detailLoadingPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading file details")
                .font(.headline)
        }
        .padding(18)
    }

    private func detailErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("File details cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetrySelectedFileDetail)
            DisclosureGroup("Technical Details") {
                Text(error.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(18)
        .accessibilityElement(children: .contain)
    }

    private func detailMetadataPane(_ detail: FileEntrySnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(detail.currentName)
                    .font(.headline)
                    .textSelection(.enabled)
                detailStatusSection
                metadataRows(for: detail)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var detailStatusSection: some View {
        if let error = detailErrorMapping {
            detailInlineError(error)
        } else if isDetailLoading {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Refreshing file details")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func detailInlineError(_ error: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("无法加载文件详情", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetrySelectedFileDetail)
        }
        .padding(10)
        .background(Color.yellow.opacity(0.12))
        .accessibilityElement(children: .contain)
    }

    private func metadataRows(for detail: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(detailMetaMetadataRows(for: detail)) { row in
                metadataRow(row.label, row.value)
            }
        }
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }
}

struct DetailMetaMetadataRow: Equatable, Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
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
        DetailMetaMetadataRow(label: "Status", value: detail.statusDisplay),
    ]
}

private func detailMetaDisplayValue(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Not available" }
    return value
}
