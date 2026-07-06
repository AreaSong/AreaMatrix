@testable import AreaMatrix

extension SearchQueryRequestSnapshot {
    static func savedSearchSavedSearchFixture(query: String) -> SearchQueryRequestSnapshot {
        .testFixture(
            query: query,
            filters: .testFixture(
                category: "docs",
                fileKind: "pdf",
                tags: ["finance"],
                tagMatchMode: .all,
                modifiedAfter: 1_700_000_000,
                storageMode: .copied
            )
        )
    }
}

extension SavedSearchQuerySnapshot {
    static func testFixture(request: SearchQueryRequestSnapshot) -> SavedSearchQuerySnapshot {
        SavedSearchQuerySnapshot(request: request)
    }
}

extension SavedSearchSnapshot {
    static func testFixture(
        id: Int64,
        name: String,
        query: SavedSearchQuerySnapshot,
        icon: String? = "magnifyingglass",
        color: String? = nil,
        pinned: Bool = true,
        createdAt: Int64 = 1_700_000_000,
        updatedAt: Int64 = 1_700_000_000
    ) -> SavedSearchSnapshot {
        SavedSearchSnapshot(
            id: id,
            name: name,
            query: query,
            icon: icon,
            color: color,
            pinned: pinned,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func testFixture(id: Int64, request: CreateSavedSearchRequestSnapshot) -> SavedSearchSnapshot {
        .testFixture(
            id: id,
            name: request.name,
            query: request.query,
            icon: request.icon,
            color: request.color,
            pinned: request.pinned
        )
    }

    static func savedSearchFixture(id: Int64, request: CreateSavedSearchRequestSnapshot) -> SavedSearchSnapshot {
        .testFixture(id: id, request: request)
    }

    static func smartListFixture(
        id: Int64,
        name: String,
        pinned: Bool,
        updatedAt: Int64
    ) -> SavedSearchSnapshot {
        let request = SearchQueryRequestSnapshot.savedSearchSavedSearchFixture(query: name)
        return .testFixture(
            id: id,
            name: name,
            query: .testFixture(request: request),
            pinned: pinned,
            updatedAt: updatedAt
        )
    }
}

extension SearchResultPageSnapshot {
    static func savedSearchSavedSearchFixture(
        request: SearchQueryRequestSnapshot,
        files: [FileEntrySnapshot]
    ) -> SearchResultPageSnapshot {
        .testFixture(
            query: request.query,
            results: files.map { file in
                SearchFileResultSnapshot.testFixture(file: file)
            }
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
        FileEntrySnapshot.testFixture(
            id: 203,
            path: "docs/finance/report.pdf",
            currentName: "report.pdf",
            category: "docs"
        ) {
            $0.hashSha256 = "saved-search-hash"
        }
    }
}

extension RepositoryOpeningResult {
    static func savedSearchSavedSearchFixture(
        repoPath: String,
        tree: RepositoryTreeNodeSnapshot
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .testFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func savedSearchSavedSearchFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(children: [.testCategory("inbox")])
    }
}

extension CoreErrorMappingSnapshot {
    static func savedSearchSavedSearchDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "Saved search is unavailable.",
            severity: .high,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "saved search db locked"
        )
    }
}
