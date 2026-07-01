@testable import AreaMatrix

extension SearchQueryRequestSnapshot {
    static func savedSearchSavedSearchFixture(query: String) -> SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query,
            scope: .all,
            currentPath: nil,
            category: nil,
            filters: SearchFilterStateSnapshot(
                category: "docs",
                fileKind: "pdf",
                tags: ["finance"],
                tagMatchMode: .all,
                importedAfter: nil,
                importedBefore: nil,
                modifiedAfter: 1_700_000_000,
                modifiedBefore: nil,
                storageMode: .copied,
                includeDeleted: false
            ),
            sort: .relevance,
            limit: 50,
            offset: 0
        )
    }
}

extension SavedSearchSnapshot {
    static func savedSearchFixture(id: Int64, request: CreateSavedSearchRequestSnapshot) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: id,
            name: request.name,
            query: request.query,
            icon: request.icon,
            color: request.color,
            pinned: request.pinned,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }

    static func smartListFixture(
        id: Int64,
        name: String,
        pinned: Bool,
        updatedAt: Int64
    ) -> SavedSearchSnapshot {
        let request = SearchQueryRequestSnapshot.savedSearchSavedSearchFixture(query: name)
        return SavedSearchSnapshot(
            id: id,
            name: name,
            query: SavedSearchQuerySnapshot(request: request),
            icon: "magnifyingglass",
            color: nil,
            pinned: pinned,
            createdAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

typealias SmartListRecordingSavedSearchStore = RecordingSavedSearchStore

extension SearchResultPageSnapshot {
    static func savedSearchSavedSearchFixture(
        request: SearchQueryRequestSnapshot,
        files: [FileEntrySnapshot]
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: request.query,
            totalCount: Int64(files.count),
            results: files.map { file in
                SearchFileResultSnapshot(file: file, score: 1, matches: [], noteSnippet: nil)
            },
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

func sortedSavedSearches(_ savedSearches: [SavedSearchSnapshot]) -> [SavedSearchSnapshot] {
    savedSearches.sorted { lhs, rhs in
        if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
        if lhs.pinned { return lhs.updatedAt > rhs.updatedAt }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

extension RepositoryTreeNodeSnapshot {
    func appendingSortedSavedSearches(_ savedSearches: [SavedSearchSnapshot]) -> RepositoryTreeNodeSnapshot {
        sortedSavedSearches(savedSearches).reduce(self) { tree, saved in
            tree.insertingSavedSearch(saved)
        }
    }
}

extension FileEntrySnapshot {
    static func savedSearchSavedSearchFixture() -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 203,
            path: "docs/finance/report.pdf",
            originalName: "report.pdf",
            currentName: "report.pdf",
            category: "docs",
            sizeBytes: 128,
            hashSha256: "saved-search-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100,
            availability: .available
        )
    }
}

extension RepositoryOpeningResult {
    static func savedSearchSavedSearchFixture(
        repoPath: String,
        tree: RepositoryTreeNodeSnapshot
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
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
            ),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func savedSearchSavedSearchFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "inbox",
                    displayName: "inbox",
                    fileCount: 0,
                    children: []
                )
            ]
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func savedSearchSavedSearchDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Saved search is unavailable.",
            severity: .high,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "saved search db locked"
        )
    }
}
