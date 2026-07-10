@testable import AreaMatrix
import XCTest

struct MainListSearchFacetRequestRecord: Equatable {
    var repoPath: String
    var request: SearchFacetRequestSnapshot
}

actor MainListRecordingSearchFiltering: CoreSearchFiltering {
    private var results: [Swift.Result<SearchFacetsSnapshot, Error>]
    private var requests: [MainListSearchFacetRequestRecord] = []

    init(results: [Swift.Result<SearchFacetsSnapshot, Error>]) {
        self.results = results
    }

    func listFilterFacets(repoPath: String, request: SearchFacetRequestSnapshot) async throws -> SearchFacetsSnapshot {
        requests.append(MainListSearchFacetRequestRecord(repoPath: repoPath, request: request))
        guard !results.isEmpty else {
            return .searchFiltersFixture(active: request.filters.activeFilterCount)
        }

        return try results.removeFirst().get()
    }

    func recordedRequests() -> [MainListSearchFacetRequestRecord] {
        requests
    }

    func assertRequests(
        _ expectedRequests: [SearchFacetRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.map(\.request), expectedRequests, file: file, line: line)
    }
}
