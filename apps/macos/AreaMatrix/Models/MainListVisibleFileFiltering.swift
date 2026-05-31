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

enum SearchDateFilterPreset { case any, last7Days, last30Days, thisYear }

enum SearchFilterDateField {
    case imported
    case modified

    func summary(in filters: SearchFilterStateSnapshot) -> String {
        let after = afterTimestamp(in: filters)
        let before = beforeTimestamp(in: filters)
        if let after, let before {
            return "\(dateText(after)) - \(dateText(before))"
        }
        return after.map { "Since \(dateText($0))" } ?? "Any"
    }

    func hasCustomRange(in filters: SearchFilterStateSnapshot) -> Bool {
        afterTimestamp(in: filters) != nil && beforeTimestamp(in: filters) != nil
    }

    func afterTimestamp(in filters: SearchFilterStateSnapshot) -> Int64? {
        switch self {
        case .imported:
            filters.importedAfter
        case .modified:
            filters.modifiedAfter
        }
    }

    func beforeTimestamp(in filters: SearchFilterStateSnapshot) -> Int64? {
        switch self {
        case .imported:
            filters.importedBefore
        case .modified:
            filters.modifiedBefore
        }
    }

    func applying(
        after: Int64?,
        before: Int64? = nil,
        to filters: SearchFilterStateSnapshot
    ) -> SearchFilterStateSnapshot {
        var updated = filters
        switch self {
        case .imported:
            updated.importedAfter = after
            updated.importedBefore = before
        case .modified:
            updated.modifiedAfter = after
            updated.modifiedBefore = before
        }
        return updated
    }

    func allowedDateRange(from bounds: SearchDateFacetBoundsSnapshot?) -> ClosedRange<Date> {
        let lower = boundTimestamp(from: bounds, oldest: true)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(timeIntervalSince1970: 0)
        let upper = boundTimestamp(from: bounds, oldest: false)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(timeIntervalSince1970: 4_102_444_800)
        return min(lower, upper) ... max(lower, upper)
    }

    func clearing(in filters: SearchFilterStateSnapshot) -> SearchFilterStateSnapshot {
        applying(after: nil, before: nil, to: filters)
    }

    private func boundTimestamp(from bounds: SearchDateFacetBoundsSnapshot?, oldest: Bool) -> Int64? {
        switch (self, oldest) {
        case (.imported, true):
            bounds?.oldestImportedAt
        case (.imported, false):
            bounds?.newestImportedAt
        case (.modified, true):
            bounds?.oldestModifiedAt
        case (.modified, false):
            bounds?.newestModifiedAt
        }
    }

    private func dateText(_ timestamp: Int64) -> String {
        Self.formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
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
    case classifierRuleEditor(context: BatchChangeCategoryReturnContext?)

    var id: String {
        switch self {
        case let .savedSearchSheet(request): "S2-03-\(request.query)"
        case let .searchEmpty(request): "S2-04-\(request.query)"
        case let .queryError(request, diagnostic): "S2-05-\(request.query)-\(diagnostic.message)"
        case let .indexingStatus(request): "S2-01-indexing-\(request.query)"
        case .commandPalette: "S2-15-command-palette"
        case let .classifierRuleEditor(context):
            "S2-19-classifier-rule-editor-\(context?.handoff.id ?? "settings")"
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
        case .classifierRuleEditor: "S2-19"
        }
    }

    var isSheetRoute: Bool {
        switch self {
        case .savedSearchSheet, .indexingStatus, .commandPalette, .classifierRuleEditor:
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

struct SmartListFilterDraft: Equatable {
    var id: Int64
    var name: String
    var filters: SearchFilterStateSnapshot

    var activeFilterCount: Int64 {
        filters.activeFilterCount
    }
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
        let offset = group == .semantic ? Int64(semanticPage.semanticMatches.count) : Int64(semanticPage.normalMatches.count)
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
