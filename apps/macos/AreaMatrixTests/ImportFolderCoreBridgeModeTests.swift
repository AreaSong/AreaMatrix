@testable import AreaMatrix
import XCTest

final class ImportFolderCoreBridgeModeTests: XCTestCase {
    @MainActor
    func testDefaultCoreBridgeFolderCopyImportKeepsSourceAndCreatesRepoCopy() async throws {
        let repoURL = try makeImportFolderTemporaryDirectory()
        let sourceRoot = try makeImportFolderTemporaryDirectory()
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("invoice.pdf")
        try Data("invoice bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            destination: .autoClassify,
            suggestedCategory: "finance",
            overrideFilename: "folder-invoice.pdf"
        )

        XCTAssertEqual(entry.currentName, "folder-invoice.pdf")
        XCTAssertEqual(entry.category, "finance")
        XCTAssertEqual(entry.storageMode, "Copied")
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }

    @MainActor
    func testDefaultCoreBridgeFolderIndexOnlyImportKeepsSourceWithoutRepoCopy() async throws {
        let repoURL = try makeImportFolderTemporaryDirectory()
        let sourceRoot = try makeImportFolderTemporaryDirectory()
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }

        let sourceURL = sourceRoot.appendingPathComponent("reference.pdf")
        try Data("reference bytes".utf8).write(to: sourceURL)
        let sourceBefore = try Data(contentsOf: sourceURL)
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importBatchFile(request: CoreBatchImportRequest(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            storageMode: .indexOnly,
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "reference-index.pdf",
            duplicateStrategy: .ask
        ))

        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(entry.currentName, "reference-index.pdf")
        XCTAssertEqual(entry.category, "docs")
        XCTAssertEqual(entry.storageMode, "Indexed")
        XCTAssertEqual(entry.sourcePath, sourceURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(entry.path).path))
    }
}

final class QueryErrorPageFeatureTests: XCTestCase {
    func testQueryErrorQueryErrorRouteRendersParseProblemHelpAndActions() {
        let diagnostic = SearchQueryDiagnosticSnapshot.queryErrorUnknownField()
        assertTestMirrorDescription(of: QueryErrorRouteView(
            request: .queryErrorQueryFixture(query: "kindd:pdf tag:finance"),
            diagnostic: diagnostic,
            onApplySuggestion: { _ in },
            onClear: {}
        ).body, contains: [
            "Query could not be parsed",
            "Fix the highlighted part of your query to continue searching.",
            "[kindd]:pdf tag:finance",
            "Unknown field: kindd",
            "Apply suggestion",
            "Clear query",
            "Open query help",
            "query-error-query-error"
        ])
    }

    func testQueryErrorApplySuggestionReplacesOnlyTheFailedToken() {
        let fixed = QuerySuggestionApplier.applying(
            "kind",
            diagnostic: .queryErrorUnknownField(),
            query: "kindd:pdf tag:finance"
        )

        XCTAssertEqual(fixed, "kind:pdf tag:finance")
    }

    func testQueryErrorApplySuggestionUsesDiagnosticRangeBeforeMatchingTokenText() {
        let fixed = QuerySuggestionApplier.applying(
            "kind",
            diagnostic: .queryErrorUnknownField(),
            query: "kindd:pdf note:kindd"
        )

        XCTAssertEqual(fixed, "kind:pdf note:kindd")
    }

    func testQueryErrorQueryHighlighterUsesDiagnosticRangeBeforeMatchingTokenText() {
        let highlighted = QueryTokenHighlighter.highlighted(
            query: "kindd:pdf note:kindd",
            diagnostic: .queryErrorUnknownField()
        )

        XCTAssertEqual(highlighted, "[kindd]:pdf note:kindd")
    }

    @MainActor
    func testQueryErrorCoreDiagnosticRoutesToQueryErrorAndBlocksSmartListSave() async {
        let tree = RepositoryTreeNodeSnapshot.queryErrorFixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let diagnostic = SearchQueryDiagnosticSnapshot.queryErrorUnknownField()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.queryErrorQueryErrorPage(query: "kindd:pdf tag:finance", diagnostic: diagnostic))
        ])
        let model = MainFileListModel(
            opening: .queryErrorOpening(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainListRecordingErrorMapper(mapping: .queryErrorConfigMapping())
        )

        await model.runSearch(
            query: "kindd:pdf tag:finance",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty
        )

        XCTAssertEqual(model.searchPageDestination?.pageID, "query-error")
        XCTAssertFalse(model.canSaveCurrentSearch)
        XCTAssertEqual(model.searchState.page?.diagnostics.first, diagnostic)
        XCTAssertEqual(model.files, [])
        let recordedQueries = await searcher.recordedRequests().map(\.request.query)
        XCTAssertEqual(recordedQueries, ["kindd:pdf tag:finance"])
    }
}

