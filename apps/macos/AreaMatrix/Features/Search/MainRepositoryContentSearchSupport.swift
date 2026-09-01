import Foundation
import SwiftUI

extension MainRepositoryContentView {
    var searchTaskKey: String {
        [
            filterText,
            searchMode.rawValue,
            searchScope.rawValue,
            searchSort.rawValue,
            effectiveSearchFilters.taskKey,
            selectedSidebarID
        ].joined(separator: "|")
    }

    var searchFacetsTaskKey: String {
        [
            filterText,
            searchScope.rawValue,
            effectiveSearchFilters.taskKey,
            selectedSidebarID
        ].joined(separator: "|")
    }

    var searchStatusBanner: some View {
        mainRepositorySearchStatusBanner
    }

    var searchFiltersButtonTitle: String {
        searchActiveFilterCount > 0
            ? L10n.plural("search.filterButtonCount", count: searchActiveFilterCount)
            : L10n.string("Filters")
    }

    var searchFiltersAccessibilityLabel: String {
        L10n.format("search.filters.accessibility-label", searchFiltersButtonTitle, searchFilterSummaryText)
    }

    var searchFilterSummaryText: String {
        if searchModel.isEditingSmartListFilterDraft {
            return L10n.plural("search.draftActiveFilterCount", count: searchActiveFilterCount)
        }
        if let error = searchModel.searchFacetsState.errorMapping {
            return L10n.format("search.filters.loadError", error.userMessage)
        }
        if let facets = searchModel.searchFacetsState.facets {
            return L10n.format(
                "%d filters active, %d matching files",
                facets.activeFilterCount,
                facets.totalCount
            )
        }
        return L10n.plural("search.activeFilterCount", count: searchFilters.activeFilterCount)
    }

    var searchActiveFilterCount: Int64 {
        if let draft = searchModel.smartListFilterDraft {
            return draft.activeFilterCount
        }
        return searchModel.searchFacetsState.facets?.activeFilterCount ?? searchFilters.activeFilterCount
    }

    var searchSaveDisabledReason: String? {
        guard !searchModel.canSaveCurrentSearch else { return nil }
        if searchModel.searchState.page?.hasDiagnosticError == true {
            return L10n.string("Fix query syntax before saving")
        }
        if searchModel.searchState.request == nil {
            return L10n.string("Enter a query before saving")
        }
        return L10n.string("Wait for search results")
    }

    func clearSearch() {
        filterText = ""
        searchMode = .normal
        searchFilters = .empty
        searchModel.clearSearch()
        selectionModel.fileIDs = []
        if selectedSmartList != nil { selectedSidebarID = Self.defaultSelectedSidebarID(from: regularSidebarRows) }
        searchScope = selectedSidebarRow.categoryForFileList == nil ? .all : .current
        Task { await fileListModel.loadCurrentCategory(selectedSidebarRow.categoryForFileList) }
    }

    func beginCommandFindSearch() {
        searchModel.enterSearch(context: .commandFind)
        searchMode = .normal
        searchScope = .all
        isSearchFieldFocused = true
    }

    func handleSearchEscape() {
        if searchModel.routingState.isToolbarFiltersPresented {
            searchModel.routingState.isToolbarFiltersPresented = false
            return
        }
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchFieldFocused = false
            return
        }
        clearSearch()
    }

    func resetSearchFilters() {
        if searchModel.isEditingSmartListFilterDraft {
            searchModel.updateSmartListFilterDraft(.empty)
            return
        }
        searchFilters = .empty
    }

    var effectiveSearchFilters: SearchFilterStateSnapshot {
        SearchFilterStateRouting.effective(
            searchFilters: searchFilters,
            draft: searchModel.smartListFilterDraft
        )
    }

    var searchFiltersBinding: Binding<SearchFilterStateSnapshot> {
        Binding(
            get: { effectiveSearchFilters },
            set: { filters in
                SearchFilterStateRouting.assign(
                    filters,
                    searchFilters: &searchFilters,
                    searchModel: searchModel
                )
            }
        )
    }

    var searchFiltersButton: some View {
        Button {
            searchModel.routingState.isToolbarFiltersPresented.toggle()
        } label: {
            Label(searchFiltersButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
        }
        .popover(isPresented: $searchModel.routingState.isToolbarFiltersPresented) {
            SearchFiltersPopover(
                filters: searchFiltersBinding,
                facetsState: searchModel.searchFacetsState,
                tagRegistryState: detailTagModel.filterRegistryState,
                tagRegistryAnchorFileID: tagRegistryAnchorFileID,
                canSaveAsSmartList: !searchModel.isEditingSmartListFilterDraft && searchModel.canSaveCurrentSearch,
                isEditingSmartListDraft: searchModel.isEditingSmartListFilterDraft,
                saveDisabledReason: searchSaveDisabledReason,
                onReset: {
                    resetSearchFilters()
                },
                onRetry: {
                    Task { await searchModel.retrySearchFacets() }
                },
                onLoadTagRegistry: { fileID in
                    Task { await detailTagModel.loadTagFilterRegistry(activeFileID: fileID) }
                },
                onRetryTagRegistry: {
                    Task { await detailTagModel.retryTagFilterRegistry() }
                },
                onSaveAsSmartList: {
                    searchModel.routingState.isToolbarFiltersPresented = false
                    searchModel.openSavedSearchSheet()
                }
            )
        }
        .accessibilityLabel(searchFiltersAccessibilityLabel)
    }

    var tagRegistryAnchorFileID: Int64? {
        fileListModel.selection.singleFileID ?? fileListModel.files.first?.id
    }
}
