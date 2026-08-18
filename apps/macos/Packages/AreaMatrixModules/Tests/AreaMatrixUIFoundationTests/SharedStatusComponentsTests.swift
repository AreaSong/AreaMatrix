@testable import AreaMatrixUIFoundation
import SwiftUI
import XCTest

final class SharedStatusComponentsTests: XCTestCase {
    func testStepHeaderComponentsExposeStableConstructionContracts() {
        _ = AreaMatrixStepHeaderIcon(systemImage: "folder", tint: .blue)
        _ = AreaMatrixStepHeader(
            systemImage: "folder",
            tint: .blue,
            title: "Repository",
            subtitle: "Choose a folder"
        )
    }

    func testSharedStatusComponentsExposeStableConstructionContracts() {
        _ = NeutralCapsuleChip { Text("chip") }
        _ = NeutralSummaryPanel { Text("summary") }
        _ = ReasonStatusCard(
            badge: "state",
            badgeTint: .blue,
            accessibilityIdentifier: "status",
            badgeAccessibilityIdentifier: "status.badge",
            title: { Text("title") },
            message: { Text("message") },
            actions: { EmptyView() }
        )
        _ = TintedCapsuleBadge(title: "badge", tint: .blue)
        _ = TintedStatusBanner(tint: .blue) { Text("banner") }
        _ = TintedOutlinedStatusBanner(tint: .blue) { Text("outlined") }
        _ = AreaMatrixInlineErrorBanner(
            message: "Something failed",
            detail: "Details",
            recovery: "Try again",
            tint: .red
        ) { EmptyView() }
    }

    func testLucideIconExposesStableConstructionContract() {
        _ = AreaMatrixLucideIcon(name: .folderOpen, lineWidth: 1.5)
    }

    func testEmptyStateExposesStableConstructionContract() {
        _ = AreaMatrixEmptyStateView(
            systemImage: "tray",
            title: "Empty",
            message: "Nothing here",
            primaryTitle: "Add",
            primaryAction: {}
        )
    }
}
