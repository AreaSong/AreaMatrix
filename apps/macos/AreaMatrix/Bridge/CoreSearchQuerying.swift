import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreSearchQuerying = AreaMatrixCoreBridgeContract.CoreSearchQuerying
typealias CoreSmartListRunning = AreaMatrixCoreBridgeContract.CoreSmartListRunning
typealias SearchSortSnapshot = AreaMatrixCoreBridgeContract.SearchSortSnapshot
typealias SearchIndexStatusSnapshot = AreaMatrixCoreBridgeContract.SearchIndexStatusSnapshot
typealias SearchModeSnapshot = AreaMatrixCoreBridgeContract.SearchModeSnapshot
typealias SearchQueryRequestSnapshot = AreaMatrixCoreBridgeContract.SearchQueryRequestSnapshot
typealias SearchQueryPageContext = AreaMatrixCoreBridgeContract.SearchQueryPageContext
typealias SearchMatchSnapshot = AreaMatrixCoreBridgeContract.SearchMatchSnapshot
typealias SearchFileResultSnapshot = AreaMatrixCoreBridgeContract.SearchFileResultSnapshot
typealias SearchQueryDiagnosticSnapshot = AreaMatrixCoreBridgeContract.SearchQueryDiagnosticSnapshot
typealias SearchResultPageSnapshot = AreaMatrixCoreBridgeContract.SearchResultPageSnapshot
typealias SemanticSearchResultPageSnapshot = AreaMatrixCoreBridgeContract.SemanticSearchResultPageSnapshot
typealias SemanticSearchMatchSnapshot = AreaMatrixCoreBridgeContract.SemanticSearchMatchSnapshot
typealias SemanticNormalSearchMatchSnapshot = AreaMatrixCoreBridgeContract.SemanticNormalSearchMatchSnapshot
typealias SemanticIndexBuildReportSnapshot = AreaMatrixCoreBridgeContract.SemanticIndexBuildReportSnapshot
typealias SemanticIndexStatusSnapshot = AreaMatrixCoreBridgeContract.SemanticIndexStatusSnapshot
typealias SemanticSearchRouteSnapshot = AreaMatrixCoreBridgeContract.SemanticSearchRouteSnapshot
typealias SemanticSearchInputFieldSnapshot = AreaMatrixCoreBridgeContract.SemanticSearchInputFieldSnapshot
typealias SemanticSearchFallbackReasonSnapshot = AreaMatrixCoreBridgeContract.SemanticSearchFallbackReasonSnapshot

extension SearchScopeSnapshot {
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

extension SearchSortSnapshot {
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

extension SearchModeSnapshot {
    var displayName: String {
        switch self {
        case .normal:
            L10n.string("Normal")
        case .semantic:
            L10n.string("Semantic")
        }
    }
}

extension SearchQueryRequestSnapshot {
    static func pageFeature(
        query: String,
        scope: SearchScopeSnapshot,
        sort: SearchSortSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot,
        filters: SearchFilterStateSnapshot,
        mode: SearchModeSnapshot = .normal
    ) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot.pageFeature(
            query: query,
            scope: scope,
            sort: sort,
            context: SearchQueryPageContext(
                currentPath: sidebarRow.pathFilterPrefix,
                category: sidebarRow.categoryForFileList,
                filters: filters
            ),
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

extension SearchQueryDiagnosticSnapshot {
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

extension CoreBridge: CoreSearchQuerying {
    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        let corePage = try await Task.detached(priority: .userInitiated) {
            try self.generatedAdapter.searchFiles(
                repoPath: repoPath,
                query: request.query,
                filter: SearchFilter(request),
                sort: SearchSort(request.sort),
                pagination: SearchPagination(limit: request.limit, offset: request.offset)
            )
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
        self.init(
            file: file,
            score: coreResult.score,
            matches: coreResult.matches.map(SearchMatchSnapshot.init(coreMatch:)),
            noteSnippet: coreResult.noteSnippet
        )
    }
}

extension SearchMatchSnapshot {
    init(coreMatch: SearchMatch) {
        self.init(
            fieldDisplayName: coreMatch.field.displayName,
            kindDisplayName: coreMatch.kind.displayName,
            snippet: coreMatch.snippet
        )
    }
}

extension SearchResultPageSnapshot {
    init(corePage: SearchResultPage, results: [SearchFileResultSnapshot]) {
        self.init(
            query: corePage.query,
            totalCount: corePage.totalCount,
            results: results,
            diagnostics: corePage.diagnostics.map(SearchQueryDiagnosticSnapshot.init(coreDiagnostic:)),
            indexStatus: SearchIndexStatusSnapshot(coreStatus: corePage.indexStatus)
        )
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
