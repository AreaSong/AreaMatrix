@testable import AreaMatrix
import XCTest

struct MainListSearchFacetRequestRecord: Equatable {
    var repoPath: String
    var request: SearchFacetRequestSnapshot
}

actor MainListRecordingSearchFiltering: CoreSearchFiltering {
    private var resultQueue: TestResultQueue<SearchFacetsSnapshot>
    private var requests: [MainListSearchFacetRequestRecord] = []

    init(results: [Swift.Result<SearchFacetsSnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .success(.searchFiltersFixture(active: 0))
        }
    }

    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot {
        requests.append(MainListSearchFacetRequestRecord(repoPath: repoPath, request: request))
        return try resultQueue.next {
            .success(.searchFiltersFixture(active: request.filters.activeFilterCount))
        }
    }

    func assertSearchFacetRequests(
        _ expectedRequests: [SearchFacetRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.map(\.request), expectedRequests, file: file, line: line)
    }

    func assertRequestFilters(
        _ expectedFilters: [SearchFilterStateSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.map(\.request.filters), expectedFilters, file: file, line: line)
    }
}
