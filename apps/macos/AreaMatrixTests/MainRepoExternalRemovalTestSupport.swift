@testable import AreaMatrix
import Foundation

extension SearchQueryRequestSnapshot {
    static func mainRepoSearchResultsRouteFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .mainRepoSearchResultsRouteFilters,
            sort: .relevance,
            limit: 50,
            offset: 0
        )
    }
}

extension RepositoryOpeningResult {
    static func mainRepoSearchFiltersFixture(
        repoPath: String,
        tree: RepositoryTreeNodeSnapshot
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func mainRepoSearchFiltersFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: []
        )
    }
}

extension SearchFilterStateSnapshot {
    static func mainRepoSearchFiltersFixture(tag: String = "finance") -> SearchFilterStateSnapshot {
        SearchFilterStateSnapshot(
            category: "docs",
            fileKind: "pdf",
            tags: [tag],
            tagMatchMode: .all,
            importedAfter: nil,
            importedBefore: nil,
            modifiedAfter: 1_700_000_000,
            modifiedBefore: nil,
            storageMode: .copied,
            includeDeleted: true
        )
    }

    static let mainRepoSearchResultsRouteFilters = SearchFilterStateSnapshot(
        category: "docs",
        fileKind: "pdf",
        tags: ["contract"],
        tagMatchMode: .any,
        importedAfter: nil,
        importedBefore: nil,
        modifiedAfter: nil,
        modifiedBefore: nil,
        storageMode: .copied,
        includeDeleted: false
    )
}

extension CoreErrorMappingSnapshot {
    static func mainRepoSearchFiltersDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "过滤器不可用",
            severity: .high,
            suggestedAction: "请重试过滤器。",
            recoverability: .retryable,
            rawContext: "facet db locked"
        )
    }
}

struct MainRepoSavedSearchRequestRecord: Equatable {
    var repoPath: String
    var request: CreateSavedSearchRequestSnapshot
}

actor MainRepoSavedSearchRecordingStore: CoreSavedSearchCRUD {
    enum Result {
        case listSuccess([SavedSearchSnapshot])
        case createSuccess(SavedSearchSnapshot)
        case createFailure(Error)
    }

    private var results: [Result]
    private var createRecords: [MainRepoSavedSearchRequestRecord] = []

    init(results: [Result]) {
        self.results = results
    }

    func createSavedSearch(
        repoPath: String,
        request: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        createRecords.append(MainRepoSavedSearchRequestRecord(repoPath: repoPath, request: request))
        guard !results.isEmpty else { throw CoreError.Db(message: "missing saved search result") }
        switch results.removeFirst() {
        case let .createSuccess(saved):
            return saved
        case let .createFailure(error):
            throw error
        case .listSuccess:
            throw CoreError.Internal(message: "expected saved search create result")
        }
    }

    func listSavedSearches(repoPath _: String) async throws -> [SavedSearchSnapshot] {
        guard !results.isEmpty else { return [] }
        switch results.removeFirst() {
        case let .listSuccess(saved):
            return saved
        case .createSuccess, .createFailure:
            throw CoreError.Internal(message: "expected saved search list result")
        }
    }

    func createdRequests() -> [MainRepoSavedSearchRequestRecord] {
        createRecords
    }
}

extension SavedSearchSnapshot {
    static func mainRepoSavedSearchFixture(
        id: Int64,
        request: CreateSavedSearchRequestSnapshot
    ) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: id,
            name: request.name,
            query: request.query,
            icon: request.icon,
            color: request.color,
            pinned: request.pinned,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}
