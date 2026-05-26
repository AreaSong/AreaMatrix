@testable import AreaMatrix
import XCTest

final class MainListIntegrationFilterTests: XCTestCase {
    func testCurrentListFilterMatchesLoadedFileNamesOnly() {
        let files = [
            FileEntrySnapshot.integrationFilterFixture(
                id: 1,
                path: "docs/contracts/customer.pdf",
                category: "docs",
                currentName: "customer.pdf"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 2,
                path: "docs/references/research.md",
                category: "docs",
                currentName: "research.md"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 3,
                path: "docs/contracts/budget.xlsx",
                category: "docs",
                currentName: "budget.xlsx"
            )
        ]
        let row = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
            .sidebarRow(id: "docs/contracts")

        guard let row else {
            return XCTFail("expected docs/contracts sidebar row")
        }

        let result = MainListVisibleFileFiltering.visibleFiles(
            from: files,
            sidebarRow: row,
            filterText: "customer"
        )

        XCTAssertEqual(result.map(\.id), [1])
    }

    func testCurrentListFilterDoesNotSearchAcrossCategoryOrPathFields() {
        let files = [
            FileEntrySnapshot.integrationFilterFixture(
                id: 1,
                path: "docs/contracts/customer.pdf",
                category: "docs",
                currentName: "customer.pdf"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 2,
                path: "docs/references/research.md",
                category: "docs",
                currentName: "research.md"
            )
        ]
        let row = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
            .sidebarRow(id: "docs")

        guard let row else {
            return XCTFail("expected docs sidebar row")
        }

        let result = MainListVisibleFileFiltering.visibleFiles(
            from: files,
            sidebarRow: row,
            filterText: "contracts"
        )

        XCTAssertEqual(result, [])
    }

    @MainActor
    func testMainListSearchQueriesAllRepoThroughC201SearchFiles() async {
        let resultFile = FileEntrySnapshot.integrationFilterFixture(
            id: 201,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.mainSearchFixture(query: "合同", files: [resultFile]))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainListRecordingErrorMapper(mapping: .integrationFilterDbFixture(rawContext: "unused"))
        )

        await model.runSearch(
            query: " 合同 ",
            scope: .all,
            sort: .newestImported,
            sidebarRow: RepositoryTreeNodeSnapshot.integrationFilterFixtureTree().sidebarRows[0],
            filters: .empty
        )
        let requests = await searcher.recordedRequests()

        XCTAssertEqual(requests.map(\.request), [
            SearchQueryRequestSnapshot(
                query: "合同",
                scope: .all,
                currentPath: nil,
                category: nil,
                filters: .empty,
                sort: .newestImported,
                limit: 50,
                offset: 0
            )
        ])
        XCTAssertEqual(model.files, [resultFile])
        XCTAssertEqual(model.searchState.page?.totalCount, 1)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMainListSearchCurrentScopeCarriesSidebarContext() async {
        let tree = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.mainSearchFixture(query: "customer", files: []))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainListRecordingErrorMapper(mapping: .integrationFilterDbFixture(rawContext: "unused"))
        )

        await model.runSearch(
            query: "customer",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty
        )
        let requests = await searcher.recordedRequests()

        XCTAssertEqual(requests.map(\.request.currentPath), ["docs/contracts"])
        XCTAssertEqual(requests.map(\.request.category), ["docs"])
        XCTAssertEqual(requests.map(\.request.scope), [.current])
        XCTAssertEqual(requests.map(\.request.sort), [.relevance])
    }

    @MainActor
    func testMainListSearchFailureMapsErrorAndPreservesRequestForRetry() async {
        let mapping = CoreErrorMappingSnapshot.integrationFilterDbFixture(rawContext: "search db locked")
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let searcher = MainListRecordingSearchQuerying(results: [
            .failure(CoreError.Db(message: "search db locked"))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: mapper
        )

        await model.runSearch(
            query: "合同",
            scope: .all,
            sort: .newestImported,
            sidebarRow: RepositoryTreeNodeSnapshot.integrationFilterFixtureTree().sidebarRows[0],
            filters: .empty
        )
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.searchState.errorMapping, mapping)
        XCTAssertEqual(model.searchState.request?.query, "合同")
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "search db locked")])
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testMainListSearchClearExitsSearchMode() async {
        let resultFile = FileEntrySnapshot.integrationFilterFixture(
            id: 202,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.mainSearchFixture(query: "合同", files: [resultFile], indexStatus: .unavailable))
        ])
        let model = MainFileListModel(
            opening: .integrationFilterFixture(repoPath: "/tmp/repo", currentCategoryFiles: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainListRecordingErrorMapper(mapping: .integrationFilterDbFixture(rawContext: "unused"))
        )

        await model.runSearch(
            query: "合同",
            scope: .all,
            sort: .newestImported,
            sidebarRow: RepositoryTreeNodeSnapshot.integrationFilterFixtureTree().sidebarRows[0],
            filters: .empty
        )
        model.clearSearch()

        XCTAssertEqual(model.searchState, .idle)
        XCTAssertNil(model.errorMapping)
        XCTAssertFalse(model.isLoading)
    }
}

private extension RepositoryOpeningResult {
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

private extension RepoConfigSnapshot {
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

private extension RepositoryTreeNodeSnapshot {
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

private extension CoreErrorMappingSnapshot {
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

private extension SearchResultPageSnapshot {
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
}

private extension FileEntrySnapshot {
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

actor MainListRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}
