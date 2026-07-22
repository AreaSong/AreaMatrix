import Foundation

extension MainFileListModel {
    func searchBannerContextText(for request: SearchQueryRequestSnapshot) -> String {
        activeSmartListSearch
            .map { L10n.format("search.smartList.context", $0.name, request.query) } ??
            L10n.format("search.query.context", request.query)
    }

    func restoreSavedSearch(_ savedSearch: SavedSearchSnapshot) async {
        cancelSmartListFilterDraft()
        enterSearch(context: .smartList(id: savedSearch.id, name: savedSearch.name))
        activeSmartListSearch = savedSearch
        await loadSmartList(savedSearch)
    }

    func loadSmartList(_ savedSearch: SavedSearchSnapshot) async {
        searchGeneration += 1
        let generation = searchGeneration
        let request = SearchQueryRequestSnapshot(savedSearchQuery: savedSearch.query)
        let previousPage = searchState.page

        searchState = .loading(request: request, previousPage: previousPage)
        pendingSearchDestination = nil
        isLoading = true
        errorMapping = nil
        diagnosticsState = .idle

        do {
            let page = try await searchQuerying.runSmartList(
                repoPath: repoPath,
                savedSearchID: savedSearch.id,
                limit: request.limit,
                offset: request.offset
            )
            guard generation == searchGeneration else { return }
            files = page.results.map(\.file)
            searchState = .loaded(request: request, page: page)
            pendingSearchDestination = nil
            errorMapping = nil
            isLoading = false
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == searchGeneration else { return }
            searchState = .failed(request: request, mappedError)
            pendingSearchDestination = nil
            isLoading = false
        }
    }
}
