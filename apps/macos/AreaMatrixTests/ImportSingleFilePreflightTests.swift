// swiftlint:disable file_length
@testable import AreaMatrix
import Foundation
import XCTest

final class ImportSingleFilePreflightTests: XCTestCase {
    @MainActor
    func testSemanticSearchSemanticModeRoutesToSemanticSearchCoreSemanticSearchAndKeepsNormalFallbackGroup() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let semanticFile = FileEntrySnapshot.semanticSearchFixture(id: 670, name: "invoice_0426.pdf")
        let normalFile = FileEntrySnapshot.semanticSearchFixture(id: 671, name: "invoice_notes.txt")
        let semantic = SemanticSearchSemanticSearcher(page: .semanticSearchPage(semanticFile: semanticFile, normalFile: normalFile))
        let normal = SemanticSearchNormalSearcher()
        let model = MainFileListModel(
            opening: .semanticSearchFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: SemanticSearchLister(),
            fileDetailer: SemanticSearchDetailer(file: semanticFile),
            searchQuerying: normal,
            semanticSearching: semantic,
            errorMapper: SemanticSearchErrorMapper()
        )

        await model.runSearch(
            query: " 上个月的发票 ",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: SearchFilterStateSnapshot.empty,
            mode: SearchModeSnapshot.semantic
        )
        let semanticRequests = await semantic.semanticRequests()
        let normalRequests = await normal.requests()

