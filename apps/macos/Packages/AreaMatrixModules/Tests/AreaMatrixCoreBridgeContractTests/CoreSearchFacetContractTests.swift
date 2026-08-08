@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreSearchFacetContractTests: XCTestCase {
    func testSearchFilterStateComputesStableIdentity() {
        var filters = SearchFilterStateSnapshot.empty
        XCTAssertTrue(filters.isEmpty)
        XCTAssertEqual(filters.activeFilterCount, 0)

        filters.category = "work"
        filters.tags = ["urgent"]
        filters.storageMode = .indexed
        filters.includeDeleted = true

        XCTAssertFalse(filters.isEmpty)
        XCTAssertEqual(filters.activeFilterCount, 4)
        XCTAssertTrue(filters.taskKey.contains("work|"))
        XCTAssertTrue(filters.taskKey.contains("include-deleted"))
    }

    func testSearchFacetContractCanBeImplementedWithoutGeneratedBindings() async throws {
        let implementation = ContractDouble()
        let request = SearchFacetRequestSnapshot(
            query: "report",
            scope: .all,
            currentPath: nil,
            category: nil,
            filters: .empty
        )
        let facets = try await implementation.listFilterFacets(repoPath: "/tmp/repository", request: request)

        XCTAssertEqual(facets.query, "report")
        XCTAssertEqual(facets.totalCount, 1)
        XCTAssertEqual(facets.categories.first?.value, "work")
        XCTAssertEqual(facets.storageModes.first?.value, .indexed)
    }
}

private struct ContractDouble: CoreSearchFiltering {
    func listFilterFacets(
        repoPath _: String,
        request: SearchFacetRequestSnapshot
    ) async throws -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: request.query,
            totalCount: 1,
            categories: [
                SearchFacetCountSnapshot(value: "work", label: "Work", count: 1, selected: false, disabled: false)
            ],
            fileKinds: [],
            tags: [],
            storageModes: [
                SearchStorageModeFacetCountSnapshot(
                    value: .indexed,
                    label: "Indexed",
                    count: 1,
                    selected: false,
                    disabled: false
                )
            ],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: request.filters.activeFilterCount
        )
    }
}
