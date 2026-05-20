import Foundation

protocol CoreSavedSearchCRUD: Sendable {
    func createSavedSearch(
        repoPath: String,
        request: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot
    func listSavedSearches(repoPath: String) async throws -> [SavedSearchSnapshot]
}

struct SavedSearchQuerySnapshot: Equatable {
    var query: String
    var filter: SearchFilterStateSnapshot
    var scope: SearchScopeSnapshot
    var currentPath: String?
    var category: String?
    var sort: SearchSortSnapshot

    init(request: SearchQueryRequestSnapshot) {
        query = request.query
        filter = request.filters
        scope = request.scope
        currentPath = request.currentPath
        category = request.category
        sort = request.sort
    }
}

struct CreateSavedSearchRequestSnapshot: Equatable {
    var name: String
    var query: SavedSearchQuerySnapshot
    var icon: String?
    var color: String?
    var pinned: Bool
}

struct SavedSearchSnapshot: Equatable, Identifiable {
    var id: Int64
    var name: String
    var query: SavedSearchQuerySnapshot
    var icon: String?
    var color: String?
    var pinned: Bool
    var createdAt: Int64
    var updatedAt: Int64
}

protocol CoreFileRenaming: Sendable {
    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot
}

extension CoreBridge: CoreFileRenaming, CoreSavedSearchCRUD {
    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        let entry = try await Task.detached(priority: .userInitiated) {
            try renameCoreFile(repoPath: repoPath, fileID: fileID, newName: newName)
        }.value
        return await makeFileEntrySnapshot(from: entry, repoPath: repoPath)
    }

    func createSavedSearch(
        repoPath: String,
        request: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        let saved = try await Task.detached(priority: .userInitiated) {
            try createCoreSavedSearch(repoPath: repoPath, request: request)
        }.value
        return SavedSearchSnapshot(coreSavedSearch: saved)
    }

    func listSavedSearches(repoPath: String) async throws -> [SavedSearchSnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try listCoreSavedSearches(repoPath: repoPath).map(SavedSearchSnapshot.init(coreSavedSearch:))
        }.value
    }
}

private func renameCoreFile(repoPath: String, fileID: Int64, newName: String) throws -> FileEntry {
    try renameFile(repoPath: repoPath, fileId: fileID, newName: newName)
}

private func createCoreSavedSearch(
    repoPath: String,
    request: CreateSavedSearchRequestSnapshot
) throws -> SavedSearch {
    try createSavedSearch(repoPath: repoPath, request: CreateSavedSearchRequest(request))
}

private func listCoreSavedSearches(repoPath: String) throws -> [SavedSearch] {
    try listSavedSearches(repoPath: repoPath)
}

extension SavedSearchQuery {
    init(_ snapshot: SavedSearchQuerySnapshot) {
        let request = SearchQueryRequestSnapshot(
            query: snapshot.query,
            scope: snapshot.scope,
            currentPath: snapshot.currentPath,
            category: snapshot.category,
            filters: snapshot.filter,
            sort: snapshot.sort,
            limit: 50,
            offset: 0
        )
        self.init(query: snapshot.query, filter: SearchFilter(request), sort: SearchSort(snapshot.sort))
    }
}

extension CreateSavedSearchRequest {
    init(_ snapshot: CreateSavedSearchRequestSnapshot) {
        self.init(
            name: snapshot.name,
            query: SavedSearchQuery(snapshot.query),
            icon: snapshot.icon,
            color: snapshot.color,
            pinned: snapshot.pinned
        )
    }
}

extension SavedSearchSnapshot {
    init(coreSavedSearch: SavedSearch) {
        id = coreSavedSearch.id
        name = coreSavedSearch.name
        query = SavedSearchQuerySnapshot(coreQuery: coreSavedSearch.query)
        icon = coreSavedSearch.icon
        color = coreSavedSearch.color
        pinned = coreSavedSearch.pinned
        createdAt = coreSavedSearch.createdAt
        updatedAt = coreSavedSearch.updatedAt
    }
}

extension SavedSearchQuerySnapshot {
    init(coreQuery: SavedSearchQuery) {
        query = coreQuery.query
        filter = SearchFilterStateSnapshot(coreFilter: coreQuery.filter)
        scope = SearchScopeSnapshot(coreScope: coreQuery.filter.scope)
        currentPath = coreQuery.filter.currentPath
        category = coreQuery.filter.category
        sort = SearchSortSnapshot(coreSort: coreQuery.sort)
    }
}

extension SearchScopeSnapshot {
    init(coreScope: SearchScope) {
        switch coreScope {
        case .allRepo:
            self = .all
        case .currentNode:
            self = .current
        }
    }
}

extension SearchSortSnapshot {
    init(coreSort: SearchSort) {
        switch coreSort {
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

extension SearchFilterStateSnapshot {
    init(coreFilter: SearchFilter) {
        category = coreFilter.category
        fileKind = coreFilter.fileKind
        tags = coreFilter.tags
        tagMatchMode = SearchTagMatchModeSnapshot(coreMode: coreFilter.tagMatchMode)
        importedAfter = coreFilter.importedAfter
        importedBefore = coreFilter.importedBefore
        modifiedAfter = coreFilter.modifiedAfter
        modifiedBefore = coreFilter.modifiedBefore
        storageMode = coreFilter.storageMode.map(SearchStorageModeSnapshot.init(coreMode:))
        includeDeleted = coreFilter.includeDeleted ?? false
    }
}

extension SearchTagMatchModeSnapshot {
    init(coreMode: SearchTagMatchMode) {
        switch coreMode {
        case .any:
            self = .any
        case .all:
            self = .all
        }
    }
}
