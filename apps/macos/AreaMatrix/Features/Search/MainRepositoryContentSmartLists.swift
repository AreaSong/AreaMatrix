import SwiftUI

extension MainRepositoryContentView {
    func smartListManagementSheet(_ route: SmartListManagementRoute) -> some View {
        SmartListManagementSheet(
            route: route,
            repoPath: opening.config.repoPath,
            savedSearches: sortedSavedSearches,
            resultCountState: savedSearchResultCountState,
            savedSearchStore: savedSearchStore,
            searchQuerying: fileListModel.searchQuerying,
            errorMapper: errorMapper,
            onCancel: { cancelSmartListManagement(route) },
            onSaved: applyManagedSmartList,
            onDeleted: deleteManagedSmartList,
            onEditFilters: beginSmartListFilterEditing
        )
    }

    var savedSearchResultCountState: SavedSearchResultCountState {
        switch fileListModel.searchState {
        case let .loaded(_, page):
            .loaded(page.totalCount)
        case .failed:
            .failed
        case .idle, .loading:
            .loading
        }
    }

    func selectSavedSearch(_ saved: SavedSearchSnapshot) {
        applySavedSearchToSidebar(saved)
        selectAppliedSavedSearch(saved)
    }

    var selectedSmartList: SavedSearchSnapshot? {
        savedSearchesBySidebarID[selectedSidebarID]
    }

    @ViewBuilder
    var smartListBannerEditButton: some View {
        if selectedSmartList != nil {
            Button("Edit", action: openSelectedSmartListEditor)
        }
    }

    func openSelectedSmartListEditor() {
        guard let saved = selectedSmartList else { return }
        openSmartListManagement(.editQuery, saved: saved)
    }

    private func applyManagedSmartList(_ saved: SavedSearchSnapshot) {
        fileListModel.cancelSmartListFilterDraft()
        applySavedSearchToSidebar(saved)
        if selectedSidebarID == RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id) {
            Task { await restoreSavedSearch(saved) }
        }
        smartListManagementRoute = nil
    }

    private func applySavedSearchToSidebar(_ saved: SavedSearchSnapshot) {
        let sidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        savedSearchesBySidebarID[sidebarID] = saved
        rebuildSmartListSidebar()
    }

    private func selectAppliedSavedSearch(_ saved: SavedSearchSnapshot) {
        filterText = saved.query.query
        searchScope = saved.query.scope
        searchSort = saved.query.sort
        searchFilters = saved.query.filter
        fileListModel.cancelSmartListFilterDraft()
        fileListModel.enterSearch(context: .smartList(id: saved.id, name: saved.name))
        selectedSidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        selectedFileIDs = []
    }

    func restoreSelectedSavedSearchIfNeeded() async -> Bool {
        guard let saved = savedSearchesBySidebarID[selectedSidebarID] else {
            return selectedSidebarRow.isSmartList
        }

        await restoreSavedSearch(saved)
        return true
    }

    func restoreSavedSearch(_ saved: SavedSearchSnapshot) async {
        filterText = saved.query.query
        searchScope = saved.query.scope
        searchSort = saved.query.sort
        searchFilters = saved.query.filter
        await fileListModel.restoreSavedSearch(saved)
    }

    func loadSmartLists() async {
        do {
            let saved = try await savedSearchStore.listSavedSearches(repoPath: opening.config.repoPath)
            await MainActor.run {
                smartListLoadError = nil
                savedSearchesBySidebarID = Dictionary(
                    uniqueKeysWithValues: saved.map {
                        (RepositoryTreeNodeSnapshot.savedSearchSidebarID($0.id), $0)
                    }
                )
                rebuildSmartListSidebar()
            }
        } catch {
            let mapped = await mapSmartListError(error)
            await MainActor.run {
                smartListLoadError = mapped
            }
        }
    }

    func openSmartListManagement(
        _ mode: SmartListManagementMode,
        saved: SavedSearchSnapshot,
        draftFilters: SearchFilterStateSnapshot? = nil
    ) {
        smartListManagementRoute = SmartListManagementRoute(mode: mode, savedSearch: saved, draftFilters: draftFilters)
    }

    private func cancelSmartListManagement(_ route: SmartListManagementRoute) {
        if route.mode == .editQuery {
            fileListModel.cancelSmartListFilterDraft()
        }
        smartListManagementRoute = nil
    }

    private func deleteManagedSmartList(_ saved: SavedSearchSnapshot) {
        let sidebarID = RepositoryTreeNodeSnapshot.savedSearchSidebarID(saved.id)
        savedSearchesBySidebarID.removeValue(forKey: sidebarID)
        repositoryTree = repositoryTree.removingSavedSearch(id: saved.id)
        if selectedSidebarID == sidebarID {
            selectedSidebarID = Self.defaultSelectedSidebarID(from: regularSidebarRows)
            clearSearch()
        }
        smartListManagementRoute = nil
    }

    private func beginSmartListFilterEditing(_ saved: SavedSearchSnapshot, filters: SearchFilterStateSnapshot) {
        fileListModel.beginSmartListFilterDraft(id: saved.id, name: saved.name, filters: filters)
        smartListManagementRoute = nil
        isSearchFiltersPresented = true
    }

    private func rebuildSmartListSidebar() {
        var tree = repositoryTree
        for row in smartListRows {
            if let id = row.savedSearchID {
                tree = tree.removingSavedSearch(id: id)
            }
        }
        for saved in sortedSavedSearches {
            tree = tree.insertingSavedSearch(saved)
        }
        repositoryTree = tree
    }

    private func mapSmartListError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }
}
