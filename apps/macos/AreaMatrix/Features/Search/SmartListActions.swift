import Foundation

extension SearchModel {
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
        let previousPage = state.page

        state = .loading(request: request, previousPage: previousPage)
        pendingDestination = nil
        applyResult(.loading)

        do {
            let page = try await searchQuerying.runSmartList(
                repoPath: repoPath,
                savedSearchID: savedSearch.id,
                limit: request.limit,
                offset: request.offset
            )
            guard generation == searchGeneration else { return }
            state = .loaded(request: request, page: page)
            pendingDestination = nil
            applyResult(.loaded(page.results.map(\.file)))
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == searchGeneration else { return }
            state = .failed(request: request, mappedError)
            pendingDestination = nil
            applyResult(.failed)
        }
    }
}
