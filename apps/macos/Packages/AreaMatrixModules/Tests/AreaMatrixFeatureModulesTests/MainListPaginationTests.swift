import AreaMatrixFeatureLibrary
import XCTest

final class MainListPaginationTests: XCTestCase {
    private struct Item: Equatable {
        let id: Int
        let value: String
    }

    func testPaginationTracksReplaceAppendAndReset() {
        var pagination = MainListPagination(initialCount: 50)
        XCTAssertEqual(pagination.nextOffset, 50)
        XCTAssertTrue(pagination.hasMore)

        pagination.append(itemCount: 20)
        XCTAssertEqual(pagination.nextOffset, 70)
        XCTAssertFalse(pagination.hasMore)
        XCTAssertEqual(pagination.reloadLimit(), 70)

        pagination.replace(itemCount: 50, requestedLimit: 70)
        XCTAssertEqual(pagination.nextOffset, 50)
        XCTAssertFalse(pagination.hasMore)

        pagination.reset()
        XCTAssertEqual(pagination, MainListPagination(initialCount: 0))
    }

    func testMergingUniquePreservesOrderAndUsesLatestValue() {
        let existing = [Item(id: 1, value: "old"), Item(id: 2, value: "two")]
        let loaded = [Item(id: 1, value: "new"), Item(id: 3, value: "three")]

        XCTAssertEqual(
            MainListPagination.mergingUnique(existing: existing, appending: loaded, id: \Item.id),
            [Item(id: 1, value: "new"), Item(id: 2, value: "two"), Item(id: 3, value: "three")]
        )
    }

    func testLoadingStateOwnsPaginationAndBusyFlags() {
        var state = MainListLoadingState(isLoading: true, isLoadingMore: true)
        state.apply(MainListPagination(initialCount: 50))

        XCTAssertTrue(state.isLoading)
        XCTAssertTrue(state.isLoadingMore)
        XCTAssertTrue(state.hasMore)
        XCTAssertEqual(state.nextOffset, 50)

        state.resetPagination()
        XCTAssertFalse(state.hasMore)
        XCTAssertFalse(state.isLoadingMore)
        XCTAssertEqual(state.nextOffset, 0)
    }
}
