@testable import AreaMatrixUIFoundation
import XCTest

final class AsyncLoadStateTests: XCTestCase {
    func testStateExposesOnlyTheAssociatedValueForItsCurrentPhase() {
        let loaded = AsyncLoadState<Int, TestFailure>.loaded(42)
        XCTAssertEqual(loaded.value, 42)
        XCTAssertNil(loaded.failure)
        XCTAssertFalse(loaded.isLoading)

        let failed = AsyncLoadState<Int, TestFailure>.failed(.unavailable)
        XCTAssertNil(failed.value)
        XCTAssertEqual(failed.failure, .unavailable)
        XCTAssertFalse(failed.isLoading)

        let loading = AsyncLoadState<Int, TestFailure>.loading
        XCTAssertNil(loading.value)
        XCTAssertNil(loading.failure)
        XCTAssertTrue(loading.isLoading)
    }

    func testPhaseStateExposesFailureAndProgressWithoutPayload() {
        XCTAssertTrue(AsyncPhaseState<TestFailure>.loading.isLoading)
        XCTAssertTrue(AsyncPhaseState<TestFailure>.loaded.isLoaded)
        XCTAssertEqual(AsyncPhaseState<TestFailure>.failed(.unavailable).failure, .unavailable)
    }
}

private enum TestFailure: Equatable {
    case unavailable
}
