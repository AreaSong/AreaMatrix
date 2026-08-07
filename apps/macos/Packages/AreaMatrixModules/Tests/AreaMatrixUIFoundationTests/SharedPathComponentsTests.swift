@testable import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SharedPathComponentsTests: XCTestCase {
    func testPathBoxStylePlainUsesOpaqueQuaternarySurface() {
        XCTAssertEqual(
            AreaMatrixPathBoxStyle.plain,
            AreaMatrixPathBoxStyle.quaternary(backgroundOpacity: 1)
        )
    }

    func testPathComponentsExposeStableConstructionContracts() {
        _ = AreaMatrixGlassCardModifier(cornerRadius: 10)
        _ = AreaMatrixPathBox(path: "/tmp/repository", style: .plain, lineLimit: 3, alignment: .leading)
    }
}
