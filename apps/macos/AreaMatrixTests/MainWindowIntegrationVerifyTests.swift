@testable import AreaMatrix
import XCTest

final class MainWindowIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testMainWindowIntegrationRoutesEmptyAndPopulatedRepositoriesToMainPages() async {
        let emptyOpening = RepositoryOpeningResult.task34Fixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let empty = await openConfiguredRepository(opening: emptyOpening)

        XCTAssertEqual(empty.route, .mainEmpty(emptyOpening))
        XCTAssertEqual(empty.openedRepoPaths, ["/tmp/empty-repo"])
        XCTAssertEqual(empty.savedRepoPaths, [])
        XCTAssertEqual(empty.successfulRepoOpenPaths, ["/tmp/empty-repo"])

        let populatedOpening = RepositoryOpeningResult.task34Fixture(repoPath: "/tmp/list-repo", fileCount: 4)
        let populated = await openConfiguredRepository(opening: populatedOpening)

        XCTAssertEqual(populated.route, .mainList(populatedOpening))
        XCTAssertEqual(populated.openedRepoPaths, ["/tmp/list-repo"])
        XCTAssertEqual(populated.successfulRepoOpenPaths, ["/tmp/list-repo"])
    }

    @MainActor
    func testMainWindowIntegrationKeepsRetryableDbFailureInMainLoading() async {
        let mapping = CoreErrorMappingSnapshot.task34Mapping(
            kind: .db,
            severity: .medium,
            recoverability: .retryable,
            rawContext: "database is locked"
        )
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreError.Db(message: "database is locked")))
        let writer = ShellRecordingSettingsWriter()
        let model = task34Model(
            repoPath: "/tmp/repo",
            writer: writer,
            opener: opener,
            treeLister: MainLoadingRecordingTreeLister(result: .success(.mainLoadingTreeFixture())),
            errorMapper: MainWindowIntegrationErrorMapper(mapping: mapping)
        )

        await model.bootstrapIfNeeded()
        let openedRepoPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .mainLoading(state) = model.route else {
            return XCTFail("expected S1-10 main-loading, got \(model.route)")
        }

        XCTAssertEqual(openedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")
    }

    @MainActor
    func testMainWindowIntegrationRoutesCriticalRepoFailureToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.task34Mapping(
            kind: .permissionDenied,
            rawContext: "/tmp/repo"
        )
        let mapper = MainWindowIntegrationErrorMapper(mapping: mapping)
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let writer = ShellRecordingSettingsWriter()
        let model = task34Model(
            repoPath: "/tmp/repo",
            writer: writer,
            opener: opener,
            errorMapper: mapper
        )

        await model.bootstrapIfNeeded()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertTrue(mappedErrors.contains(CoreError.PermissionDenied(path: "/tmp/repo")))
        XCTAssertEqual(RepositoryErrorPresentation.mainRepo(mapping: mapping).primaryAction, .reconnectFolder)
    }

    func testMainWindowIntegrationUsesRealCoreBridgeBoundariesForBoundCapabilities() {
        let requiredBoundaries: Set<CoreBridgeBoundary> = [
            .validateInitializedRepoPath,
            .recoverOnStartup,
            .getLatestScanSession,
            .resumeScanSession,
            .listFiles,
            .searchFiles,
            .listFilterFacets,
            .runSmartList,
            .getFile,
            .previewBatchDelete,
            .batchDeleteToTrash,
            .listTreeJSON,
            .syncExternalChanges,
            .mapCoreError
        ]

        XCTAssertEqual(CoreBridge().state, .generatedBindings)
        XCTAssertTrue(requiredBoundaries.isSubset(of: Set(CoreBridgeBoundary.allCases)))
    }

    @MainActor
    func testS201PageIntegrationWiresSearchFiltersResultDetailAndClear() async {
        let tree = RepositoryTreeNodeSnapshot.task98FixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let resultFile = FileEntrySnapshot.task98Fixture(
            id: 298,
            path: "docs/contracts/customer.pdf",
            category: "docs",
            currentName: "customer.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.task98SearchPage(query: "合同", files: [resultFile]))
        ])
        let facetLoader = MainListRecordingSearchFiltering(results: [
            .success(.task98SearchFacets(query: "合同", totalCount: 1, activeFilters: 1))
        ])
        let detailer = MainListRecordingFileDetailer(results: [.success(resultFile)])
        let filters = SearchFilterStateSnapshot.task98ContractFilters()
        let model = MainFileListModel(
            opening: .task98Fixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: detailer,
            searchQuerying: searcher,
            searchFiltering: facetLoader,
            errorMapper: MainWindowIntegrationErrorMapper(mapping: .task34Mapping(kind: .db))
        )

        await model.runSearch(query: " 合同 ", scope: .current, sort: .relevance, sidebarRow: row, filters: filters)
        await model.loadSearchFacets(query: "合同", scope: .current, sidebarRow: row, filters: filters)
        await model.selectFiles([resultFile.id])
        let searchRequests = await searcher.recordedRequests()
        let facetRequests = await facetLoader.recordedRequests()
        let detailRequests = await detailer.recordedRequests()
        model.clearSearch()

        XCTAssertEqual(searchRequests.map(\.request.filters), [filters])
        XCTAssertEqual(facetRequests.map(\.request.filters), [filters])
        XCTAssertEqual(detailRequests.map(\.fileID), [resultFile.id])
        XCTAssertEqual(model.searchState, .idle)
        XCTAssertEqual(model.searchFacetsState, .idle)
        XCTAssertEqual(model.selection, .none)
    }

    @MainActor
    func testS201PageIntegrationRoutesEmptyQueryErrorIndexingSaveAndCommandEntrances() async {
        let tree = RepositoryTreeNodeSnapshot.task98FixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let diagnostic = SearchQueryDiagnosticSnapshot(
            severityDisplayName: "Error",
            message: "Unknown field: owner",
            suggestion: "Use category:"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.task98SearchPage(query: "missing", files: [])),
            .success(.task98SearchPage(query: "owner:me", diagnostics: [diagnostic])),
            .success(.task98SearchPage(query: "")),
            .success(.task98SearchPage(query: "合同", files: [], indexStatus: .unavailable))
        ])
        let model = MainFileListModel(
            opening: .task98Fixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainWindowIntegrationErrorMapper(mapping: .task34Mapping(kind: .db))
        )

        await model.runSearch(query: "missing", scope: .current, sort: .newestImported, sidebarRow: row, filters: .empty)
        XCTAssertEqual(model.searchPageDestination?.pageID, "S2-04")
        XCTAssertEqual(model.files, [])
        let firstRecordedQuery = await searcher.recordedRequests().first?.request.query
        XCTAssertEqual(firstRecordedQuery, "missing")
        model.openSavedSearchSheet()
        XCTAssertEqual(model.pendingSearchDestination?.pageID, "S2-03")
        model.clearPendingSearchDestination()

        await model.runSearch(query: "owner:me", scope: .current, sort: .relevance, sidebarRow: row, filters: .empty)
        XCTAssertEqual(model.searchPageDestination?.pageID, "S2-05")
        XCTAssertFalse(model.canSaveCurrentSearch)
        XCTAssertNil(model.searchState.errorMapping)

        await model.runSearch(query: "", scope: .current, sort: .newestModified, sidebarRow: row, filters: .task98ContractFilters())
        XCTAssertTrue(model.canSaveCurrentSearch)

        await model.runSearch(query: "合同", scope: .current, sort: .newestImported, sidebarRow: row, filters: .empty)
        model.openIndexingStatus()
        XCTAssertEqual(model.pendingSearchDestination?.pageID, "S2-01-indexing-status")

        model.enterSearch(context: .commandFind)
        XCTAssertEqual(model.lastSearchExitContext, .toolbar)
        model.openCommandPaletteForSearch()
        XCTAssertEqual(model.pendingSearchDestination?.pageID, "S2-15")
        XCTAssertEqual(model.lastSearchExitContext, .toolbar)
    }

    @MainActor
    func testS201PageIntegrationSmartListClearPreservesSavedQueryContext() async {
        let tree = RepositoryTreeNodeSnapshot.task98FixtureTree()
        let resultFile = FileEntrySnapshot.task98Fixture(
            id: 299,
            path: "docs/contracts/smart.pdf",
            category: "docs",
            currentName: "smart.pdf"
        )
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.task98SearchPage(query: "合同", files: [resultFile]))
        ])
        let model = MainFileListModel(
            opening: .task98Fixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainWindowIntegrationErrorMapper(mapping: .task34Mapping(kind: .db))
        )
        let smartListContext = MainSearchEntryContext.smartList(id: 42, name: "最近合同")

        model.enterSearch(context: smartListContext)
        await model.runSearch(
            query: "合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: tree.sidebarRows[0],
            filters: .task98ContractFilters()
        )
        model.clearSearch()

        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: 42, name: "最近合同"))
        XCTAssertEqual(model.searchState, .idle)
        XCTAssertNil(model.pendingSearchDestination)
    }

    @MainActor
    private func openConfiguredRepository(
        opening: RepositoryOpeningResult
    ) async -> MainWindowIntegrationOpenResult {
        let opener = ShellRecordingRepositoryOpener(result: .success(opening))
        let writer = ShellRecordingSettingsWriter()
        let model = task34Model(
            repoPath: opening.config.repoPath,
            writer: writer,
            opener: opener
        )

        await model.bootstrapIfNeeded()
        return await MainWindowIntegrationOpenResult(
            route: model.route,
            openedRepoPaths: opener.requestedConfiguredRepoPaths(),
            savedRepoPaths: writer.savedRepoPaths,
            successfulRepoOpenPaths: writer.successfulRepoOpens.map(\.repoPath)
        )
    }

    @MainActor
    private func task34Model(
        repoPath: String,
        writer: ShellRecordingSettingsWriter,
        opener: ShellRecordingRepositoryOpener,
        treeLister: (any CoreRepositoryTreeListing)? = nil,
        errorMapper: any CoreErrorMapping = MainWindowIntegrationErrorMapper(mapping: .task34Mapping(kind: .db))
    ) -> OnboardingModel {
        OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: repoPath),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: ShellStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
    }
}

