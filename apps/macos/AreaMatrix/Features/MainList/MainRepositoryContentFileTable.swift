import SwiftUI

extension MainRepositoryContentView {
    @ViewBuilder
    func contextMenu(for selection: Set<Int64>) -> some View {
        let selectedFiles = files(for: selection)
        if selectedFiles.count == 1, let file = selectedFiles.first {
            singleFileContextMenu(for: file)
        } else {
            multiFileContextMenu(for: selection, selectedFiles: selectedFiles)
        }
    }

    @ViewBuilder
    private func singleFileContextMenu(for file: FileEntrySnapshot) -> some View {
        Button("Show in Finder") {
            onShowInFinder(file.path)
        }
        Button("Rename...") {
            fileListModel.beginRename(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Change Category...") {
            fileListModel.beginChangeCategory(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Correct Classification...") {
            fileListModel.beginClassifierCorrection(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Delete...", role: .destructive) {
            fileListModel.beginDelete(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Divider()
        Button("Copy Path") {
            onCopyPath(file.path)
        }
    }

    @ViewBuilder
    private func multiFileContextMenu(for selection: Set<Int64>, selectedFiles: [FileEntrySnapshot]) -> some View {
        if selectedFiles.count > 1 {
            Button("Add tags...") {
                openBatchAddTagsRoute(selection, source: .listContextMenu)
            }
            Button("Change category...") {
                openBatchChangeCategoryRoute(selection, source: .listContextMenu)
            }
            Button("Rename...") {
                openBatchRenameRoute(selection, source: .listContextMenu)
            }
            Button("Delete...", role: .destructive) {
                openBatchDeleteRoute(selection, source: .listContextMenu)
            }
        }
        Button("Copy Paths") {
            onCopyPaths(selectedFiles.map(\.path))
        }
        .disabled(selectedFiles.isEmpty)
    }

    func files(for selection: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { selection.contains($0.id) }
    }

    var fileTable: some View {
        VStack(spacing: 8) {
            ImportProgressTableView(rows: importProgressRows, selection: $selectedImportProgressIDs)
            if let semanticPage = fileListModel.searchState.page?.semanticPage {
                semanticResultsContent(semanticPage)
            } else {
                fileTableContent
            }
        }
        .overlay { emptyListOverlay }
    }

    private func semanticResultsContent(_ page: SemanticSearchResultPageSnapshot) -> some View {
        SemanticSearchResultsView(
            page: page,
            selectedFileIDs: $selectedFileIDs,
            showFoldedDuplicates: fileListModel.showFoldedSemanticDuplicates,
            pagingState: fileListModel.semanticPagingState,
            onToggleDuplicates: fileListModel.toggleFoldedSemanticDuplicates,
            onLoadMoreSemantic: {
                Task { await fileListModel.loadMoreSemanticMatches(.semantic) }
            },
            onLoadMoreNormal: {
                Task { await fileListModel.loadMoreSemanticMatches(.normal) }
            },
            onRetrySemanticPage: {
                Task { await fileListModel.loadMoreSemanticMatches(.semantic) }
            },
            onRetryNormalPage: {
                Task { await fileListModel.loadMoreSemanticMatches(.normal) }
            },
            contextMenu: { selection in AnyView(contextMenu(for: selection)) },
            onPrimaryAction: { selection in selectedFileIDs = selection }
        )
    }

    private var fileTableContent: some View {
        Table(visibleFiles, selection: $selectedFileIDs, sortOrder: $tableSortOrder) {
            TableColumn("Name", sortUsing: KeyPathComparator(\FileEntrySnapshot.currentName)) { file in
                Text(file.currentName)
                    .lineLimit(1)
            }
            TableColumn("Category / Path", sortUsing: KeyPathComparator(\FileEntrySnapshot.path)) { file in
                Text(file.categoryPathDisplay)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Match") { file in
                Text(searchMatchText(for: file.id))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Size", sortUsing: KeyPathComparator(\FileEntrySnapshot.sizeBytes)) { file in
                Text(file.sizeDisplay)
                    .monospacedDigit()
            }
            TableColumn("Modified", sortUsing: KeyPathComparator(\FileEntrySnapshot.updatedAt)) { file in
                Text(file.updatedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Imported", sortUsing: KeyPathComparator(\FileEntrySnapshot.importedAt)) { file in
                Text(file.importedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Status", sortUsing: KeyPathComparator(\FileEntrySnapshot.statusDisplay)) { file in
                Text(file.statusDisplay)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { selection in
            contextMenu(for: selection)
        } primaryAction: { selection in
            selectedFileIDs = selection
        }
    }
}
