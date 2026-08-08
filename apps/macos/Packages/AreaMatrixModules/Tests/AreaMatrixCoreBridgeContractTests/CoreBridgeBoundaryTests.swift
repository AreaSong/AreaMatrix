@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreBridgeBoundaryTests: XCTestCase {
    func testBoundaryNamesAreStableAndUnique() {
        let boundaries = CoreBridgeBoundary.allCases

        XCTAssertFalse(boundaries.isEmpty)
        XCTAssertEqual(Set(boundaries.map(\.rawValue)).count, boundaries.count)
        XCTAssertEqual(CoreBridgeBoundary.validateRepoPath.rawValue, "validate_repo_path")
        XCTAssertEqual(CoreBridgeBoundary.listCommandTargets.rawValue, "list_command_targets")
        XCTAssertEqual(CoreBridgeBoundary.listAICalls.rawValue, "list_ai_calls")
        XCTAssertEqual(CoreBridgeBoundary.clearAICallLog.rawValue, "clear_ai_call_log")
        XCTAssertEqual(CoreBridgeBoundary.mapCoreError.rawValue, "map_core_error")
    }

    func testRuntimeContractExposesStableStateAndBoundaryProvider() {
        XCTAssertEqual(CoreBridgeRuntimeState.unavailable.rawValue, "unavailable")
        XCTAssertEqual(CoreBridgeRuntimeState.generatedBindings.rawValue, "generatedBindings")
        XCTAssertEqual(
            CoreBridgeRuntimeError.undeclaredBoundary(.loadConfig),
            .undeclaredBoundary(.loadConfig)
        )
    }
}
