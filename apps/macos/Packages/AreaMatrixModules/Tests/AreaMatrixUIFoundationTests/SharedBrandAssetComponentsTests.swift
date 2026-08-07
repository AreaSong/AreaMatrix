import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SharedBrandAssetComponentsTests: XCTestCase {
    func testBrandAssetComponentsExposeStableConstructionContracts() {
        _ = AreaMatrixTrafficLights()
        _ = AreaMatrixMiniWindow(title: "AreaMatrix", width: 320, height: 180) {
            Text("Preview")
        }
        _ = AreaMatrixBottomCornersShape()
        _ = AreaMatrixHexagonShape()
        _ = AreaMatrixFolderShape(tabWidth: 64, tabHeight: 24, cornerRadius: 16)
        _ = AreaMatrixNoiseOverlay()
    }
}
