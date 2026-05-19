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

extension MainFileListModel {
    func runSearch(
        query: String,
        scope: SearchScopeSnapshot,
        sort: SearchSortSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot
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
            sidebarRow: sidebarRow
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
        errorMapping = nil
        isLoading = false
    }

    private func loadSearch(_ request: SearchQueryRequestSnapshot) async {
        searchGeneration += 1
        let generation = searchGeneration
        let previousPage = searchState.page

        searchState = .loading(request: request, previousPage: previousPage)
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
            isLoading = false
        }
    }

    private func applySearchPage(_ page: SearchResultPageSnapshot, request: SearchQueryRequestSnapshot) {
        files = page.results.map(\.file)
        searchState = .loaded(request: request, page: page)
        errorMapping = nil
        isLoading = false
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