final class SmartListQueryDiagnosticPageFeatureTests: XCTestCase {
    func testSmartListEditQueryDiagnosticBlocksSaveAndRendersQueryErrorSummary() {
        let diagnostic = SearchQueryDiagnosticSnapshot.queryErrorUnknownField()
        var model = SmartListEditorModel(
            mode: .editQuery,
            savedSearch: .smartListFixture(query: "Finance"),
            existingNames: ["finance"],
            resultCountState: .loaded(12)
        )

        model.query = "kindd:pdf tag:finance"
        XCTAssertFalse(model.canSubmit)

        model.applyQueryDiagnosticPage(.queryErrorQueryErrorPage(query: model.query, diagnostic: diagnostic))
        XCTAssertEqual(model.validationMessage, "Fix query syntax before saving changes.")
        XCTAssertFalse(model.canSubmit)

        assertTestMirrorDescription(of: QueryDiagnosticSummary(
            diagnostic: diagnostic,
            query: model.query
        ).body, contains: [
            "Query could not be parsed",
            "[kindd]:pdf tag:finance",
            "Unknown field: kindd",
            "query-error-query-error"
        ])
    }

    func testSmartListEditQueryRequiresFreshDiagnosticBeforeSaveChanges() {
        var model = SmartListEditorModel(
            mode: .editQuery,
            savedSearch: .smartListFixture(query: "Finance"),
            existingNames: ["finance"],
            resultCountState: .loaded(12)
        )

        model.applyQueryDiagnosticPage(.smartListValidQueryPage(query: "Finance", totalCount: 4))
        XCTAssertTrue(model.canSubmit)
        XCTAssertEqual(model.resultCountSummary, "4 files")

        model.query = "kind:pdf"
        XCTAssertFalse(model.canSubmit)

        model.applyQueryDiagnosticPage(.smartListValidQueryPage(query: "kind:pdf", totalCount: 1))
        XCTAssertNil(model.validationMessage)
        XCTAssertTrue(model.canSubmit)
        XCTAssertEqual(model.resultCountSummary, "1 file")
    }

    func testSmartListEditQuerySaveFailureKeepsDraftAndShowsRetry() {
        var model = SmartListEditorModel(
            mode: .editQuery,
            savedSearch: .smartListFixture(query: "Finance"),
            existingNames: ["finance"],
            resultCountState: .loaded(12)
        )
        model.query = "kind:pdf"
        model.applyQueryDiagnosticPage(.smartListValidQueryPage(query: "kind:pdf", totalCount: 4))
        model.failure = .queryErrorConfigMapping()

        XCTAssertTrue(model.showsRetry)
        XCTAssertEqual(model.query, "kind:pdf")
        XCTAssertEqual(model.primaryActionTitle, "Save changes")
    }

    func testSmartListSidebarStatusUsesResultCountAndWarnings() {
        let saved = SavedSearchSnapshot.smartListFixture(query: "Finance")
        let loaded = SmartListSidebarRowStatus.make(
            savedSearch: saved,
            isCurrent: true,
            searchState: .loaded(
                request: .queryErrorQueryFixture(query: "Finance"),
                page: .smartListValidQueryPage(query: "Finance", totalCount: 4)
            )
        )
        let invalid = SmartListSidebarRowStatus.make(
            savedSearch: saved,
            isCurrent: true,
            searchState: .loaded(
                request: .queryErrorQueryFixture(query: "kindd:pdf"),
                page: .queryErrorQueryErrorPage(query: "kindd:pdf", diagnostic: .queryErrorUnknownField())
            )
        )
        let failed = SmartListSidebarRowStatus.make(
            savedSearch: saved,
            isCurrent: true,
            searchState: .failed(request: .queryErrorQueryFixture(query: "Finance"), .queryErrorConfigMapping())
        )

        XCTAssertEqual(loaded.badgeText, "4")
        XCTAssertEqual(loaded.accessibilityValue, "4 results, Pinned")
        XCTAssertEqual(invalid.badgeText, "Invalid query")
        XCTAssertEqual(invalid.warningMessage, "Unknown field `kindd`")
        XCTAssertEqual(failed.badgeText, "--")
        XCTAssertEqual(failed.warningMessage, "Query syntax is invalid.")
    }

    @MainActor
    func testSmartListSearchBannerUsesSavedSmartListContextText() {
        let saved = SavedSearchSnapshot.smartListFixture(query: "Finance")
        let request = SearchQueryRequestSnapshot(savedSearchQuery: saved.query)
        let model = MainFileListModel(
            opening: .queryErrorOpening(
                repoPath: "/tmp/repo",
                tree: .queryErrorFixtureTree().insertingSavedSearch(saved)
            ),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            errorMapper: MainListRecordingErrorMapper(mapping: .queryErrorConfigMapping())
        )
        model.activeSmartListSearch = saved

        XCTAssertEqual(model.searchBannerContextText(for: request), "Smart List: Finance  query=\"Finance\"")
    }

