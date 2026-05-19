import Foundation

protocol CoreFileListing: Sendable {
    func listFiles(repoPath: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot]
}

protocol CoreFileDetailing: Sendable {
    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot
}

protocol CoreSearchQuerying: Sendable {
    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot
}

struct FileFilterSnapshot: Equatable {
    var category: String?
    var includeDeleted: Bool?
    var importedAfter: Int64?
    var importedBefore: Int64?
    var limit: Int64
    var offset: Int64

    static func currentCategory(_ category: String?) -> FileFilterSnapshot {
        FileFilterSnapshot(
            category: category,
            includeDeleted: false,
            importedAfter: nil,
            importedBefore: nil,
            limit: 50,
            offset: 0
        )
    }
}

enum SearchScopeSnapshot: String, CaseIterable, Equatable, Identifiable {
    case all
    case current

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            "All"
        case .current:
            "Current"
        }
    }

    var bannerDisplayName: String {
        switch self {
        case .all:
            "全库"
        case .current:
            "当前"
        }
    }
}

enum SearchSortSnapshot: String, CaseIterable, Equatable, Identifiable {
    case relevance
    case newestImported
    case newestModified
    case nameAsc

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relevance:
            "Relevance"
        case .newestImported:
            "Newest imported"
        case .newestModified:
            "Newest modified"
        case .nameAsc:
            "Name A-Z"
        }
    }
}

enum SearchIndexStatusSnapshot: Equatable {
    case ready
    case indexing
    case unavailable
}

struct SearchQueryRequestSnapshot: Equatable {
    var query: String
    var scope: SearchScopeSnapshot
    var currentPath: String?
    var category: String?
    var sort: SearchSortSnapshot
    var limit: Int64
    var offset: Int64

    static func pageFeature(
        query: String,
        scope: SearchScopeSnapshot,
        sort: SearchSortSnapshot,
        sidebarRow: RepositorySidebarRowSnapshot
    ) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: scope,
            currentPath: scope == .current ? sidebarRow.pathFilterPrefix : nil,
            category: scope == .current ? sidebarRow.categoryForFileList : nil,
            sort: sort,
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

    var id: Int64 { file.id }
}

struct SearchQueryDiagnosticSnapshot: Equatable {
    var severityDisplayName: String
    var message: String
    var suggestion: String?

    var isError: Bool {
        severityDisplayName == "Error"
    }
}

struct SearchResultPageSnapshot: Equatable {
    var query: String
    var totalCount: Int64
    var results: [SearchFileResultSnapshot]
    var diagnostics: [SearchQueryDiagnosticSnapshot]
    var indexStatus: SearchIndexStatusSnapshot

    var hasDiagnosticError: Bool {
        diagnostics.contains(where: \.isError)
    }
}

enum FileAvailabilitySnapshot: String, Equatable {
    case available
    case missing
    case iCloudPlaceholder
}

protocol FileAvailabilityChecking: Sendable {
    func availability(repoPath: String, relativePath: String, sourcePath: String?) async -> FileAvailabilitySnapshot
}

struct LocalFileAvailabilityChecker: FileAvailabilityChecking {
    func availability(repoPath: String, relativePath: String, sourcePath: String?) async -> FileAvailabilitySnapshot {
        FileAvailabilityResolver.availability(repoPath: repoPath, relativePath: relativePath, sourcePath: sourcePath)
    }
}

struct FileEntrySnapshot: Equatable, Identifiable {
    var id: Int64
    var path: String
    var originalName: String
    var currentName: String
    var category: String
    var sizeBytes: Int64
    var hashSha256: String
    var storageMode: String
    var origin: String
    var sourcePath: String?
    var importedAt: Int64
    var updatedAt: Int64
    var availability: FileAvailabilitySnapshot = .available
}

extension FileEntrySnapshot {
    var statusDisplay: String {
        switch availability {
        case .missing:
            "Missing"
        case .iCloudPlaceholder:
            "iCloud"
        case .available:
            storageMode == "Indexed" ? "Index-only" : "OK"
        }
    }
}

extension CoreBridge: CoreFileListing, CoreFileDetailing, CoreSearchQuerying {
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

extension FileFilter {
    init(_ snapshot: FileFilterSnapshot) {
        self.init(
            category: snapshot.category,
            includeDeleted: snapshot.includeDeleted,
            importedAfter: snapshot.importedAfter,
            importedBefore: snapshot.importedBefore,
            limit: snapshot.limit,
            offset: snapshot.offset
        )
    }
}

extension SearchFilter {
    init(_ snapshot: SearchQueryRequestSnapshot) {
        self.init(
            scope: SearchScope(snapshot.scope),
            currentPath: snapshot.currentPath,
            category: snapshot.category,
            fileKind: nil,
            tags: [],
            tagMatchMode: .any,
            importedAfter: nil,
            importedBefore: nil,
            modifiedAfter: nil,
            modifiedBefore: nil,
            storageMode: nil,
            includeDeleted: false
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

extension FileEntrySnapshot {
    init(coreEntry: FileEntry, availabilityChecker: (String, String?) -> FileAvailabilitySnapshot) {
        id = coreEntry.id
        path = coreEntry.path
        originalName = coreEntry.originalName
        currentName = coreEntry.currentName
        category = coreEntry.category
        sizeBytes = coreEntry.sizeBytes
        hashSha256 = coreEntry.hashSha256
        storageMode = coreEntry.storageMode.fileListDisplayName
        origin = coreEntry.origin.fileListDisplayName
        sourcePath = coreEntry.sourcePath
        importedAt = coreEntry.importedAt
        updatedAt = coreEntry.updatedAt
        availability = availabilityChecker(coreEntry.path, coreEntry.sourcePath)
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

extension SearchQueryDiagnosticSnapshot {
    init(coreDiagnostic: SearchQueryDiagnostic) {
        severityDisplayName = coreDiagnostic.severity.displayName
        message = coreDiagnostic.message
        suggestion = coreDiagnostic.suggestion
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

private enum FileAvailabilityResolver {
    static func availability(repoPath: String, relativePath: String, sourcePath: String?) -> FileAvailabilitySnapshot {
        if isICloudPlaceholder(relativePath) || sourcePath.map(isICloudPlaceholder) == true {
            return .iCloudPlaceholder
        }

        let fileURL = URL(fileURLWithPath: repoPath, isDirectory: true).appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: fileURL.path) ? .available : .missing
    }

    private static func isICloudPlaceholder(_ path: String) -> Bool {
        path.hasSuffix(".icloud") || path.contains(".icloud/")
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

private extension StorageMode {
    var fileListDisplayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

private extension SearchMatchField {
    var displayName: String {
        switch self {
        case .name:
            "Name"
        case .path:
            "Path"
        case .note:
            "Note"
        case .category:
            "Category"
        case .changeLog:
            "Change log"
        }
    }
}

private extension SearchMatchKind {
    var displayName: String {
        switch self {
        case .exact:
            "Exact match"
        case .fuzzy:
            "Fuzzy match"
        case .pinyinInitials:
            "Pinyin initials"
        }
    }
}

private extension SearchDiagnosticSeverity {
    var displayName: String {
        switch self {
        case .info:
            "Info"
        case .warning:
            "Warning"
        case .error:
            "Error"
        }
    }
}

private extension FileOrigin {
    var fileListDisplayName: String {
        switch self {
        case .imported:
            "Imported"
        case .adopted:
            "Adopted"
        case .external:
            "External"
        }
    }
}