private extension RepositoryOpeningResult {
    static func task98Fixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func task98FixtureTree() -> RepositoryTreeNodeSnapshot {
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

private extension SearchFilterStateSnapshot {
    static func task98ContractFilters() -> SearchFilterStateSnapshot {
        SearchFilterStateSnapshot(
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
}

private extension SearchResultPageSnapshot {
    static func task98SearchPage(
        query: String,
        files: [FileEntrySnapshot] = [],
        diagnostics: [SearchQueryDiagnosticSnapshot] = [],
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
            diagnostics: diagnostics,
            indexStatus: indexStatus
        )
    }
}

private extension SearchFacetsSnapshot {
    static func task98SearchFacets(
        query: String,
        totalCount: Int64,
        activeFilters: Int64
    ) -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: query,
            totalCount: totalCount,
            categories: [],
            fileKinds: [],
            tags: [],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: activeFilters
        )
    }
}

private extension FileEntrySnapshot {
    static func task98Fixture(
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
            hashSha256: "task-98-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000 - id,
            updatedAt: 1_700_000_000
        )
    }
}

private struct MainWindowIntegrationOpenResult {
    var route: OnboardingModel.Route
    var openedRepoPaths: [String]
    var savedRepoPaths: [String]
    var successfulRepoOpenPaths: [String]
}

private actor MainWindowIntegrationErrorMapper: CoreErrorMapping {
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

private extension RepositoryOpeningResult {
    static func task34Fixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func task34Mapping(
        kind: CoreErrorKindSnapshot,
        severity: CoreErrorSeveritySnapshot = .high,
        recoverability: CoreErrorRecoverabilitySnapshot = .userActionRequired,
        rawContext: String = "task-34"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: severity,
            suggestedAction: "mapped action",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}
