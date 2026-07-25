import SwiftUI

extension MainRepositoryDetailPane {
    var multiSelectionDetailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                multiSelectionHeader
                multiSelectionWarnings
                multiSelectionStatistics
                multiSelectionFileTypes
                multiSelectionActions
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
    }

    private var multiSelectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(multiSelectionSummary.title)
                .font(.headline)
            Text(multiSelectionSummary.subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if multiSelectionSummary.isUpdating {
                Label(L10n.string("Updating selection..."), systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let detailErrorMapping {
                Label(detailErrorMapping.userMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var multiSelectionWarnings: some View {
        if !multiSelectionSummary.warningMessages.isEmpty {
            TintedStatusBanner(
                tint: .yellow,
                cornerRadius: 0,
                fillsWidth: false,
                contentPadding: 10,
                backgroundOpacity: 0.12
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(multiSelectionSummary.warningMessages, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                    }
                }
            }
        }
    }

    private var multiSelectionStatistics: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(multiSelectionSummary.statisticRows) { row in
                multiSelectionMetadataRow(row.label, row.value)
            }
        }
    }

    @ViewBuilder
    private var multiSelectionFileTypes: some View {
        if !multiSelectionSummary.fileTypeRows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("File types"))
                    .font(.callout.weight(.semibold))
                ForEach(multiSelectionSummary.fileTypeRows) { row in
                    multiSelectionMetadataRow(row.label, row.value)
                }
            }
        }
    }

    private var multiSelectionActions: some View {
        MainRepositoryMultiSelectionActions(
            selection: selection,
            summary: multiSelectionSummary,
            detailErrorMapping: detailErrorMapping,
            repoPath: repoPath,
            categoryRows: categoryRows,
            batchTagStore: batchTagStore,
            batchTagUndoStore: batchTagUndoStore,
            batchTagErrorMapper: batchTagErrorMapper,
            batchDeleter: batchDeleter,
            batchCategoryChanger: batchCategoryChanger,
            batchRenamer: batchRenamer,
            tagActions: tagActions,
            writeActionDisabledReason: writeActionDisabledReason,
            onCopyPaths: onCopyPaths,
            onRetrySelectedFileDetail: onRetrySelectedFileDetail,
            onRefreshChangeLog: onRefreshChangeLog,
            onBatchCategoryApplied: onBatchCategoryApplied,
            onBatchDeleteApplied: onBatchDeleteApplied,
            onBatchRenameApplied: onBatchRenameApplied,
            onBatchCategoryCreateNewCategory: onBatchCategoryCreateNewCategory
        )
    }

    private func multiSelectionMetadataRow(_ label: String, _ value: String) -> some View {
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
