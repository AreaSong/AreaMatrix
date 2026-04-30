import XCTest
@testable import AreaMatrix

final class AreaMatrixShellTests: XCTestCase {
    func testBridgeStartsAsPlaceholder() {
        XCTAssertEqual(CoreBridge().state, .placeholder)
        XCTAssertEqual(CoreBridge().coreAvailability(), "placeholder")
    }

    func testAppShellModelUsesPhaseZeroStatus() {
        XCTAssertEqual(AppShellModel().statusText, "Phase 0 app shell")
    }
}
