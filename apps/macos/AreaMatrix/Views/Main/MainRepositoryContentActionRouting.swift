import SwiftUI

extension MainRepositoryContentView {
    var searchDestinationBinding: Binding<MainSearchDestination?> {
        Binding(
            get: {
                guard fileListModel.pendingSearchDestination?.isSheetRoute == true else { return nil }
                return fileListModel.pendingSearchDestination
            },
            set: { value in
                if value == nil {
                    fileListModel.clearPendingSearchDestination()
                }
            }
        )
    }

    @ViewBuilder
    func searchRoutingSheet(_ destination: MainSearchDestination) -> some View {
        switch destination {
        case let .savedSearchSheet(request):
            SavedSearchSheetRouteView(
                request: request,
                repoPath: opening.config.repoPath,
                resultCountState: savedSearchResultCountState,
                savedSearchStore: savedSearchStore,
                errorMapper: errorMapper,
                onCancel: fileListModel.clearPendingSearchDestination,
                onSaved: saveAndCloseSearchSheet,
                onEditFilters: {
                    fileListModel.clearPendingSearchDestination()
                    isSearchFiltersPresented = true
                }
            )
        case let .indexingStatus(request):
            SearchIndexingStatusRouteView(
                request: request,
                indexStatus: fileListModel.searchState.indexStatus,
                onRetry: { Task { await fileListModel.retrySearch() } },
                onClose: fileListModel.clearPendingSearchDestination
            )
        case .commandPalette:
            commandPaletteRouteView()
        case let .classifierRuleEditor(context):
            ClassifierRuleEditorRouteView(
                repoPath: opening.config.repoPath,
                context: context,
                onCancelFromBatchCategory: cancelClassifierRuleEditorFromBatchCategory,
                onAcceptedCategoryFromBatchCategory: acceptClassifierRuleEditorCategory
            )
        case .searchEmpty, .queryError:
            EmptyView()
        }
    }

    private func saveAndCloseSearchSheet(_ saved: SavedSearchSnapshot) {
        selectSavedSearch(saved)
        fileListModel.clearPendingSearchDestination()
    }
}

extension MainRepositoryContentView {
    func clearSearchQuery() {
        guard !effectiveSearchFilters.isEmpty else {
            clearSearch()
            return
        }
        filterText = ""
        selectedFileIDs = []
        fileListModel.enterSearch(context: .toolbar)
    }

    func clearSearchFiltersFromEmptyState() {
        SearchFilterStateRouting.assign(.empty, searchFilters: &searchFilters, fileListModel: fileListModel)
        selectedFileIDs = []
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearSearch()
        }
    }

    func removeSearchFilterFromEmptyState(_ kind: SearchFilterChipKind) {
        let updated = SearchFilterEditing.removing(kind, from: effectiveSearchFilters)
        SearchFilterStateRouting.assign(updated, searchFilters: &searchFilters, fileListModel: fileListModel)
    }

    func searchAllFileTypesFromEmptyState() {
        removeSearchFilterFromEmptyState(.fileKind)
    }

    func applyQuerySuggestion(_ query: String) {
        filterText = query
        selectedFileIDs = []
        fileListModel.enterSearch(context: .toolbar)
        isSearchFieldFocused = true
    }
}
