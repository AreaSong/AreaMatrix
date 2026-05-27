import Foundation

protocol CoreSavedSearchCRUD: Sendable {
    func createSavedSearch(
        repoPath: String,
        request: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot
    func updateSavedSearch(
        repoPath: String,
        request: UpdateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot
    func deleteSavedSearch(repoPath: String, savedSearchID: Int64) async throws
    func listSavedSearches(repoPath: String) async throws -> [SavedSearchSnapshot]
}

protocol CoreSmartListRunning: Sendable {
    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot
}

extension CoreSavedSearchCRUD {
    func updateSavedSearch(
        repoPath _: String,
        request _: UpdateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        throw CoreError.Internal(message: "update_saved_search is not available in this saved search store")
    }

    func deleteSavedSearch(repoPath _: String, savedSearchID _: Int64) async throws {
        throw CoreError.Internal(message: "delete_saved_search is not available in this saved search store")
    }
}

extension CoreSearchQuerying {
    func runSmartList(
        repoPath _: String,
        savedSearchID _: Int64,
        limit _: Int64,
        offset _: Int64
    ) async throws -> SearchResultPageSnapshot {
        throw CoreError.Internal(message: "run_smart_list is not available in this search store")
    }
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

struct UpdateSavedSearchRequestSnapshot: Equatable {
    var id: Int64
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

protocol CoreBatchRenaming: Sendable {
    func previewBatchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot

    func batchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken: String
    ) async throws -> BatchRenameReportSnapshot
}

extension CoreBridge: CoreFileRenaming, CoreBatchRenaming, CoreSavedSearchCRUD {
    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        let entry = try await Task.detached(priority: .userInitiated) {
            try renameCoreFile(repoPath: repoPath, fileID: fileID, newName: newName)
        }.value
        return await makeFileEntrySnapshot(from: entry, repoPath: repoPath)
    }

    func previewBatchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try BatchRenamePreviewReportSnapshot(coreReport: AreaMatrix.previewBatchRename(
                repoPath: repoPath,
                fileIds: fileIDs,
                rule: BatchRenameRule(rule)
            ))
        }.value
    }

