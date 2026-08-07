@testable import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SharedFeatureCardComponentsTests: XCTestCase {
    func testFeatureCardComponentsExposeStableConstructionContracts() {
        let spec = AreaMatrixFeatureCardSpec(
            id: "welcome",
            icon: .folder,
            title: "Welcome",
            description: "Choose a repository",
            accentColor: .teal,
            entranceDelay: 0.2
        )

        _ = AreaMatrixFeatureCardGroup(
            cards: [spec],
            activeID: "welcome",
            onHoverChanged: { _, _ in }
        )
        _ = AreaMatrixFeatureCard(
            icon: spec.icon,
            title: spec.title,
            description: spec.description,
            accentColor: spec.accentColor,
            isHovered: false,
            entranceDelay: spec.entranceDelay,
            anyCardHovered: false,
            onHoverChanged: { _ in }
        )
    }
}
