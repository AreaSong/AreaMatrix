@testable import AreaMatrix
import Foundation

struct ImportSingleFileFileLoadRequest: Equatable {
    var repoPath: String
    var categories: Set<String?>
}

actor ImportSingleFileStaticFileLoader: ImportBatchCoreFileLoading {
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

actor SemanticSearchDetailer: CoreFileDetailing {
    let file: FileEntrySnapshot

    init(file: FileEntrySnapshot) {
        self.file = file
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        file
    }
}

actor SemanticSearchLister: CoreFileListing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        []
    }
}

actor SemanticSearchNormalSearcher: CoreSearchQuerying {
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

actor SemanticSearchSemanticSearcher: CoreSemanticSearching {
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

struct SemanticSearchErrorMapper: CoreErrorMapping {
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

extension ImportSingleFilePreflightRequest {
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

extension RepositoryOpeningResult {
    static func semanticSearchFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(config: .semanticSearchConfig(repoPath: repoPath), tree: tree, currentCategoryFiles: [])
    }
}

extension RepoConfigSnapshot {
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

extension RepositoryTreeNodeSnapshot {
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

extension FileEntrySnapshot {
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

extension SearchResultPageSnapshot {
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

extension SemanticSearchResultPageSnapshot {
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

extension SemanticSearchMatchSnapshot {
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

extension SemanticIndexBuildReportSnapshot {
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
