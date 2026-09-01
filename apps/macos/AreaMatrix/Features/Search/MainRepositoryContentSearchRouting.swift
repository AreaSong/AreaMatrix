import SwiftUI

extension MainRepositoryContentView {
    func applyMainRepositoryContentSearchTasks(to content: some View) -> some View {
        content
            .task(id: searchTaskKey) {
                guard state == .list else { return }
                guard searchModel.savedSearchesBySidebarID[selectedSidebarID] == nil else { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await searchModel.runSearch(
                    query: filterText,
                    scope: searchScope,
                    sort: searchSort,
                    sidebarRow: selectedSidebarRow,
                    filters: effectiveSearchFilters,
                    mode: searchMode
                )
            }
            .task(id: searchFacetsTaskKey) {
                guard state == .list else { return }
                guard searchModel.savedSearchesBySidebarID[selectedSidebarID] == nil else { return }
                await searchModel.loadSearchFacets(
                    query: filterText,
                    scope: searchScope,
                    sidebarRow: selectedSidebarRow,
                    filters: effectiveSearchFilters
                )
            }
    }

    func applyMainRepositorySearchSheets(to content: some View) -> some View {
        content
            .sheet(item: searchDestinationBinding, content: searchRoutingSheet)
            .sheet(item: $searchModel.routingState.semanticPrivacyRuleRoute, content: semanticPrivacyRuleSheet)
            .sheet(item: $searchModel.routingState.semanticCallLogRoute, content: semanticCallLogSheet)
    }

    func applyMainRepositorySearchFilterDismissRelay(to content: some View) -> some View {
        content.onChange(of: searchModel.routingState.isToolbarFiltersPresented) { _, presented in
            guard !presented else { return }
            reopenSmartListEditorFromDraftIfNeeded()
        }
    }

    var searchDestinationBinding: Binding<MainSearchDestination?> {
        Binding(
            get: {
                guard searchModel.pendingSearchDestination?.isSheetRoute == true else { return nil }
                return searchModel.pendingSearchDestination
            },
            set: { value in
                if value == nil {
                    searchModel.clearPendingSearchDestination()
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
                onCancel: searchModel.clearPendingSearchDestination,
                onSaved: saveAndCloseSearchSheet,
                onEditFilters: {
                    searchModel.clearPendingSearchDestination()
                    searchModel.routingState.isToolbarFiltersPresented = true
                }
            )
        case let .indexingStatus(request):
            SearchIndexingStatusRouteView(
                request: request,
                indexStatus: searchModel.searchState.indexStatus,
                onRetry: { Task { await searchModel.retrySearch() } },
                onClose: searchModel.clearPendingSearchDestination
            )
        case .commandPalette:
            commandPaletteRouteView()
        case let .classifierRuleEditor(context):
            ClassifierRuleEditorRouteView(
                repoPath: opening.config.repoPath,
                context: context,
                settingsDependencies: settingsDependencies,
                errorMapper: errorMapper,
                onCancelFromBatchCategory: cancelClassifierRuleEditorFromBatchCategory,
                onAcceptedCategoryFromBatchCategory: acceptClassifierRuleEditorCategory
            )
        case .searchEmpty, .queryError:
            EmptyView()
        }
    }

    private func saveAndCloseSearchSheet(_ saved: SavedSearchSnapshot) {
        selectSavedSearch(saved)
        searchModel.clearPendingSearchDestination()
    }

    private func reopenSmartListEditorFromDraftIfNeeded() {
        guard let draft = searchModel.smartListFilterDraft else { return }
        let sidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(draft.id)
        guard let saved = searchModel.savedSearchesBySidebarID[sidebarID] else { return }
        searchModel.routingState.smartListManagementRoute = SmartListManagementRoute(
            mode: .editQuery,
            savedSearch: saved,
            draftFilters: draft.filters
        )
    }
}

struct MainRepositorySearchRoutingState: Equatable {
    var isToolbarFiltersPresented = false
    var isSidebarTagsFilterPresented = false
    var smartListManagementRoute: SmartListManagementRoute?
    var isSemanticIndexConfirmationPresented = false
    var semanticPrivacyRuleRoute: AIClassificationPrivacyRuleRoute?
    var semanticCallLogRoute: SemanticSearchCallLogRoute?
}

extension MainRepositoryContentView {
    func applyMainRepositorySemanticIndexDialogs(to content: some View) -> some View {
        content
            .confirmationDialog(
                "Build semantic index?",
                isPresented: $searchModel.routingState.isSemanticIndexConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(L10n.string("Start index build")) {
                    Task { await searchModel.buildSemanticIndexForCurrentSearch() }
                }
                .disabled(!searchModel.semanticPrivacyGateState.allowsIndexBuild)
                semanticIndexRecoveryActions
                Button(L10n.string("Back")) {}
                Button(L10n.string("Cancel"), role: .cancel) {}
            } message: {
                Text(semanticIndexConfirmationMessage)
            }
            .confirmationDialog(
                "Cancel semantic index build?",
                isPresented: Binding(
                    get: {
                        if case .cancelConfirm = searchModel.semanticIndexControlState { return true }
                        return false
                    },
                    set: { if !$0 { searchModel.keepBuildingSemanticIndexForCurrentSearch() } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.string("Cancel index build"), role: .destructive) {
                    Task { await searchModel.cancelSemanticIndexBuildForCurrentSearch() }
                }
                Button(L10n.string("Keep building"), role: .cancel) {
                    searchModel.keepBuildingSemanticIndexForCurrentSearch()
                }
            } message: {
                Text(semanticIndexCancelConfirmationMessage)
            }
    }
}

extension MainRepositoryContentView {
    func clearSearchQuery() {
        guard !effectiveSearchFilters.isEmpty else {
            clearSearch()
            return
        }
        filterText = ""
        selectionModel.fileIDs = []
        searchModel.enterSearch(context: .toolbar)
    }

    func clearSearchFiltersFromEmptyState() {
        SearchFilterStateRouting.assign(.empty, searchFilters: &searchFilters, searchModel: searchModel)
        selectionModel.fileIDs = []
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clearSearch()
        }
    }

    func removeSearchFilterFromEmptyState(_ kind: SearchFilterChipKind) {
        let updated = SearchFilterEditing.removing(kind, from: effectiveSearchFilters)
        SearchFilterStateRouting.assign(updated, searchFilters: &searchFilters, searchModel: searchModel)
    }

    func searchAllFileTypesFromEmptyState() {
        removeSearchFilterFromEmptyState(.fileKind)
    }

    func applyQuerySuggestion(_ query: String) {
        filterText = query
        selectionModel.fileIDs = []
        searchModel.enterSearch(context: .toolbar)
        isSearchFieldFocused = true
    }
}
