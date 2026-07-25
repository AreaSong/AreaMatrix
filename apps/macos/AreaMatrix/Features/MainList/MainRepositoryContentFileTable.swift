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
        let isWriteActionDisabled = !fileListModel.canPerformWriteAction(fileID: file.id)

        Button(L10n.string("Show in Finder")) {
            onShowInFinder(file.path)
        }
        Button(L10n.string("Rename...")) {
            fileListModel.beginRename(fileID: file.id)
        }
        .disabled(isWriteActionDisabled)
        Button(L10n.string("Change Category...")) {
            fileListModel.beginChangeCategory(fileID: file.id)
        }
        .disabled(isWriteActionDisabled)
        Button(L10n.string("Correct Classification...")) {
            fileListModel.beginClassifierCorrection(fileID: file.id)
        }
        .disabled(isWriteActionDisabled)
        Button(L10n.string("Delete..."), role: .destructive) {
            fileListModel.beginDelete(fileID: file.id)
        }
        .disabled(isWriteActionDisabled)
        Divider()
        Button(L10n.string("Copy Path")) {
            onCopyPath(file.path)
        }
    }

    @ViewBuilder
    private func multiFileContextMenu(for selection: Set<Int64>, selectedFiles: [FileEntrySnapshot]) -> some View {
        if selectedFiles.count > 1 {
            Button(L10n.string("Add tags...")) {
                openBatchAddTagsRoute(selection, source: .listContextMenu)
            }
            Button(L10n.string("Change category...")) {
                openBatchChangeCategoryRoute(selection, source: .listContextMenu)
            }
            Button(L10n.string("Rename...")) {
                openBatchRenameRoute(selection, source: .listContextMenu)
            }
            Button(L10n.string("Delete..."), role: .destructive) {
                openBatchDeleteRoute(selection, source: .listContextMenu)
            }
        }
        Button(L10n.string("Copy Paths")) {
            onCopyPaths(selectedFiles.map(\.path))
        }
        .disabled(selectedFiles.isEmpty)
    }

    func files(for selection: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { selection.contains($0.id) }
    }

    var fileTable: some View {
        VStack(spacing: 8) {
            ImportProgressTableView(
                rows: importProgressPresentation.rows,
                selection: $importProgressSelectionState.selectedIDs
            )
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
        VStack(spacing: 8) {
            normalFileTable
            normalListPaginationControls
        }
    }

    private var normalFileTable: some View {
        Table(visibleFiles, selection: $selectedFileIDs, sortOrder: $tableSortOrder) {
            TableColumn(L10n.string("Name"), sortUsing: KeyPathComparator(\FileEntrySnapshot.currentName)) { file in
                Text(file.currentName)
                    .lineLimit(1)
            }
            TableColumn(L10n.string("Category / Path"), sortUsing: KeyPathComparator(\FileEntrySnapshot.path)) { file in
                Text(file.categoryPathDisplay)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn(L10n.string("Match")) { file in
                Text(searchMatchText(for: file.id))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn(L10n.string("Size"), sortUsing: KeyPathComparator(\FileEntrySnapshot.sizeBytes)) { file in
                Text(file.sizeDisplay)
                    .monospacedDigit()
            }
            TableColumn(L10n.string("Modified"), sortUsing: KeyPathComparator(\FileEntrySnapshot.updatedAt)) { file in
                Text(file.updatedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn(L10n.string("Imported"), sortUsing: KeyPathComparator(\FileEntrySnapshot.importedAt)) { file in
                Text(file.importedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn(L10n.string("Status"), sortUsing: KeyPathComparator(\FileEntrySnapshot.statusDisplay)) { file in
                Text(file.statusDisplay)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { selection in
            contextMenu(for: selection)
        } primaryAction: { selection in
            selectedFileIDs = selection
        }
    }

    @ViewBuilder
    private var normalListPaginationControls: some View {
        if !fileListModel.searchState.isActive {
            if let error = fileListModel.loadMoreErrorMapping {
                HStack(spacing: 10) {
                    Text(error.userMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button {
                        Task { await fileListModel.loadMoreCurrentCategory() }
                    } label: {
                        Label(L10n.string("Retry"), systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("main-list-retry-load-more")
                }
            } else if fileListModel.isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.string("Loading more files..."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if fileListModel.hasMore {
                Button {
                    Task { await fileListModel.loadMoreCurrentCategory() }
                } label: {
                    Label(L10n.string("Load More"), systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("main-list-load-more")
            }
        }
    }
}
