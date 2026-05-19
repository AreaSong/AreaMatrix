import Foundation

enum MainListVisibleFileFiltering {
    static func visibleFiles(
        from files: [FileEntrySnapshot],
        sidebarRow: RepositorySidebarRowSnapshot,
        filterText: String
    ) -> [FileEntrySnapshot] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        return files.filter { file in
            sidebarRow.contains(file) && file.matchesCurrentListFilter(query)
        }
    }
}

enum MainSearchState: Equatable {
    case idle
    case loading(request: SearchQueryRequestSnapshot, previousPage: SearchResultPageSnapshot?)
    case loaded(request: SearchQueryRequestSnapshot, page: SearchResultPageSnapshot)
    case failed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)

    var isActive: Bool {
        request != nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var request: SearchQueryRequestSnapshot? {
        switch self {
        case .idle:
            nil
        case let .loading(request, _), let .loaded(request, _), let .failed(request, _):
            request
        }
    }

    var page: SearchResultPageSnapshot? {
        switch self {
        case let .loaded(_, page):
            page
        case let .loading(_, previousPage):
            previousPage
        case .idle, .failed:
            nil
        }
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        if case let .failed(_, mapping) = self { return mapping }
        return nil
    }

    var indexStatus: SearchIndexStatusSnapshot? {
        page?.indexStatus
    }
}

enum MainSearchFacetsState: Equatable {
    case idle
    case loading(request: SearchFacetRequestSnapshot, previousFacets: SearchFacetsSnapshot?)
    case loaded(request: SearchFacetRequestSnapshot, facets: SearchFacetsSnapshot)
    case failed(request: SearchFacetRequestSnapshot, CoreErrorMappingSnapshot)

    var facets: SearchFacetsSnapshot? {
        switch self {
        case let .loaded(_, facets):
            facets
        case let .loading(_, previousFacets):
            previousFacets
        case .idle, .failed:
            nil
        }
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        if case let .failed(_, mapping) = self { return mapping }
        return nil
    }
}

enum MainSearchDestination: Equatable, Identifiable {
    case savedSearchSheet(SearchQueryRequestSnapshot)
    case searchEmpty(SearchQueryRequestSnapshot)
    case queryError(SearchQueryRequestSnapshot, SearchQueryDiagnosticSnapshot)
    case indexingStatus(SearchQueryRequestSnapshot)
    case commandPalette

    var id: String {
        switch self {
        case let .savedSearchSheet(request):
            "S2-03-\(request.query)"
        case let .searchEmpty(request):
            "S2-04-\(request.query)"
        case let .queryError(request, diagnostic):
            "S2-05-\(request.query)-\(diagnostic.message)"
        case let .indexingStatus(request):
            "S2-01-indexing-\(request.query)"
        case .commandPalette:
            "S2-15-command-palette"
        }
    }

    var pageID: String {
        switch self {
        case .savedSearchSheet:
            "S2-03"
        case .searchEmpty:
            "S2-04"
        case .queryError:
            "S2-05"
        case .indexingStatus:
            "S2-01-indexing-status"
        case .commandPalette:
            "S2-15"
        }
    }

    var isSheetRoute: Bool {
        switch self {
        case .savedSearchSheet, .indexingStatus, .commandPalette:
            true
        case .searchEmpty, .queryError:
            false
        }
    }
}

enum MainSearchEntryContext: Equatable {
    case toolbar
    case commandFind
    case smartList(id: Int64, name: String)
    case commandPalette
    case sidebar(String)
}

enum MainSearchExitContext: Equatable {
    case toolbar
    case smartList(id: Int64, name: String)
    case sidebar(String)
    case list
}

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
        return !request.query.isEmpty && !page.hasDiagnosticError
    }

    func enterSearch(context: MainSearchEntryContext) {
        lastSearchExitContext = exitContext(for: context)
    }

    func runSearch(
        query: String,
        scope: SearchScopeSnapshot,
        sort: SearchSortSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot,
        filters: SearchFilterStateSnapshot
    ) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSearch()
            return
        }

        let request = SearchQueryRequestSnapshot.pageFeature(
            query: trimmedQuery,
            scope: scope,
            sort: sort,
            sidebarRow: sidebarRow,
            filters: filters
        )
        await loadSearch(request)
    }

    func retrySearch() async {
        guard let request = searchState.request else { return }
        await loadSearch(request)
    }

    func clearSearch() {
        searchGeneration += 1
        searchState = .idle
        pendingSearchDestination = nil
        clearSearchFacets()
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

        searchState = .loading(request: request, previousPage: previousPage)
        pendingSearchDestination = nil
        isLoading = true
        errorMapping = nil
        diagnosticsState = .idle

        do {
            let page = try await searchQuerying.searchFiles(repoPath: repoPath, request: request)
            guard generation == searchGeneration else { return }
            applySearchPage(page, request: request)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == searchGeneration else { return }
            searchState = .failed(request: request, mappedError)
            pendingSearchDestination = nil
            isLoading = false
        }
    }

    private func applySearchPage(_ page: SearchResultPageSnapshot, request: SearchQueryRequestSnapshot) {
        files = page.results.map(\.file)
        searchState = .loaded(request: request, page: page)
        pendingSearchDestination = nil
        errorMapping = nil
        isLoading = false
    }

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
        guard !trimmedQuery.isEmpty else {
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

extension FileEntrySnapshot {
    func matchesCurrentListFilter(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }

        return currentName.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    var categoryPathDisplay: String {
        let pathPrefix = path.split(separator: "/").dropLast().joined(separator: "/")
        return pathPrefix.isEmpty ? category : pathPrefix
    }

    var sizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var importedAtDisplay: String {
        Self.mainDisplayDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(importedAt)))
    }

    var updatedAtDisplay: String {
        Self.mainDisplayDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(updatedAt)))
    }

    static let mainDisplayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
