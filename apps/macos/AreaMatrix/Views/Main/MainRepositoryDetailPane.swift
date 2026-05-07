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
            } else if let error = detailErrorMapping {
                detailErrorPane(error)
            } else if isDetailLoading {
                detailLoadingPane
            } else if let detail = selectedFileDetail {
                detailMetadataPane(detail)
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
                metadataRows(for: detail)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func metadataRows(for detail: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metadataRow("Category", detail.category)
            metadataRow("Path", detail.path)
            metadataRow("Size", detail.sizeDisplay)
            metadataRow("Storage", detail.storageMode)
            metadataRow("Origin", detail.origin)
            metadataRow("Imported", detail.importedAtDisplay)
            metadataRow("Modified", detail.updatedAtDisplay)
            metadataRow("SHA-256", detail.hashSha256)
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
