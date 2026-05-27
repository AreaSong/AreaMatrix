@testable import AreaMatrix
import XCTest

final class ImportFolderCoreBridgeModeTests: XCTestCase {
    @MainActor
    func testDefaultCoreBridgeFolderCopyImportKeepsSourceAndCreatesRepoCopy() async throws {
        let repoURL = try makeImportFolderTemporaryDirectory()
        let sourceRoot = try makeImportFolderTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

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
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

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
    func testS205QueryErrorRouteRendersParseProblemHelpAndActions() {
        let diagnostic = SearchQueryDiagnosticSnapshot.s205UnknownField()
        let body = s205RouteMirrorDescription(of: QueryErrorRouteView(
            request: .s205QueryFixture(query: "kindd:pdf tag:finance"),
            diagnostic: diagnostic,
            onApplySuggestion: { _ in },
            onClear: {}
        ).body)

        XCTAssertTrue(body.contains("Query could not be parsed"))
        XCTAssertTrue(body.contains("Fix the highlighted part of your query to continue searching."))
        XCTAssertTrue(body.contains("[kindd]:pdf tag:finance"))
        XCTAssertTrue(body.contains("Unknown field: kindd"))
        XCTAssertTrue(body.contains("Apply suggestion"))
        XCTAssertTrue(body.contains("Clear query"))
        XCTAssertTrue(body.contains("Open query help"))
        XCTAssertTrue(body.contains("S2-05-query-error"))
    }

    func testS205ApplySuggestionReplacesOnlyTheFailedToken() {
        let fixed = QuerySuggestionApplier.applying(
            "kind",
            diagnostic: .s205UnknownField(),
            query: "kindd:pdf tag:finance"
        )

        XCTAssertEqual(fixed, "kind:pdf tag:finance")
    }

    func testS205ApplySuggestionUsesDiagnosticRangeBeforeMatchingTokenText() {
        let fixed = QuerySuggestionApplier.applying(
            "kind",
            diagnostic: .s205UnknownField(),
            query: "kindd:pdf note:kindd"
        )

        XCTAssertEqual(fixed, "kind:pdf note:kindd")
    }

    func testS205QueryHighlighterUsesDiagnosticRangeBeforeMatchingTokenText() {
        let highlighted = QueryTokenHighlighter.highlighted(
            query: "kindd:pdf note:kindd",
            diagnostic: .s205UnknownField()
        )

        XCTAssertEqual(highlighted, "[kindd]:pdf note:kindd")
    }

    @MainActor
    func testS205CoreDiagnosticRoutesToQueryErrorAndBlocksSmartListSave() async {
        let tree = RepositoryTreeNodeSnapshot.s205FixtureTree()
        guard let row = tree.sidebarRow(id: "docs/contracts") else {
            return XCTFail("expected docs/contracts sidebar row")
        }
        let diagnostic = SearchQueryDiagnosticSnapshot.s205UnknownField()
        let searcher = MainListRecordingSearchQuerying(results: [
            .success(.s205QueryErrorPage(query: "kindd:pdf tag:finance", diagnostic: diagnostic))
        ])
        let model = MainFileListModel(
            opening: .s205Opening(repoPath: "/tmp/repo", tree: tree),
            fileLister: MainListRecordingFileLister(results: [.success([])]),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            errorMapper: MainListRecordingErrorMapper(mapping: .s205ConfigMapping())
        )

        await model.runSearch(
            query: "kindd:pdf tag:finance",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: .empty
        )

        XCTAssertEqual(model.searchPageDestination?.pageID, "S2-05")
        XCTAssertFalse(model.canSaveCurrentSearch)
        XCTAssertEqual(model.searchState.page?.diagnostics.first, diagnostic)
        XCTAssertEqual(model.files, [])
        let recordedQueries = await searcher.recordedRequests().map(\.request.query)
        XCTAssertEqual(recordedQueries, ["kindd:pdf tag:finance"])
    }
}

final class SmartListQueryDiagnosticPageFeatureTests: XCTestCase {
    func testS206EditQueryDiagnosticBlocksSaveAndRendersS205Summary() {
        let diagnostic = SearchQueryDiagnosticSnapshot.s205UnknownField()
        var model = SmartListEditorModel(
            mode: .editQuery,
            savedSearch: .s206Fixture(query: "Finance"),
            existingNames: ["finance"],
            resultCountState: .loaded(12)
        )

        model.query = "kindd:pdf tag:finance"
        XCTAssertFalse(model.canSubmit)

        model.applyQueryDiagnosticPage(.s205QueryErrorPage(query: model.query, diagnostic: diagnostic))
        XCTAssertEqual(model.validationMessage, "Fix query syntax before saving changes.")
        XCTAssertFalse(model.canSubmit)

        let body = s205RouteMirrorDescription(of: QueryDiagnosticSummary(
            diagnostic: diagnostic,
            query: model.query
        ).body)
        XCTAssertTrue(body.contains("Query could not be parsed"))
        XCTAssertTrue(body.contains("[kindd]:pdf tag:finance"))
        XCTAssertTrue(body.contains("Unknown field: kindd"))
        XCTAssertTrue(body.contains("S2-05-query-error"))
    }

