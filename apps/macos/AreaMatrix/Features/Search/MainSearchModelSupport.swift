import Foundation

extension MainFileListModel {
    var searchPageDestination: MainSearchDestination? {
        switch searchState {
        case let .loaded(request, page):
            if let diagnostic = page.diagnostics.first(where: \.isError) {
                return .queryError(request, diagnostic)
            }
            if page.indexStatus == .unavailable {
                return nil
            }
            if page.totalCount == 0 {
                return .searchEmpty(request)
            }
            return nil
        case .idle, .loading, .failed:
            return nil
        }
    }

    var canSaveCurrentSearch: Bool {
        guard case let .loaded(request, page) = searchState else { return false }
        return (!request.query.isEmpty || !request.filters.isEmpty) && !page.hasDiagnosticError
    }

    func enterSearch(context: MainSearchEntryContext) {
        lastSearchExitContext = exitContext(for: context)
    }

    var isEditingSmartListFilterDraft: Bool {
        smartListFilterDraft != nil
    }

    func beginSmartListFilterDraft(
        id: Int64,
        name: String,
        filters: SearchFilterStateSnapshot
    ) {
        smartListFilterDraft = SmartListFilterDraft(id: id, name: name, filters: filters)
        enterSearch(context: .smartList(id: id, name: name))
    }

    func updateSmartListFilterDraft(_ filters: SearchFilterStateSnapshot) {
        guard var draft = smartListFilterDraft else { return }
        draft.filters = filters
        smartListFilterDraft = draft
    }

    func cancelSmartListFilterDraft() {
        smartListFilterDraft = nil
    }

    func runSearch(
        query: String,
        scope: SearchScopeSnapshot,
        sort: SearchSortSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot,
        filters: SearchFilterStateSnapshot,
        mode: SearchModeSnapshot = .normal
    ) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty || !filters.isEmpty else {
            clearSearch()
            return
        }

