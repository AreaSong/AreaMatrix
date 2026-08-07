@testable import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SharedAssetComponentsTests: XCTestCase {
    func testCrossfadeAssetImageExposesStableConstructionContract() {
        _ = AreaMatrixCrossfadeAssetImage(
            darkName: "AreaMatrixLogoLockupDark",
            lightName: "AreaMatrixLogoLockupLight",
            width: 80,
            height: 80
        )
    }
}
