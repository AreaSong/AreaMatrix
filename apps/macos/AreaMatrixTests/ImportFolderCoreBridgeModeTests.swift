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
        XCTAssertEqual(await searcher.recordedRequests().map(\.request.query), ["kindd:pdf tag:finance"])
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
