@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static var semanticSearchPageFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .internal,
            userMessage: "semantic-search semantic page failed",
            severity: .medium,
            suggestedAction: "Retry the failed semantic group.",
            recoverability: .retryable,
            rawContext: "semantic-search"
        )
    }
}

extension FileEntrySnapshot {
    static func semanticSearchPageFile(id: Int64, name: String = "invoice.pdf") -> FileEntrySnapshot {
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

extension SearchFileResultSnapshot {
    static func semanticSearchPageResult(
        file: FileEntrySnapshot,
        snippet: String = "filename contains invoice"
    ) -> SearchFileResultSnapshot {
        .testFixture(
            file: file,
            matches: [.testFixture(kindDisplayName: "Exact", snippet: snippet)]
        )
    }
}

extension RepositoryOpeningResult {
    static func semanticSearchPageOpening(tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(config: .semanticSearchPageConfig(), tree: tree, currentCategoryFiles: [])
    }
}

extension RepoConfigSnapshot {
    static func semanticSearchPageConfig() -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: "/tmp/repo") {
            $0.aiEnabled = true
        }
    }
}

extension RepositoryTreeNodeSnapshot {
    static func semanticSearchPageTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(children: [.semanticSearchPageFinanceNode()])
    }

    static func semanticSearchPageFinanceNode() -> RepositoryTreeNodeSnapshot {
        .testCategory(
            "finance",
            children: [.testSubdirectory("invoices", relativePath: "finance/invoices", fileCount: 2)]
        )
    }
}

extension SemanticSearchMatchSnapshot {
    static func semanticSearchPage(
        result: SearchFileResultSnapshot,
        alsoMatchedNormalSearch: Bool = false
    ) -> SemanticSearchMatchSnapshot {
        SemanticSearchMatchSnapshot(
            result: result,
            relevance: 0.91,
            matchedReason: "filename and summary match invoice",
            usedFields: [.fileName, .aiSummary],
            route: .local,
            alsoMatchedNormalSearch: alsoMatchedNormalSearch,
            callLogID: 308,
            privacyRuleID: nil
        )
    }
}

extension SemanticSearchResultPageSnapshot {
    static func testFixture(
        query: String = "invoice",
        semanticMatches: [SemanticSearchMatchSnapshot] = [],
        normalMatches: [SemanticNormalSearchMatchSnapshot] = [],
        dedupedNormalCount: Int64 = 0,
        semanticTotalCount: Int64? = nil,
        normalTotalCount: Int64? = nil,
        indexStatus: SemanticIndexStatusSnapshot = .ready,
        route: SemanticSearchRouteSnapshot? = .local,
        fallbackReason: SemanticSearchFallbackReasonSnapshot? = nil,
        fallbackMessage: String? = nil,
        callLogID: Int64? = 308,
        privacyRuleID: String? = nil,
        lowConfidence: Bool = false
    ) -> SemanticSearchResultPageSnapshot {
        SemanticSearchResultPageSnapshot(
            query: query,
            semanticTotalCount: semanticTotalCount ?? Int64(semanticMatches.count),
            normalTotalCount: normalTotalCount ?? Int64(normalMatches.count),
            semanticMatches: semanticMatches,
            normalMatches: normalMatches,
            dedupedNormalCount: dedupedNormalCount,
            indexStatus: indexStatus,
            route: route,
            fallbackReason: fallbackReason,
            fallbackMessage: fallbackMessage,
            callLogID: callLogID,
            privacyRuleID: privacyRuleID,
            lowConfidence: lowConfidence
        )
    }

    static func semanticSearchPage(
        semanticMatches: [SemanticSearchMatchSnapshot],
        normalMatches: [SemanticNormalSearchMatchSnapshot],
        dedupedNormalCount: Int64 = 0,
        semanticTotalCount: Int64? = nil,
        indexStatus: SemanticIndexStatusSnapshot = .ready,
        fallbackReason: SemanticSearchFallbackReasonSnapshot? = nil,
        fallbackMessage: String? = nil
    ) -> SemanticSearchResultPageSnapshot {
        .testFixture(
            semanticMatches: semanticMatches,
            normalMatches: normalMatches,
            dedupedNormalCount: dedupedNormalCount,
            semanticTotalCount: semanticTotalCount,
            indexStatus: indexStatus,
            fallbackReason: fallbackReason,
            fallbackMessage: fallbackMessage
        )
    }
}

extension SearchResultPageSnapshot {
    static func semanticSearchSearchPage(
        semantic: [FileEntrySnapshot],
        normal: [FileEntrySnapshot],
        semanticTotalCount: Int64? = nil,
        indexStatus: SemanticIndexStatusSnapshot = .ready
    ) -> SearchResultPageSnapshot {
        let semanticPage = SemanticSearchResultPageSnapshot.semanticSearchPage(
            semanticMatches: semantic.map { .semanticSearchPage(result: .semanticSearchPageResult(file: $0)) },
            normalMatches: normal.map {
                SemanticNormalSearchMatchSnapshot(result: .semanticSearchPageResult(file: $0), dedupedBySemantic: false)
            },
            semanticTotalCount: semanticTotalCount,
            indexStatus: indexStatus
        )
        return .testFixture(
            query: semanticPage.query,
            totalCount: semanticPage.visibleTotalCount,
            results: semanticPage.visibleResults,
            indexStatus: SearchIndexStatusSnapshot(semanticStatus: indexStatus),
            semanticPage: semanticPage
        )
    }

    static func semanticSearchIndexBuildingPage() -> SearchResultPageSnapshot {
        semanticSearchSearchPage(semantic: [], normal: [], indexStatus: .building)
    }
}

extension SemanticIndexBuildReportSnapshot {
    static func semanticSearchReadyReport() -> SemanticIndexBuildReportSnapshot {
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
