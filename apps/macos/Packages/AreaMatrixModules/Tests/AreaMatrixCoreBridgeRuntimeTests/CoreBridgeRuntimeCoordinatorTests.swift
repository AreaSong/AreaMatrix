import AreaMatrixCoreBridgeContract
@testable import AreaMatrixCoreBridgeRuntime
import XCTest

final class CoreBridgeRuntimeCoordinatorTests: XCTestCase {
    func testCoordinatorExposesConfiguredRuntimeMetadata() async {
        let runtime = CoreBridgeRuntimeCoordinator(
            state: .unavailable,
            availability: "test-unavailable",
            boundaries: [.getVersion, .mapCoreError]
        )

        let boundaries = await runtime.declaredBoundaries()
        XCTAssertEqual(runtime.state, .unavailable)
        XCTAssertEqual(runtime.coreAvailability(), "test-unavailable")
        XCTAssertEqual(boundaries, [.getVersion, .mapCoreError])
        XCTAssertTrue(runtime.isDeclared(.getVersion))
        XCTAssertFalse(runtime.isDeclared(.loadConfig))
    }
}
