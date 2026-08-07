@testable import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SharedButtonComponentsTests: XCTestCase {
    func testButtonComponentsExposeStableConstructionContracts() {
        _ = AreaMatrixCapsuleButton(
            isHovered: false,
            action: {},
            label: { Text("Continue") }
        )
        _ = AreaMatrixGhostButton(
            isHovered: true,
            action: {},
            label: { Text("Back") }
        )
        _ = AreaMatrixPrimaryGlowButton(
            accent: .teal,
            isHovered: false,
            shimmerPhase: .constant(0)
        ) {
            Text("Primary")
        }
        _ = AreaMatrixLinkActionLabel(title: "Help", iconName: "questionmark.circle", isHovered: false)
        _ = AreaMatrixPrimaryActionLabel(title: "Import", iconName: "plus", shortcut: "⌘I", isHovered: false)
        _ = AreaMatrixPrimaryButtonStyle()
        _ = AreaMatrixSecondaryButtonStyle()
    }

    func testSharedMotionComponentsExposeStableContracts() {
        XCTAssertNotNil(Animation.areaMatrixQuickFade)
        XCTAssertNotNil(Animation.areaMatrixGlowBreath)
        _ = Text("Motion")
            .areaMatrixPulseAura(color: .teal)
            .areaMatrixMagneticHover()
            .areaMatrixDelayedEntrance(isVisible: true)
            .areaMatrixDeepDive(isActive: false, scale: 1.05)
    }
}