    func batchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken: String
    ) async throws -> BatchRenameReportSnapshot {
        let report = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.batchRename(
                repoPath: repoPath,
                fileIds: fileIDs,
                rule: BatchRenameRule(rule),
                previewToken: previewToken
            )
        }.value
        let updatedFiles = await makeFileEntrySnapshots(from: report.updatedFiles, repoPath: repoPath)
        return BatchRenameReportSnapshot(coreReport: report, updatedFiles: updatedFiles)
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

    func updateSavedSearch(
        repoPath: String,
        request: UpdateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        let saved = try await Task.detached(priority: .userInitiated) {
            try updateCoreSavedSearch(repoPath: repoPath, request: request)
        }.value
        return SavedSearchSnapshot(coreSavedSearch: saved)
    }

    func deleteSavedSearch(repoPath: String, savedSearchID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try deleteCoreSavedSearch(repoPath: repoPath, savedSearchID: savedSearchID)
        }.value
    }

    func listSavedSearches(repoPath: String) async throws -> [SavedSearchSnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try listCoreSavedSearches(repoPath: repoPath).map(SavedSearchSnapshot.init(coreSavedSearch:))
        }.value
    }

    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot {
        let corePage = try await Task.detached(priority: .userInitiated) {
            try runCoreSmartList(repoPath: repoPath, savedSearchID: savedSearchID, limit: limit, offset: offset)
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

private func renameCoreFile(repoPath: String, fileID: Int64, newName: String) throws -> FileEntry {
    try renameFile(repoPath: repoPath, fileId: fileID, newName: newName)
}

extension BatchRenamePreviewReportSnapshot {
    init(coreReport: BatchRenamePreviewReport) {
        requestedFileCount = coreReport.requestedFileCount
        rule = BatchRenameRuleSnapshot(coreRule: coreReport.rule)
        previewToken = coreReport.previewToken
        willRenameCount = coreReport.willRenameCount
        displayOnlyCount = coreReport.displayOnlyCount
        unchangedCount = coreReport.unchangedCount
        blockedCount = coreReport.blockedCount
        conflictCount = coreReport.conflictCount
        items = coreReport.items.map(BatchRenamePreviewItemSnapshot.init)
        canApply = coreReport.canApply
        applyBlockedReason = coreReport.applyBlockedReason
    }
}

extension BatchRenameReportSnapshot {
    init(coreReport: BatchRenameReport, updatedFiles: [FileEntrySnapshot]) {
        requestedFileCount = coreReport.requestedFileCount
        renamedCount = coreReport.renamedCount
        displayNameUpdatedCount = coreReport.displayNameUpdatedCount
        unchangedCount = coreReport.unchangedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(BatchRenameItemResultSnapshot.init)
        self.updatedFiles = updatedFiles
        undoToken = coreReport.undoToken
    }
}

private extension BatchRenameRule {
    init(_ snapshot: BatchRenameRuleSnapshot) {
        self.init(
            mode: BatchRenameMode(snapshot.mode),
            prefix: snapshot.prefix,
            dateSource: snapshot.dateSource.map(BatchRenameDateSource.init),
            dateFormat: snapshot.dateFormat,
            separator: snapshot.separator,
            startNumber: snapshot.startNumber,
            padding: snapshot.padding,
            find: snapshot.find,
            replacement: snapshot.replacement,
            caseSensitive: snapshot.caseSensitive
        )
    }
}

private extension BatchRenameMode {
    init(_ snapshot: BatchRenameModeSnapshot) {
        switch snapshot {
        case .prefix: self = .prefix
        case .datePrefix: self = .datePrefix
        case .keepBaseSequence: self = .keepBaseSequence
        case .replaceText: self = .replaceText
        }
    }
}

private extension BatchRenameDateSource {
    init(_ snapshot: BatchRenameDateSourceSnapshot) {
        switch snapshot {
        case .imported: self = .imported
        case .modified: self = .modified
        case .today: self = .today
        }
    }
}

private func createCoreSavedSearch(
    repoPath: String,
    request: CreateSavedSearchRequestSnapshot
) throws -> SavedSearch {
    try createSavedSearch(repoPath: repoPath, request: CreateSavedSearchRequest(request))
}

private func updateCoreSavedSearch(
    repoPath: String,
    request: UpdateSavedSearchRequestSnapshot
) throws -> SavedSearch {
    try updateSavedSearch(repoPath: repoPath, request: UpdateSavedSearchRequest(request))
}

private func deleteCoreSavedSearch(repoPath: String, savedSearchID: Int64) throws {
    try deleteSavedSearch(repoPath: repoPath, savedSearchId: savedSearchID)
}

private func listCoreSavedSearches(repoPath: String) throws -> [SavedSearch] {
    try listSavedSearches(repoPath: repoPath)
}

private func runCoreSmartList(
    repoPath: String,
    savedSearchID: Int64,
    limit: Int64,
    offset: Int64
) throws -> SearchResultPage {
    try runSmartList(
        repoPath: repoPath,
        savedSearchId: savedSearchID,
        pagination: SearchPagination(limit: limit, offset: offset)
    )
}

extension CoreBridge {
    func makeFileEntrySnapshots(from entries: [FileEntry], repoPath: String) async -> [FileEntrySnapshot] {
        var snapshots: [FileEntrySnapshot] = []
        for entry in entries {
            await snapshots.append(makeFileEntrySnapshot(from: entry, repoPath: repoPath))
        }
        return snapshots
    }
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

extension UpdateSavedSearchRequest {
    init(_ snapshot: UpdateSavedSearchRequestSnapshot) {
        self.init(
            id: snapshot.id,
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
