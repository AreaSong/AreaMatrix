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
        searchActiveFilterCount > 0 ? "Filters (\(searchActiveFilterCount))" : "Filters"
    }

    var searchFiltersAccessibilityLabel: String {
        "\(searchFiltersButtonTitle), \(searchFilterSummaryText)"
    }

    var searchFilterSummaryText: String {
        if fileListModel.isEditingSmartListFilterDraft {
            return "\(searchActiveFilterCount) draft filters active"
        }
        if let error = fileListModel.searchFacetsState.errorMapping {
            return "Could not load filters: \(error.userMessage)"
        }
        if let facets = fileListModel.searchFacetsState.facets {
            return "\(facets.activeFilterCount) filters active, \(facets.totalCount) matching files"
        }
        return "\(searchFilters.activeFilterCount) filters active"
    }

    var searchActiveFilterCount: Int64 {
        if let draft = fileListModel.smartListFilterDraft {
            return draft.activeFilterCount
        }
        return fileListModel.searchFacetsState.facets?.activeFilterCount ?? searchFilters.activeFilterCount
    }

    var searchSaveDisabledReason: String? {
        guard !fileListModel.canSaveCurrentSearch else { return nil }
        if fileListModel.searchState.page?.hasDiagnosticError == true {
            return "Fix query syntax before saving"
        }
        if fileListModel.searchState.request == nil {
            return "Enter a query before saving"
        }
        return "Wait for search results"
    }

    func clearSearch() {
        filterText = ""
        searchMode = .normal
        searchFilters = .empty
        fileListModel.clearSearch()
        selectedFileIDs = []
        if selectedSmartList != nil { selectedSidebarID = Self.defaultSelectedSidebarID(from: regularSidebarRows) }
        searchScope = selectedSidebarRow.categoryForFileList == nil ? .all : .current
        Task { await fileListModel.loadCurrentCategory(selectedSidebarRow.categoryForFileList) }
    }

    func beginCommandFindSearch() {
        fileListModel.enterSearch(context: .commandFind)
        searchMode = .normal
        searchScope = .all
        isSearchFieldFocused = true
    }

    func handleSearchEscape() {
        if searchRoutingState.isToolbarFiltersPresented {
            searchRoutingState.isToolbarFiltersPresented = false
            return
        }
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchFieldFocused = false
            return
        }
        clearSearch()
    }

    func resetSearchFilters() {
        if fileListModel.isEditingSmartListFilterDraft {
            fileListModel.updateSmartListFilterDraft(.empty)
            return
        }
        searchFilters = .empty
    }

    var effectiveSearchFilters: SearchFilterStateSnapshot {
        SearchFilterStateRouting.effective(
            searchFilters: searchFilters,
            draft: fileListModel.smartListFilterDraft
        )
    }

    var searchFiltersBinding: Binding<SearchFilterStateSnapshot> {
        Binding(
            get: { effectiveSearchFilters },
            set: { filters in
                SearchFilterStateRouting.assign(
                    filters,
                    searchFilters: &searchFilters,
                    fileListModel: fileListModel
                )
            }
        )
    }

    var searchFiltersButton: some View {
        Button {
            searchRoutingState.isToolbarFiltersPresented.toggle()
        } label: {
            Label(searchFiltersButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
        }
        .popover(isPresented: $searchRoutingState.isToolbarFiltersPresented) {
            SearchFiltersPopover(
                filters: searchFiltersBinding,
                facetsState: fileListModel.searchFacetsState,
                tagRegistryState: fileListModel.tagFilterRegistryState,
                tagRegistryAnchorFileID: tagRegistryAnchorFileID,
                canSaveAsSmartList: !fileListModel.isEditingSmartListFilterDraft && fileListModel.canSaveCurrentSearch,
                isEditingSmartListDraft: fileListModel.isEditingSmartListFilterDraft,
                saveDisabledReason: searchSaveDisabledReason,
                onReset: {
                    resetSearchFilters()
                },
                onRetry: {
                    Task { await fileListModel.retrySearchFacets() }
                },
                onLoadTagRegistry: { fileID in
                    Task { await fileListModel.loadTagFilterRegistry(activeFileID: fileID) }
                },
                onRetryTagRegistry: {
                    Task { await fileListModel.retryTagFilterRegistry() }
                },
                onSaveAsSmartList: {
                    searchRoutingState.isToolbarFiltersPresented = false
                    fileListModel.openSavedSearchSheet()
                }
            )
        }
        .accessibilityLabel(searchFiltersAccessibilityLabel)
    }

    var tagRegistryAnchorFileID: Int64? {
        fileListModel.selection.singleFileID ?? fileListModel.files.first?.id
    }
}