        let request = SearchQueryRequestSnapshot.pageFeature(
            query: trimmedQuery,
            scope: scope,
            sort: sort,
            sidebarRow: sidebarRow,
            filters: filters,
            mode: mode
        )
        activeSmartListSearch = nil
        await loadSearch(request)
    }

    func retrySearch() async {
        if let savedSearch = activeSmartListSearch {
            await loadSmartList(savedSearch)
            return
        }
        guard let request = searchState.request else { return }
        await loadSearch(request)
    }

    func clearSearch() {
        searchGeneration += 1
        searchState = .idle
        pendingSearchDestination = nil
        smartListFilterDraft = nil
        activeSmartListSearch = nil
        clearSearchFacets()
        semanticIndexBuildState = .idle
        semanticIndexControlState = .idle
        semanticPagingState = .idle
        showFoldedSemanticDuplicates = false
        errorMapping = nil
        isLoading = false
        clearDetail()
    }

    func openSavedSearchSheet() {
        guard let request = searchState.request, canSaveCurrentSearch else { return }
        pendingSearchDestination = .savedSearchSheet(request)
    }

    func openIndexingStatus() {
        guard let request = searchState.request,
              searchState.indexStatus == .unavailable else { return }
        pendingSearchDestination = .indexingStatus(request)
    }

    func openCommandPaletteForSearch() {
        pendingSearchDestination = .commandPalette
        enterSearch(context: .commandPalette)
    }

    func clearPendingSearchDestination() {
        pendingSearchDestination = nil
    }

    private func loadSearch(_ request: SearchQueryRequestSnapshot) async {
        searchGeneration += 1
        let generation = searchGeneration
        let previousPage = searchState.page
        activeSmartListSearch = nil

        searchState = .loading(request: request, previousPage: previousPage)
        semanticPagingState = .idle
        showFoldedSemanticDuplicates = false
        pendingSearchDestination = nil
        isLoading = true
        errorMapping = nil
        diagnosticsState = .idle

        do {
            let page = try await searchPage(for: request)
            guard generation == searchGeneration else { return }
            applySearchPage(page, request: request)
            if request.mode == .semantic { await loadSemanticFallbackStatus(for: request) }
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == searchGeneration else { return }
            searchState = .failed(request: request, mappedError)
            pendingSearchDestination = nil
            isLoading = false
            if request.mode == .semantic { semanticFallbackState = .failed(request: request, mappedError) }
        }
    }

    private func applySearchPage(_ page: SearchResultPageSnapshot, request: SearchQueryRequestSnapshot) {
        files = page.results.map(\.file)
        searchState = .loaded(request: request, page: page)
        pendingSearchDestination = nil
        errorMapping = nil
        isLoading = false
    }

    func applySemanticPage(
        _ semanticPage: SemanticSearchResultPageSnapshot,
        to page: SearchResultPageSnapshot,
        request: SearchQueryRequestSnapshot
    ) {
        let updatedPage = page.replacingSemanticPage(semanticPage)
        files = updatedPage.results.map(\.file)
        searchState = .loaded(request: request, page: updatedPage)
        isLoading = false
    }

    func toggleFoldedSemanticDuplicates() {
        showFoldedSemanticDuplicates.toggle()
    }

    func loadMoreSemanticMatches(_ group: SemanticSearchResultGroup) async {
        guard let request = searchState.request,
              let page = searchState.page,
              let semanticPage = page.semanticPage else { return }
        let offset = group == .semantic ? Int64(semanticPage.semanticMatches.count) :
            Int64(semanticPage.normalMatches.count)
        let nextRequest = SearchQueryRequestSnapshot(
            query: request.query,
            scope: request.scope,
            currentPath: request.currentPath,
            category: request.category,
            filters: request.filters,
            sort: request.sort,
            limit: request.limit,
            offset: offset,
            mode: request.mode
        )
        semanticPagingState = SemanticSearchPagingState(
            loadingGroup: group,
            semanticError: group == .normal ? semanticPagingState.semanticError : nil,
            normalError: group == .semantic ? semanticPagingState.normalError : nil
        )
        do {
            let nextPage = try await searchPage(for: nextRequest)
            guard let nextSemanticPage = nextPage.semanticPage else { return }
            let merged = semanticPage.mergingPage(nextSemanticPage, group: group)
            applySemanticPage(merged, to: page, request: request)
            semanticPagingState = .idle
        } catch {
            let mappedError = await mapCoreError(error)
            switch group {
            case .semantic:
                semanticPagingState = SemanticSearchPagingState(
                    semanticError: mappedError,
                    normalError: semanticPagingState.normalError
                )
            case .normal:
                semanticPagingState = SemanticSearchPagingState(
                    semanticError: semanticPagingState.semanticError,
                    normalError: mappedError
                )
            }
        }
    }
}

extension MainFileListModel {
    private func exitContext(for context: MainSearchEntryContext) -> MainSearchExitContext {
        switch context {
        case .toolbar, .commandFind, .commandPalette:
            .toolbar
        case let .smartList(id, name):
            .smartList(id: id, name: name)
        case let .sidebar(id):
            .sidebar(id)
        }
    }

    func loadSearchFacets(
        query: String,
        scope: SearchScopeSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot,
        filters: SearchFilterStateSnapshot
    ) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty || !filters.isEmpty else {
            searchFacetsState = .idle
            return
        }

        let request = SearchFacetRequestSnapshot.pageFeature(
            query: trimmedQuery,
            scope: scope,
            sidebarRow: sidebarRow,
            filters: filters
        )
        await loadSearchFacets(request)
    }

    func retrySearchFacets() async {
        switch searchFacetsState {
        case let .failed(request, _), let .loaded(request, _), let .loading(request, _):
            await loadSearchFacets(request)
        case .idle:
            return
        }
    }

    func clearSearchFacets() {
        searchFacetsGeneration += 1
        searchFacetsState = .idle
    }

    private func loadSearchFacets(_ request: SearchFacetRequestSnapshot) async {
        searchFacetsGeneration += 1
        let generation = searchFacetsGeneration
        let previousFacets = searchFacetsState.facets

        searchFacetsState = .loading(request: request, previousFacets: previousFacets)

        do {
            let facets = try await searchFiltering.listFilterFacets(repoPath: repoPath, request: request)
            guard generation == searchFacetsGeneration else { return }
            searchFacetsState = .loaded(request: request, facets: facets)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == searchFacetsGeneration else { return }
            searchFacetsState = .failed(request: request, mappedError)
        }
    }
}
