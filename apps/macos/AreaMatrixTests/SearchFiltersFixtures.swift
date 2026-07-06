@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func searchFiltersFixture(repoPath: String, tree: RepositoryTreeNodeSnapshot) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .searchFiltersFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

extension RepoConfigSnapshot {
    static func searchFiltersFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension SearchResultPageSnapshot {
    static func searchFiltersSearchFixture(query: String) -> SearchResultPageSnapshot {
        .testFixture(query: query)
    }
}

struct SearchFacetsTestFixtureOptions {
    var categories: [SearchFacetCountSnapshot] = []
    var fileKinds: [SearchFacetCountSnapshot] = []
    var tags: [SearchFacetCountSnapshot] = []
    var storageModes: [SearchStorageModeFacetCountSnapshot] = []
    var dateBounds: SearchDateFacetBoundsSnapshot = .testEmpty
    var activeFilterCount: Int64 = 0
}

extension SearchDateFacetBoundsSnapshot {
    static var testEmpty: SearchDateFacetBoundsSnapshot {
        SearchDateFacetBoundsSnapshot(
            oldestImportedAt: nil,
            newestImportedAt: nil,
            oldestModifiedAt: nil,
            newestModifiedAt: nil
        )
    }
}

extension SearchFacetCountSnapshot {
    static func testFixture(
        value: String,
        label: String? = nil,
        count: Int64 = 0,
        selected: Bool = false,
        disabled: Bool = false
    ) -> SearchFacetCountSnapshot {
        SearchFacetCountSnapshot(
            value: value,
            label: label ?? value,
            count: count,
            selected: selected,
            disabled: disabled
        )
    }
}

extension SearchFacetsSnapshot {
    static func testFixture(
        query: String = "",
        totalCount: Int64 = 0,
        options configure: (inout SearchFacetsTestFixtureOptions) -> Void = { _ in }
    ) -> SearchFacetsSnapshot {
        var options = SearchFacetsTestFixtureOptions()
        configure(&options)

        return SearchFacetsSnapshot(
            query: query,
            totalCount: totalCount,
            categories: options.categories,
            fileKinds: options.fileKinds,
            tags: options.tags,
            storageModes: options.storageModes,
            dateBounds: options.dateBounds,
            activeFilterCount: options.activeFilterCount
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func searchFiltersFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(
            children: [
                .testCategory(
                    "docs",
                    children: [.testSubdirectory("contracts", relativePath: "docs/contracts", fileCount: 2)]
                )
            ]
        )
    }
}

extension SearchFacetsSnapshot {
    static func searchFiltersFixture(active: Int64) -> SearchFacetsSnapshot {
        SearchFacetsSnapshot.testFixture(query: "合同", totalCount: 7) {
            $0.activeFilterCount = active
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func searchFiltersDbFixture() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "过滤器不可用",
            severity: .high,
            suggestedAction: "请重试过滤器。",
            recoverability: .retryable,
            rawContext: "facet db locked"
        )
    }
}
