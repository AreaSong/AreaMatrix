import Foundation

protocol CoreSearchQuerying: CoreSmartListRunning, Sendable {
    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot
}

enum SearchScopeSnapshot: String, CaseIterable, Equatable, Identifiable {
    case all
    case current

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .all:
            L10n.string("search.scope.all")
        case .current:
            L10n.string("search.scope.current")
        }
    }

    var bannerDisplayName: String {
        switch self {
        case .all:
            L10n.string("search.scope.repository")
        case .current:
            L10n.string("search.scope.currentShort")
        }
    }
}

enum SearchSortSnapshot: String, CaseIterable, Equatable, Identifiable {
    case relevance
    case newestImported
    case newestModified
    case nameAsc

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .relevance:
            L10n.string("Relevance")
        case .newestImported:
            L10n.string("Newest imported")
        case .newestModified:
            L10n.string("Newest modified")
        case .nameAsc:
            L10n.string("Name A-Z")
        }
    }
}

enum SearchIndexStatusSnapshot: Equatable {
    case ready
    case indexing
    case unavailable
}

enum SearchModeSnapshot: String, CaseIterable, Equatable, Identifiable {
    case normal
    case semantic

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .normal:
            L10n.string("Normal")
        case .semantic:
            L10n.string("Semantic")
        }
    }
}

struct SearchQueryRequestSnapshot: Equatable {
    var query: String
    var scope: SearchScopeSnapshot
    var currentPath: String?
    var category: String?
    var filters: SearchFilterStateSnapshot
    var sort: SearchSortSnapshot
    var limit: Int64
    var offset: Int64
    var mode: SearchModeSnapshot

    init(
        query: String,
        scope: SearchScopeSnapshot,
        currentPath: String?,
        category: String?,
        filters: SearchFilterStateSnapshot,
        sort: SearchSortSnapshot,
        limit: Int64,
        offset: Int64,
        mode: SearchModeSnapshot = .normal
    ) {
        self.query = query
        self.scope = scope
        self.currentPath = currentPath
        self.category = category
        self.filters = filters
        self.sort = sort
        self.limit = limit
        self.offset = offset
        self.mode = mode
    }

    static func pageFeature(
        query: String,
        scope: SearchScopeSnapshot,
        sort: SearchSortSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot,
        filters: SearchFilterStateSnapshot,
        mode: SearchModeSnapshot = .normal
    ) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: scope,
            currentPath: scope == .current ? sidebarRow.pathFilterPrefix : nil,
            category: scope == .current ? sidebarRow.categoryForFileList : nil,
            filters: filters,
            sort: sort,
            limit: 50,
            offset: 0,
            mode: mode
        )
    }

    init(savedSearchQuery: SavedSearchQuerySnapshot) {
        self.init(
            query: savedSearchQuery.query,
            scope: savedSearchQuery.scope,
            currentPath: savedSearchQuery.currentPath,
            category: savedSearchQuery.category,
            filters: savedSearchQuery.filter,
            sort: savedSearchQuery.sort,
            limit: 50,
            offset: 0
        )
    }
}

struct SearchMatchSnapshot: Equatable {
    var fieldDisplayName: String
    var kindDisplayName: String
    var snippet: String
}

struct SearchFileResultSnapshot: Equatable, Identifiable {
    var file: FileEntrySnapshot
    var score: Float
    var matches: [SearchMatchSnapshot]
    var noteSnippet: String?

    var id: Int64 {
        file.id
    }
}

struct SearchQueryDiagnosticSnapshot: Equatable {
    var kindDisplayName: String
    var severityDisplayName: String
    var message: String
    var token: String?
    var start: Int64?
    var end: Int64?
    var suggestion: String?
    private var isErrorSeverity: Bool

    init(
        kindDisplayName: String = "unknown", severityDisplayName: String, message: String, token: String? = nil,
        start: Int64? = nil, end: Int64? = nil, suggestion: String? = nil, isErrorSeverity: Bool = false
    ) {
        self.kindDisplayName = kindDisplayName; self.severityDisplayName = severityDisplayName
        self.message = message; self.token = token; self.start = start
        self.end = end; self.suggestion = suggestion
        self.isErrorSeverity = isErrorSeverity
    }

    var isError: Bool {
        isErrorSeverity
    }

