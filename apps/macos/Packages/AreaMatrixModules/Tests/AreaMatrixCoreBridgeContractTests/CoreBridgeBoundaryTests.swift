@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreBridgeBoundaryTests: XCTestCase {
    func testBoundaryNamesAreStableAndUnique() {
        let boundaries = CoreBridgeBoundary.allCases

        XCTAssertFalse(boundaries.isEmpty)
        XCTAssertEqual(Set(boundaries.map(\.rawValue)).count, boundaries.count)
        XCTAssertEqual(CoreBridgeBoundary.validateRepoPath.rawValue, "validate_repo_path")
        XCTAssertEqual(CoreBridgeBoundary.mapCoreError.rawValue, "map_core_error")
    }
}