    func testS206EditQueryRequiresFreshDiagnosticBeforeSaveChanges() {
        var model = SmartListEditorModel(
            mode: .editQuery,
            savedSearch: .s206Fixture(query: "Finance"),
            existingNames: ["finance"],
            resultCountState: .loaded(12)
        )

        model.applyQueryDiagnosticPage(.s206ValidQueryPage(query: "Finance", totalCount: 4))
        XCTAssertTrue(model.canSubmit)
        XCTAssertEqual(model.resultCountSummary, "4 files")

        model.query = "kind:pdf"
        XCTAssertFalse(model.canSubmit)

        model.applyQueryDiagnosticPage(.s206ValidQueryPage(query: "kind:pdf", totalCount: 1))
        XCTAssertNil(model.validationMessage)
        XCTAssertTrue(model.canSubmit)
        XCTAssertEqual(model.resultCountSummary, "1 file")
    }

    func testS206EditQuerySaveFailureKeepsDraftAndShowsRetry() {
        var model = SmartListEditorModel(
            mode: .editQuery,
            savedSearch: .s206Fixture(query: "Finance"),
            existingNames: ["finance"],
            resultCountState: .loaded(12)
        )
        model.query = "kind:pdf"
        model.applyQueryDiagnosticPage(.s206ValidQueryPage(query: "kind:pdf", totalCount: 4))
        model.failure = .s205ConfigMapping()

        XCTAssertTrue(model.showsRetry)
        XCTAssertEqual(model.query, "kind:pdf")
        XCTAssertEqual(model.primaryActionTitle, "Save changes")
    }

    func testS206SidebarStatusUsesResultCountAndWarnings() {
        let saved = SavedSearchSnapshot.s206Fixture(query: "Finance")
        let loaded = SmartListSidebarRowStatus.make(
            savedSearch: saved,
            isCurrent: true,
            searchState: .loaded(
                request: .s205QueryFixture(query: "Finance"),
                page: .s206ValidQueryPage(query: "Finance", totalCount: 4)
            )
        )
        let invalid = SmartListSidebarRowStatus.make(
            savedSearch: saved,
            isCurrent: true,
            searchState: .loaded(
                request: .s205QueryFixture(query: "kindd:pdf"),
                page: .s205QueryErrorPage(query: "kindd:pdf", diagnostic: .s205UnknownField())
            )
        )
        let failed = SmartListSidebarRowStatus.make(
            savedSearch: saved,
            isCurrent: true,
            searchState: .failed(request: .s205QueryFixture(query: "Finance"), .s205ConfigMapping())
        )

        XCTAssertEqual(loaded.badgeText, "4")
        XCTAssertEqual(loaded.accessibilityValue, "4 results, Pinned")
        XCTAssertEqual(invalid.badgeText, "Invalid query")
        XCTAssertEqual(invalid.warningMessage, "Unknown field `kindd`")
        XCTAssertEqual(failed.badgeText, "--")
        XCTAssertEqual(failed.warningMessage, "Query syntax is invalid.")
    }

