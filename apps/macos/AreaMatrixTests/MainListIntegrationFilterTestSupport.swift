@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func integrationFilterFixture(
        repoPath: String,
        currentCategoryFiles: [FileEntrySnapshot]
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .integrationFilterFixture(repoPath: repoPath),
            tree: .integrationFilterFixtureTree(),
            currentCategoryFiles: currentCategoryFiles
        )
    }
}

extension RepoConfigSnapshot {
    static func integrationFilterFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func integrationFilterFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 0,
                    children: [
                        RepositoryTreeNodeSnapshot(
                            slug: "contracts",
                            displayName: "contracts",
                            kind: "Subdir",
                            relativePath: "docs/contracts",
                            fileCount: 2,
                            depth: 2,
                            children: []
                        ),
                        RepositoryTreeNodeSnapshot(
                            slug: "references",
                            displayName: "references",
                            kind: "Subdir",
                            relativePath: "docs/references",
                            fileCount: 1,
                            depth: 2,
                            children: []
                        )
                    ]
                )
            ]
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func integrationFilterDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "当前列表不可用",
            severity: .high,
            suggestedAction: "请重试当前列表。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

struct MainListSearchRequestRecord: Equatable {
    var repoPath: String
    var request: SearchQueryRequestSnapshot
}

struct MainListFallbackRequestRecord: Equatable {
    var repoPath: String
    var request: AiFallbackStatusRequest
}

struct MainListSmartListRequestRecord: Equatable {
    var repoPath: String
    var savedSearchID: Int64
    var limit: Int64
    var offset: Int64
}

actor MainListRecordingSearchQuerying: CoreSearchQuerying {
    enum Result {
        case success(SearchResultPageSnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [MainListSearchRequestRecord] = []
    private var smartListRequests: [MainListSmartListRequestRecord] = []

    init(results: [Result]) {
        self.results = results
    }

    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        requests.append(MainListSearchRequestRecord(repoPath: repoPath, request: request))
        guard !results.isEmpty else {
            return .mainSearchFixture(query: request.query, files: [])
        }

        switch results.removeFirst() {
        case let .success(page):
            return page
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [MainListSearchRequestRecord] {
        requests
    }

    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot {
        smartListRequests.append(MainListSmartListRequestRecord(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        ))
        guard !results.isEmpty else {
            return .mainSearchFixture(query: "", files: [])
        }

        switch results.removeFirst() {
        case let .success(page):
            return page
        case let .failure(error):
            throw error
        }
    }

    func recordedSmartListRequests() -> [MainListSmartListRequestRecord] {
        smartListRequests
    }
}

actor MainListRecordingSemanticSearcher: CoreSemanticSearching {
    private let page: SearchResultPageSnapshot

    init(page: SearchResultPageSnapshot) {
        self.page = page
    }

    func semanticSearch(repoPath _: String,
                        request _: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        page
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        throw CoreError.Internal(message: "semantic-search ai-fallback-core test does not build the semantic index")
    }
}

actor MainListRecordingSemanticFallbackReader: CoreSemanticFallbackStatusReading {
    private let status: AiFallbackStatus
    private var requests: [MainListFallbackRequestRecord] = []

    init(status: AiFallbackStatus) {
        self.status = status
    }

    func semanticFallbackStatus(repoPath: String, request: AiFallbackStatusRequest) async throws -> AiFallbackStatus {
        requests.append(MainListFallbackRequestRecord(repoPath: repoPath, request: request))
        return status
    }

    func recordedRequests() -> [MainListFallbackRequestRecord] {
        requests
    }
}

extension SearchResultPageSnapshot {
    static func mainSearchFixture(
        query: String,
        files: [FileEntrySnapshot],
        indexStatus: SearchIndexStatusSnapshot = .ready
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: Int64(files.count),
            results: files.map {
                SearchFileResultSnapshot(
                    file: $0,
                    score: 1,
                    matches: [
                        SearchMatchSnapshot(
                            fieldDisplayName: "Name",
                            kindDisplayName: "Exact match",
                            snippet: $0.currentName
                        )
                    ],
                    noteSnippet: nil
                )
            },
            diagnostics: [],
            indexStatus: indexStatus
        )
    }

    static func semanticSearchSemanticFallbackFixture() -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: "客户合同",
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .unavailable,
            semanticPage: SemanticSearchResultPageSnapshot(
                query: "客户合同",
                semanticTotalCount: 0,
                normalTotalCount: 0,
                semanticMatches: [],
                normalMatches: [],
                dedupedNormalCount: 0,
                indexStatus: .notReady,
                route: .remote,
                fallbackReason: .semanticIndexNotReady,
                fallbackMessage: "Semantic index is not ready",
                callLogID: 308,
                privacyRuleID: nil,
                lowConfidence: false
            )
        )
    }
}

extension AiFallbackStatus {
    static func semanticSearchSemanticIndexNotReady() -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .semanticSearch,
            kind: .semanticIndexNotReady,
            category: .unavailable,
            title: "Semantic index is not ready",
            message: "Semantic index is not ready yet.",
            retryable: false,
            retryDisabledReason: "Build the semantic index or use normal search.",
            primaryAction: .buildSemanticIndex,
            secondaryAction: .viewCallLog,
            nonAiFallbackAction: .useNormalSearch,
            route: .remote,
            callLogId: 308,
            privacyRuleId: nil,
            retryAfter: nil
        )
    }
}

extension FileEntrySnapshot {
    static func integrationFilterFixture(
        id: Int64,
        path: String,
        category: String,
        currentName: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "integration-filter-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000 - id,
            updatedAt: 1_700_000_000
        )
    }
}

actor MainListRecordingFileLister: CoreFileListing {
    enum Result {
        case success([FileEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [FileFilterSnapshot] = []

    init(results: [Result]) {
        self.results = results
    }

    func listFiles(repoPath _: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        requests.append(filter)
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case let .success(files):
            return files
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [FileFilterSnapshot] {
        requests
    }
}

struct MainListFileDetailRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

actor MainListRecordingFileDetailer: CoreFileDetailing {
    enum Result {
        case success(FileEntrySnapshot)
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [MainListFileDetailRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> FileEntrySnapshot {
        requests.append(MainListFileDetailRequest(repoPath: repoPath, fileID: fileID))
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: "\(fileID)")
        }

        switch results.removeFirst() {
        case let .success(file):
            return file
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [MainListFileDetailRequest] {
        requests
    }
}
