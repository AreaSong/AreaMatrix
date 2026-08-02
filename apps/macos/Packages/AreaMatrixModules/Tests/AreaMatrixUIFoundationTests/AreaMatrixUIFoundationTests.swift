@testable import AreaMatrixUIFoundation
import XCTest

final class AreaMatrixUIFoundationTests: XCTestCase {
    func testThemeTokensExposeStableLightAndDarkValues() {
        XCTAssertEqual(AreaMatrixAmbientScene.classify.accent, .tealBright)
        XCTAssertEqual(AreaMatrixTheme.Colors.backgroundTop.resolve(.dark), AreaMatrixTheme.Colors.backgroundTop.dark)
        XCTAssertEqual(AreaMatrixTheme.Colors.backgroundTop.resolve(.light), AreaMatrixTheme.Colors.backgroundTop.light)
    }

    func testMotionTokensKeepSharedTimingContract() {
        XCTAssertLessThan(AreaMatrixMotionTokens.Duration.quickFade, AreaMatrixMotionTokens.Duration.entrance)
        XCTAssertEqual(AreaMatrixMotionTokens.AmbientStrength.subdued.opacityScale, 0.55)
    }
}