    @MainActor
    func testS206SearchBannerUsesSavedSmartListContextText() {
        let saved = SavedSearchSnapshot.s206Fixture(query: "Finance")
        let request = SearchQueryRequestSnapshot(savedSearchQuery: saved.query)
        let model = MainFileListModel(
            opening: .s205Opening(repoPath: "/tmp/repo", tree: .s205FixtureTree().insertingSavedSearch(saved)),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: MainListRecordingSearchQuerying(results: []),
            errorMapper: MainListRecordingErrorMapper(mapping: .s205ConfigMapping())
        )
        model.activeSmartListSearch = saved

        XCTAssertEqual(model.searchBannerContextText(for: request), "Smart List: Finance  query=\"Finance\"")
    }

    @MainActor
    func testS206EditFiltersDraftReopensEditorAndFeedsUpdateRequest() {
        let saved = SavedSearchSnapshot.s206Fixture(query: "Finance")
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
        model.applyQueryDiagnosticPage(.s206ValidQueryPage(query: model.query, totalCount: 4))

        XCTAssertEqual(route, SmartListManagementRoute(
            mode: .editQuery,
            savedSearch: saved,
            draftFilters: draftFilters
        ))
        XCTAssertEqual(model.updateRequest.query.filter, draftFilters)
        XCTAssertEqual(model.updateRequest.query.filter.tags, ["tax"])
    }

    @MainActor
    func testS206SmartListOpenAndRetryUseC204RunSmartList() async {
        let saved = SavedSearchSnapshot.s206Fixture(query: "Finance")
        let mapping = CoreErrorMappingSnapshot.s205ConfigMapping()
        let mapper = MainListRecordingErrorMapper(mapping: mapping)
        let runner = S206RecordingSmartListRunner(results: [
            .failure(CoreError.FileNotFound(path: "\(saved.id)")),
            .success(.s206ValidQueryPage(query: "Finance", totalCount: 4))
        ])
        let model = MainFileListModel(
            opening: .s205Opening(repoPath: "/tmp/repo", tree: .s205FixtureTree()),
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
            S206SmartListRunRequest(repoPath: "/tmp/repo", savedSearchID: saved.id, limit: 50, offset: 0),
            S206SmartListRunRequest(repoPath: "/tmp/repo", savedSearchID: saved.id, limit: 50, offset: 0)
        ])
        XCTAssertEqual(searchRequests, [])
        XCTAssertEqual(mappedErrors, [CoreError.FileNotFound(path: "\(saved.id)")])
        XCTAssertEqual(model.searchState.page?.totalCount, 4)
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: saved.id, name: saved.name))
    }
}

private extension RepositoryOpeningResult {
    static func s205Opening(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .s205Config(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepoConfigSnapshot {
    static func s205Config(repoPath: String) -> RepoConfigSnapshot {
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
    static func s205FixtureTree() -> RepositoryTreeNodeSnapshot {
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
    static func s205UnknownField() -> SearchQueryDiagnosticSnapshot {
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
    static func s206Fixture(query: String) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: 77,
            name: "Finance",
            query: SavedSearchQuerySnapshot(request: .s205QueryFixture(query: query)),
            icon: "magnifyingglass",
            color: nil,
            pinned: true,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension SearchQueryRequestSnapshot {
    static func s205QueryFixture(query: String) -> SearchQueryRequestSnapshot {
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
    static func s205QueryErrorPage(
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

    static func s206ValidQueryPage(query: String, totalCount: Int64) -> SearchResultPageSnapshot {
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
    static func s205ConfigMapping() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "Query syntax is invalid.",
            severity: .medium,
            suggestedAction: "Fix the highlighted query token.",
            recoverability: .userActionRequired,
            rawContext: "S2-05"
        )
    }
}

private func s205RouteMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    s205RouteAppendMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func s205RouteAppendMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        s205RouteAppendMirrorDescription(of: child.value, to: &lines)
    }
}
