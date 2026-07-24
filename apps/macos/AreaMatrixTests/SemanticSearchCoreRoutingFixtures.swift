@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static var semanticSearchFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .internal,
            userMessage: "semantic-search semantic search failed",
            severity: .medium,
            suggestedAction: "Use normal search or retry.",
            recoverability: .retryable,
            rawContext: "semantic-search semantic-search-core"
        )
    }
}

extension RepositoryOpeningResult {
    static func semanticSearchFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(config: .semanticSearchConfig(repoPath: repoPath), tree: tree, currentCategoryFiles: [])
    }
}

extension AppRepoConfigSnapshot {
    static func semanticSearchConfig(repoPath: String) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath) {
            $0.aiEnabled = true
        }
    }
}

extension RepositoryTreeNodeSnapshot {
    static func semanticSearchTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(children: [.semanticSearchFinanceNode()])
    }

    static func semanticSearchFinanceNode() -> RepositoryTreeNodeSnapshot {
        .testCategory(
            "finance",
            children: [.testSubdirectory("invoices", relativePath: "finance/invoices", fileCount: 2)]
        )
    }
}

extension FileEntrySnapshot {
    static func semanticSearchFixture(id: Int64, name: String = "invoice.pdf") -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "finance/invoices/\(name)",
            currentName: name,
            category: "finance"
        ) {
            $0.hashSha256 = "semanticSearch-\(id)"
        }
    }
}

extension SearchResultPageSnapshot {
    static func semanticSearchPage(
        semanticFile: FileEntrySnapshot,
        normalFile: FileEntrySnapshot
    ) -> SearchResultPageSnapshot {
        let semanticResult = SearchFileResultSnapshot.testFixture(file: semanticFile, score: 0.91)
        let normalResult = SearchFileResultSnapshot.nameMatchFixture(file: normalFile, kindDisplayName: "Exact")
        let semanticPage = SemanticSearchResultPageSnapshot.semanticSearchFixture(
            semanticMatches: [.semanticSearchFixture(result: semanticResult)],
            normalMatches: [.testFixture(result: normalResult)]
        )
        return .testFixture(
            query: "上个月的发票",
            totalCount: semanticPage.visibleTotalCount,
            results: semanticPage.visibleResults,
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
        return .testFixture(
            query: "客户合同",
            totalCount: 0,
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
        .testFixture(
            query: "上个月的发票",
            semanticMatches: semanticMatches,
            normalMatches: normalMatches,
            indexStatus: indexStatus,
            fallbackReason: fallbackReason
        )
    }
}

extension SemanticSearchMatchSnapshot {
    static func semanticSearchFixture(result: SearchFileResultSnapshot) -> SemanticSearchMatchSnapshot {
        .testFixture(result: result)
    }
}

extension SemanticIndexBuildReportSnapshot {
    static func semanticSearchReport() -> SemanticIndexBuildReportSnapshot {
        .testFixture()
    }
}