    var problemAccessibilityHint: String {
        [
            token.map { L10n.format("search.diagnostic.token", $0) },
            start.map { value in
                end.map { L10n.format("search.diagnostic.positionRange", value, $0) }
                    ?? L10n.format("search.diagnostic.position", value)
            },
            suggestion.map { L10n.format("search.diagnostic.suggestion", $0) }
        ]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}

struct SearchResultPageSnapshot: Equatable {
    var query: String
    var totalCount: Int64
    var results: [SearchFileResultSnapshot]
    var diagnostics: [SearchQueryDiagnosticSnapshot]
    var indexStatus: SearchIndexStatusSnapshot
    var semanticPage: SemanticSearchResultPageSnapshot?

    var hasDiagnosticError: Bool {
        diagnostics.contains(where: \.isError)
    }
}

extension CoreBridge: CoreSearchQuerying {
    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        let corePage = try await Task.detached(priority: .userInitiated) {
            try searchCoreFiles(repoPath: repoPath, request: request)
        }.value

        var results: [SearchFileResultSnapshot] = []
        results.reserveCapacity(corePage.results.count)
        for result in corePage.results {
            let file = await makeFileEntrySnapshot(from: result.entry, repoPath: repoPath)
            results.append(SearchFileResultSnapshot(coreResult: result, file: file))
        }
        return SearchResultPageSnapshot(corePage: corePage, results: results)
    }
}

extension SearchFilter {
    init(_ snapshot: SearchQueryRequestSnapshot) {
        let filters = snapshot.filters
        self.init(
            scope: SearchScope(snapshot.scope),
            currentPath: snapshot.currentPath,
            category: filters.category ?? snapshot.category,
            fileKind: filters.fileKind,
            tags: filters.tags,
            tagMatchMode: SearchTagMatchMode(filters.tagMatchMode),
            importedAfter: filters.importedAfter,
            importedBefore: filters.importedBefore,
            modifiedAfter: filters.modifiedAfter,
            modifiedBefore: filters.modifiedBefore,
            storageMode: filters.storageMode.map(StorageMode.init),
            includeDeleted: filters.includeDeleted
        )
    }
}

extension SearchScope {
    init(_ snapshot: SearchScopeSnapshot) {
        switch snapshot {
        case .all:
            self = .allRepo
        case .current:
            self = .currentNode
        }
    }
}

extension SearchSort {
    init(_ snapshot: SearchSortSnapshot) {
        switch snapshot {
        case .relevance:
            self = .relevance
        case .newestImported:
            self = .newestImported
        case .newestModified:
            self = .newestModified
        case .nameAsc:
            self = .nameAsc
        }
    }
}

extension SearchFileResultSnapshot {
    init(coreResult: SearchFileResult, file: FileEntrySnapshot) {
        self.file = file
        score = coreResult.score
        matches = coreResult.matches.map(SearchMatchSnapshot.init(coreMatch:))
        noteSnippet = coreResult.noteSnippet
    }
}

extension SearchMatchSnapshot {
    init(coreMatch: SearchMatch) {
        fieldDisplayName = coreMatch.field.displayName
        kindDisplayName = coreMatch.kind.displayName
        snippet = coreMatch.snippet
    }
}

extension SearchResultPageSnapshot {
    init(corePage: SearchResultPage, results: [SearchFileResultSnapshot]) {
        query = corePage.query
        totalCount = corePage.totalCount
        self.results = results
        diagnostics = corePage.diagnostics.map(SearchQueryDiagnosticSnapshot.init(coreDiagnostic:))
        indexStatus = SearchIndexStatusSnapshot(coreStatus: corePage.indexStatus)
    }
}

extension SearchQueryDiagnosticSnapshot {
    init(coreDiagnostic: SearchQueryDiagnostic) {
        self.init(
            kindDisplayName: coreDiagnostic.kind.displayName, severityDisplayName: coreDiagnostic.severity.displayName,
            message: coreDiagnostic.message, token: coreDiagnostic.token, start: coreDiagnostic.start,
            end: coreDiagnostic.end, suggestion: coreDiagnostic.suggestion,
            isErrorSeverity: coreDiagnostic.severity == .error
        )
    }
}

extension SearchIndexStatusSnapshot {
    init(coreStatus: SearchIndexStatus) {
        switch coreStatus {
        case .ready:
            self = .ready
        case .indexing:
            self = .indexing
        case .unavailable:
            self = .unavailable
        }
    }
}

private func searchCoreFiles(repoPath: String, request: SearchQueryRequestSnapshot) throws -> SearchResultPage {
    try searchFiles(
        repoPath: repoPath,
        query: request.query,
        filter: SearchFilter(request),
        sort: SearchSort(request.sort),
        pagination: SearchPagination(limit: request.limit, offset: request.offset)
    )
}