        XCTAssertEqual(semanticRequests.first?.query, "上个月的发票")
        XCTAssertEqual(semanticRequests.first?.mode, SearchModeSnapshot.semantic)
        XCTAssertEqual(normalRequests, [])
        XCTAssertEqual(model.searchState.page?.semanticPage?.semanticTotalCount, 1)
        XCTAssertEqual(model.searchState.page?.semanticPage?.normalTotalCount, 1)
        XCTAssertEqual(model.files.map(\.id), [semanticFile.id, normalFile.id])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.semanticSearch))
    }

    @MainActor
    func testSemanticSearchBuildSemanticIndexRunsOnlyAfterExplicitUserAction() async {
        let tree = RepositoryTreeNodeSnapshot.semanticSearchTree()
        guard let row = tree.sidebarRow(id: "finance/invoices") else {
            return XCTFail("expected finance invoices sidebar row")
        }
        let semantic = SemanticSearchSemanticSearcher(page: .semanticSearchIndexNotReadyPage())
        let model = MainFileListModel(
            opening: .semanticSearchFixture(repoPath: "/tmp/repo", tree: tree),
            fileLister: SemanticSearchLister(),
            fileDetailer: SemanticSearchDetailer(file: .semanticSearchFixture(id: 672)),
            searchQuerying: SemanticSearchNormalSearcher(),
            semanticSearching: semantic,
            errorMapper: SemanticSearchErrorMapper()
        )

        await model.runSearch(
            query: "客户合同",
            scope: .current,
            sort: .relevance,
            sidebarRow: row,
            filters: SearchFilterStateSnapshot.empty,
            mode: SearchModeSnapshot.semantic
        )
        let initialIndexRequests = await semantic.indexRequests()
        XCTAssertEqual(initialIndexRequests, [])

        await model.buildSemanticIndexForCurrentSearch()
        let indexRequests = await semantic.indexRequests()

        XCTAssertEqual(indexRequests.map(\.query), ["客户合同"])
        XCTAssertEqual(indexRequests.map(\.mode), [SearchModeSnapshot.semantic])
        XCTAssertFalse(model.semanticIndexBuildState.isBuilding)
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.buildEmbeddingIndex))
    }

    func testCorePreflightComputesHashAndUsesCoreListFilesWithoutDuplicate() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("same bytes".utf8).write(to: sourceURL)
        let fileLoader = ImportSingleFileStaticFileLoader(files: [
            .importSingleFileFixture(currentName: "other.pdf", category: "docs", hashSha256: "other-hash")
        ])

        let result = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))
        let loadRequests = await fileLoader.recordedRequests()

        XCTAssertEqual(result.sourceSizeBytes, 10)
        XCTAssertEqual(result.hashSha256, "58100dc8fc06562ce3e578231dc948e083520ee49c4b4ee5a5a28bb4b4003feb")
        XCTAssertEqual(result.targetRelativePath, "docs/source.pdf")
        XCTAssertEqual(result.conflict, .none)
        XCTAssertNil(result.keepBothTargetRelativePath)
        XCTAssertNil(result.importBlockingReason())
        XCTAssertEqual(loadRequests, [ImportSingleFileFileLoadRequest(repoPath: "/tmp/repo", categories: [nil])])
    }

    func testCorePreflightDetectsDuplicateHashAndComputesKeepBothPreviewFromCoreListFiles() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("new".utf8).write(to: sourceURL)
        let duplicateHash = "11507a0e2f5e69d5dfa40a62a1bd7b6ee57e6bcd85c67c9b8431b36fff21c437"
        let fileLoader = ImportSingleFileStaticFileLoader(files: [
            .importSingleFileFixture(currentName: "existing.pdf", category: "docs", hashSha256: duplicateHash),
            .importSingleFileFixture(currentName: "source.pdf", category: "docs", hashSha256: "name-only")
        ])

        let actual = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))

        XCTAssertEqual(actual.sourceSizeBytes, 3)
        XCTAssertNotNil(actual.sourceModifiedAt)
        XCTAssertEqual(actual.hashSha256, duplicateHash)
        XCTAssertEqual(actual.targetRelativePath, "docs/source.pdf")
        XCTAssertEqual(actual.conflict, .duplicate(existingPath: "docs/existing.pdf"))
        XCTAssertEqual(actual.keepBothTargetRelativePath, "docs/source_1.pdf")
        XCTAssertEqual(actual.existingFile?.path, "docs/existing.pdf")
        XCTAssertEqual(actual.existingFile?.sizeBytes, 12)
        XCTAssertEqual(actual.importBlockingReason(), "请先完成 duplicate-conflict conflict-duplicate 处理")
    }

    func testCorePreflightDetectsSameNameDifferentHashForNameConflict() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-name-conflict")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("incoming bytes".utf8).write(to: sourceURL)
        let sameName = FileEntrySnapshot.importSingleFileFixture(
            currentName: "source.pdf",
            category: "docs",
            hashSha256: "different-hash"
        )
        let fileLoader = ImportSingleFileStaticFileLoader(files: [
            sameName,
            .importSingleFileFixture(currentName: "source_1.pdf", category: "docs", hashSha256: "other")
        ])

        let actual = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))

        XCTAssertEqual(actual.conflict, .name(path: "docs/source.pdf"))
        XCTAssertEqual(actual.keepBothTargetRelativePath, "docs/source_2.pdf")
        XCTAssertEqual(actual.existingPaths, ["docs/source.pdf", "docs/source_1.pdf"])
        XCTAssertEqual(actual.existingFile, sameName)
        XCTAssertEqual(actual.importBlockingReason(), "请先完成 name-conflict conflict-name 处理")
    }

    func testCorePreflightRejectsInvalidTargetFilenameBeforeImport() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf")
        try Data("new".utf8).write(to: sourceURL)

        let result = await CoreImportSingleFilePreflight(
            fileLoader: ImportSingleFileStaticFileLoader(files: [])
        ).preflightSingleFileImport(request: .fixture(
            repoPath: "/tmp/repo",
            sourceURL: sourceURL,
            category: "docs",
            targetFilename: "bad/name.pdf"
        ))

        XCTAssertEqual(result.hashSha256, nil)
        XCTAssertEqual(
            result.conflict,
            .invalidFilename("文件名不能包含 / \\ : * ? \" < > |")
        )
        XCTAssertEqual(
            result.importBlockingReason(),
            "文件名不能包含 / \\ : * ? \" < > |"
        )
    }

    func testCorePreflightBlocksICloudPlaceholderBeforeCorePreviewCall() async throws {
        let sourceRoot = try makeImportSingleFileTemporaryDirectory(prefix: "preflight-source")
        defer { try? FileManager.default.removeItem(at: sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.pdf.icloud")

        let fileLoader = ImportSingleFileStaticFileLoader(files: [])

        let result = await CoreImportSingleFilePreflight(fileLoader: fileLoader)
            .preflightSingleFileImport(request: .fixture(
                repoPath: "/tmp/repo",
                sourceURL: sourceURL,
                category: "docs",
                targetFilename: "source.pdf"
            ))

        let loadRequests = await fileLoader.recordedRequests()

        XCTAssertEqual(result.conflict, .iCloudPlaceholder(path: sourceURL.path))
        XCTAssertEqual(result.importBlockingReason(), "iCloud placeholder 需要下载后才能导入")
        XCTAssertEqual(loadRequests, [])
    }
}

private struct ImportSingleFileFileLoadRequest: Equatable {
    var repoPath: String
    var categories: Set<String?>
}

private actor ImportSingleFileStaticFileLoader: ImportBatchCoreFileLoading {
    private let files: [FileEntrySnapshot]
    private var requests: [ImportSingleFileFileLoadRequest] = []

    init(files: [FileEntrySnapshot]) {
        self.files = files
    }

    func loadImportPreviewFiles(repoPath: String, categories: Set<String?>) async throws -> [FileEntrySnapshot] {
        requests.append(ImportSingleFileFileLoadRequest(repoPath: repoPath, categories: categories))
        return files
    }

    func recordedRequests() -> [ImportSingleFileFileLoadRequest] {
        requests
    }
}

private actor SemanticSearchDetailer: CoreFileDetailing {
    let file: FileEntrySnapshot

    init(file: FileEntrySnapshot) {
        self.file = file
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        file
    }
}

private actor SemanticSearchLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

private actor SemanticSearchNormalSearcher: CoreSearchQuerying {
    private var recorded: [SearchQueryRequestSnapshot] = []

    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        recorded.append(request)
        return SearchResultPageSnapshot(
            query: request.query,
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }

    func requests() -> [SearchQueryRequestSnapshot] {
        recorded
    }
}

private actor SemanticSearchSemanticSearcher: CoreSemanticSearching {
    private let page: SearchResultPageSnapshot
    private var semanticSearchRequests: [SearchQueryRequestSnapshot] = []
    private var indexBuildRequests: [SearchQueryRequestSnapshot] = []

    init(page: SearchResultPageSnapshot) {
        self.page = page
    }

    func semanticSearch(repoPath _: String,
                        request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        semanticSearchRequests.append(request)
        return page
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        indexBuildRequests.append(request)
        return .semanticSearchReport()
    }

    func semanticRequests() -> [SearchQueryRequestSnapshot] {
        semanticSearchRequests
    }

    func indexRequests() -> [SearchQueryRequestSnapshot] {
        indexBuildRequests
    }
}

private struct SemanticSearchErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "semantic-search semantic search failed",
            severity: .medium,
            suggestedAction: "Use normal search or retry.",
            recoverability: .retryable,
            rawContext: "semantic-search semantic-search-core"
        )
    }
}

