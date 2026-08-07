@testable import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SceneMotionComponentsTests: XCTestCase {
    func testParallaxNormalizesPointerCoordinates() {
        let parallax = AreaMatrixParallax(
            pointerLocation: CGPoint(x: 100, y: 25),
            in: CGSize(width: 200, height: 50)
        )

        XCTAssertEqual(parallax.horizontal, 0)
        XCTAssertEqual(parallax.vertical, 0)
    }

    func testSceneVisibilityExposesPhaseState() {
        XCTAssertTrue(AreaMatrixSceneVisibility.enter(isVisible: true).isVisible)
        XCTAssertFalse(AreaMatrixSceneVisibility.exit(isVisible: false).isVisible)
        XCTAssertNotNil(AnyTransition.areaMatrixScene)
    }

    func testSceneMotionAndDecodedTextExposePackageContracts() {
        _ = AreaMatrixSceneVisualMotionModifier()
        _ = AreaMatrixSceneTextMotionModifier(delay: 0.1)
        _ = AreaMatrixDecodedText(text: "Preview")
    }
}
