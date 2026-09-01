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
        _ = FilterChipButton(title: "Tag", accessibilityLabel: "Remove Tag", action: {})
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

    func testAccessibilityMotionPolicyKeepsMotionAndTransparencySettingsIndependent() {
        let standard = AreaMatrixAccessibilityMotionPolicy()
        let reducedMotion = AreaMatrixAccessibilityMotionPolicy(reduceMotion: true)
        let reducedTransparency = AreaMatrixAccessibilityMotionPolicy(reduceTransparency: true)
        let fullyReduced = AreaMatrixAccessibilityMotionPolicy(
            reduceMotion: true,
            reduceTransparency: true
        )

        XCTAssertTrue(standard.allowsContinuousMotion)
        XCTAssertTrue(standard.allowsParallax)
        XCTAssertTrue(standard.allowsBlur)
        XCTAssertFalse(standard.usesOpaqueSurfaces)

        XCTAssertFalse(reducedMotion.allowsContinuousMotion)
        XCTAssertFalse(reducedMotion.allowsParallax)
        XCTAssertTrue(reducedMotion.allowsBlur)
        XCTAssertFalse(reducedMotion.usesOpaqueSurfaces)

        XCTAssertTrue(reducedTransparency.allowsContinuousMotion)
        XCTAssertTrue(reducedTransparency.allowsParallax)
        XCTAssertFalse(reducedTransparency.allowsBlur)
        XCTAssertTrue(reducedTransparency.usesOpaqueSurfaces)

        XCTAssertFalse(fullyReduced.allowsContinuousMotion)
        XCTAssertFalse(fullyReduced.allowsParallax)
        XCTAssertFalse(fullyReduced.allowsBlur)
        XCTAssertTrue(fullyReduced.usesOpaqueSurfaces)
    }

    func testAccessibilityMotionPolicyRejectsStaleOrHiddenDelayedCommits() {
        let policy = AreaMatrixAccessibilityMotionPolicy()

        XCTAssertTrue(policy.allowsDelayedAnimationCommit(
            generation: 3,
            currentGeneration: 3,
            isVisible: true
        ))
        XCTAssertFalse(policy.allowsDelayedAnimationCommit(
            generation: 2,
            currentGeneration: 3,
            isVisible: true
        ))
        XCTAssertFalse(policy.allowsDelayedAnimationCommit(
            generation: 3,
            currentGeneration: 3,
            isVisible: false
        ))
        XCTAssertFalse(AreaMatrixAccessibilityMotionPolicy(reduceMotion: true).allowsDelayedAnimationCommit(
            generation: 3,
            currentGeneration: 3,
            isVisible: true
        ))
    }
}