private extension ImportSingleFilePreflightRequest {
    static func fixture(
        repoPath: String,
        sourceURL: URL,
        category: String,
        targetFilename: String
    ) -> ImportSingleFilePreflightRequest {
        ImportSingleFilePreflightRequest(
            repoPath: repoPath,
            sourceURL: sourceURL,
            category: category,
            targetFilename: targetFilename
        )
    }
}

private extension RepositoryOpeningResult {
    static func semanticSearchFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(config: .semanticSearchConfig(repoPath: repoPath), tree: tree, currentCategoryFiles: [])
    }
}

private extension RepoConfigSnapshot {
    static func semanticSearchConfig(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: true,
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
    static func semanticSearchTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [.semanticSearchFinanceNode()]
        )
    }

    static func semanticSearchFinanceNode() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "finance",
            displayName: "finance",
            fileCount: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "invoices",
                    displayName: "invoices",
                    kind: "Subdir",
                    relativePath: "finance/invoices",
                    fileCount: 2,
                    depth: 2,
                    children: []
                )
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func semanticSearchFixture(id: Int64, name: String = "invoice.pdf") -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "finance/invoices/\(name)",
            originalName: name,
            currentName: name,
            category: "finance",
            sizeBytes: 128,
            hashSha256: "semanticSearch-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private extension SearchResultPageSnapshot {
    static func semanticSearchPage(
        semanticFile: FileEntrySnapshot,
        normalFile: FileEntrySnapshot
    ) -> SearchResultPageSnapshot {
        let semanticResult = SearchFileResultSnapshot(file: semanticFile, score: 0.91, matches: [], noteSnippet: nil)
        let normalResult = SearchFileResultSnapshot(
            file: normalFile,
            score: 1,
            matches: [SearchMatchSnapshot(
                fieldDisplayName: "Name",
                kindDisplayName: "Exact",
                snippet: normalFile.currentName
            )],
            noteSnippet: nil
        )
        let semanticPage = SemanticSearchResultPageSnapshot.semanticSearchFixture(
            semanticMatches: [.semanticSearchFixture(result: semanticResult)],
            normalMatches: [SemanticNormalSearchMatchSnapshot(result: normalResult, dedupedBySemantic: false)]
        )
        return SearchResultPageSnapshot(
            query: "上个月的发票",
            totalCount: semanticPage.visibleTotalCount,
            results: semanticPage.visibleResults,
            diagnostics: [],
            indexStatus: .ready,
            semanticPage: semanticPage
        )
    }

    static func semanticSearchIndexNotReadyPage() -> SearchResultPageSnapshot {
        let semanticPage = SemanticSearchResultPageSnapshot.semanticSearchFixture(
            semanticMatches: [],
            normalMatches: [],
            indexStatus: .notReady,
            fallbackReason: .semanticIndexNotReady
        )
        return SearchResultPageSnapshot(
            query: "客户合同",
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .unavailable,
            semanticPage: semanticPage
        )
    }
}

