@testable import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SharedPageSurfaceComponentsTests: XCTestCase {
    func testPageSurfaceModifiersExposeStableConstructionContracts() {
        _ = AreaMatrixGlassContentPanelModifier(width: nil, cornerRadius: 18, padding: 24)
        _ = AreaMatrixWorkspaceRegionShellModifier(cornerRadius: 10)
    }
}