    @MainActor
    func testSmartListEditFiltersDraftReopensEditorAndFeedsUpdateRequest() {
        let saved = SavedSearchSnapshot.smartListFixture(query: "Finance")
        let draftFilters = SearchFilterStateSnapshot(
            category: "docs",
            fileKind: "spreadsheet",
            tags: ["tax"],
            tagMatchMode: .all,
            importedAfter: nil,
            importedBefore: nil,
            modifiedAfter: 1_700_000_000,
            modifiedBefore: nil,
            storageMode: .copied,
            includeDeleted: false
        )
        let route = SmartListManagementRoute(mode: .editQuery, savedSearch: saved, draftFilters: draftFilters)
        var model = SmartListEditorModel(
            mode: route.mode,
            savedSearch: route.savedSearch,
            existingNames: ["finance"],
            resultCountState: .loaded(4),
            draftFilters: route.draftFilters
        )
        model.applyQueryDiagnosticPage(.smartListValidQueryPage(query: model.query, totalCount: 4))

        XCTAssertEqual(route, SmartListManagementRoute(
            mode: .editQuery,
            savedSearch: saved,
            draftFilters: draftFilters
        ))
        XCTAssertEqual(model.updateRequest.query.filter, draftFilters)
        XCTAssertEqual(model.updateRequest.query.filter.tags, ["tax"])
    }

    @MainActor
    func testSmartListSmartListOpenAndRetryUseSmartListsCoreRunSmartList() async {
        let saved = SavedSearchSnapshot.smartListFixture(query: "Finance")
        let mapping = CoreErrorMappingSnapshot.queryErrorConfigMapping()
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let runner = SmartListRecordingSmartListRunner(results: [
            .failure(CoreError.FileNotFound(path: "\(saved.id)")),
            .success(.smartListValidQueryPage(query: "Finance", totalCount: 4))
        ])
        let model = MainFileListModel(
            opening: .queryErrorOpening(repoPath: "/tmp/repo", tree: .queryErrorFixtureTree()),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: runner,
            errorMapper: mapper
        )

        await model.restoreSavedSearch(saved)
        XCTAssertEqual(model.searchState.errorMapping, mapping)
        await model.retrySearch()

        let runRequests = await runner.recordedRunRequests()
        let searchRequests = await runner.recordedSearchRequests()
        let mappedErrors = await mapper.recordedErrors()
        XCTAssertEqual(runRequests, [
            SmartListSmartListRunRequest(repoPath: "/tmp/repo", savedSearchID: saved.id, limit: 50, offset: 0),
            SmartListSmartListRunRequest(repoPath: "/tmp/repo", savedSearchID: saved.id, limit: 50, offset: 0)
        ])
        XCTAssertEqual(searchRequests, [])
        XCTAssertEqual(mappedErrors, [CoreError.FileNotFound(path: "\(saved.id)")])
        XCTAssertEqual(model.searchState.page?.totalCount, 4)
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: saved.id, name: saved.name))
    }
}

private extension RepositoryOpeningResult {
    static func queryErrorOpening(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .queryErrorConfig(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepoConfigSnapshot {
    static func queryErrorConfig(repoPath: String) -> RepoConfigSnapshot {
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
    static func queryErrorFixtureTree() -> RepositoryTreeNodeSnapshot {
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

private extension SearchQueryDiagnosticSnapshot {
    static func queryErrorUnknownField() -> SearchQueryDiagnosticSnapshot {
        SearchQueryDiagnosticSnapshot(
            kindDisplayName: "Unknown field",
            severityDisplayName: "Error",
            message: "Unknown field `kindd`",
            token: "kindd",
            start: 0,
            end: 5,
            suggestion: "kind"
        )
    }
}

private extension SavedSearchSnapshot {
    static func smartListFixture(query: String) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: 77,
            name: "Finance",
            query: SavedSearchQuerySnapshot(request: .queryErrorQueryFixture(query: query)),
            icon: "magnifyingglass",
            color: nil,
            pinned: true,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension SearchQueryRequestSnapshot {
    static func queryErrorQueryFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .current,
            currentPath: "docs/contracts",
            category: "docs",
            filters: .empty,
            sort: .relevance,
            limit: 50,
            offset: 0
        )
    }
}

private extension SearchResultPageSnapshot {
    static func queryErrorQueryErrorPage(
        query: String,
        diagnostic: SearchQueryDiagnosticSnapshot
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: 0,
            results: [],
            diagnostics: [diagnostic],
            indexStatus: .ready
        )
    }

    static func smartListValidQueryPage(query: String, totalCount: Int64) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: query,
            totalCount: totalCount,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func queryErrorConfigMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "Query syntax is invalid.",
            severity: .medium,
            suggestedAction: "Fix the highlighted query token.",
            recoverability: .userActionRequired,
            rawContext: "query-error"
        )
    }
}