private extension SemanticSearchResultPageSnapshot {
    static func semanticSearchFixture(
        semanticMatches: [SemanticSearchMatchSnapshot],
        normalMatches: [SemanticNormalSearchMatchSnapshot],
        indexStatus: SemanticIndexStatusSnapshot = .ready,
        fallbackReason: SemanticSearchFallbackReasonSnapshot? = nil
    ) -> SemanticSearchResultPageSnapshot {
        SemanticSearchResultPageSnapshot(
            query: "上个月的发票",
            semanticTotalCount: Int64(semanticMatches.count),
            normalTotalCount: Int64(normalMatches.count),
            semanticMatches: semanticMatches,
            normalMatches: normalMatches,
            dedupedNormalCount: 0,
            indexStatus: indexStatus,
            route: .local,
            fallbackReason: fallbackReason,
            fallbackMessage: nil,
            callLogID: 308,
            privacyRuleID: nil,
            lowConfidence: false
        )
    }
}

private extension SemanticSearchMatchSnapshot {
    static func semanticSearchFixture(result: SearchFileResultSnapshot) -> SemanticSearchMatchSnapshot {
        SemanticSearchMatchSnapshot(
            result: result,
            relevance: 0.91,
            matchedReason: "filename and summary match invoice",
            usedFields: [.fileName, .aiSummary],
            route: .local,
            alsoMatchedNormalSearch: false,
            callLogID: 308,
            privacyRuleID: nil
        )
    }
}

private extension SemanticIndexBuildReportSnapshot {
    static func semanticSearchReport() -> SemanticIndexBuildReportSnapshot {
        SemanticIndexBuildReportSnapshot(
            status: .ready,
            route: .local,
            totalCount: 1,
            processedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            privacySkippedCount: 0,
            providerName: "Local",
            callLogID: 308,
            fallbackReason: nil,
            message: nil
        )
    }
}
