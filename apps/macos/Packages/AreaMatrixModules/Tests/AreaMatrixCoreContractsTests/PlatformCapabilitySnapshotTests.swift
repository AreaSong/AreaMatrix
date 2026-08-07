@testable import AreaMatrixCoreContracts
import XCTest

final class PlatformCapabilitySnapshotTests: XCTestCase {
    func testPlatformIdentifiersAndStatusesPreserveStableWireValues() {
        XCTAssertEqual(PlatformIdSnapshot.macos.rawValue, "macOS")
        XCTAssertEqual(PlatformIdSnapshot.unknown.rawValue, "Unknown")
        XCTAssertEqual(PlatformCapabilityStatusSnapshot.notAvailable.rawValue, "Not available")
    }

    func testUnknownSnapshotDisablesEveryCapabilityWithoutDroppingReason() {
        let snapshot = PlatformCapabilitiesSnapshot.unknown(
            platform: .macos,
            appVersion: "1.2.3",
            reason: "permission unavailable"
        )

        XCTAssertEqual(snapshot.platform, .macos)
        XCTAssertEqual(snapshot.appVersion, "1.2.3")
        for support in [
            snapshot.watcher,
            snapshot.trash,
            snapshot.shareExtension,
            snapshot.cloudPlaceholder,
            snapshot.securityBookmark
        ] {
            XCTAssertEqual(support.status, .unknown)
            XCTAssertFalse(support.uiEnabled)
            XCTAssertFalse(support.requiresPermission)
            XCTAssertEqual(support.reason, "permission unavailable")
        }
    }

    func testSnapshotIsValueStableAndHashableAtCapabilityBoundary() {
        let support = PlatformCapabilitySupportSnapshot(
            status: .limited,
            uiEnabled: false,
            requiresPermission: true,
            reason: "needs approval"
        )
        let snapshot = PlatformCapabilitiesSnapshot(
            platform: .ios,
            appVersion: "2",
            watcher: support,
            trash: support,
            shareExtension: support,
            cloudPlaceholder: support,
            securityBookmark: support
        )

        XCTAssertEqual(snapshot, snapshot)
        XCTAssertEqual(Set([support, support]).count, 1)
    }
}
