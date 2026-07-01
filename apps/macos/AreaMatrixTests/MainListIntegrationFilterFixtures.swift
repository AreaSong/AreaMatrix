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
