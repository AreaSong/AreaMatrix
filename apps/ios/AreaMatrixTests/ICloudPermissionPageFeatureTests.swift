@testable import AreaMatrixIOS
import XCTest

@MainActor
final class ICloudPermissionPageFeatureTests: XCTestCase {
    func testPlaceholderStateRendersRetryRecoveryFromCoreState() {
        let path = "/tmp/Mobile Documents/AreaMatrixRepo"
        let content = ICloudPermissionContent(
            error: .iCloudPlaceholder(path),
            cloudState: .iCloudPlaceholder(path: path)
        )

        XCTAssertEqual(content.title, "File is still in iCloud")
        XCTAssertEqual(content.message, "This file exists in iCloud but is not downloaded on this device yet.")
        XCTAssertEqual(content.status, "Waiting for iCloud download")
        XCTAssertEqual(content.repositoryText, path)
        XCTAssertEqual(content.primaryAction, .tryAgain)
        XCTAssertTrue(content.secondaryActions.contains(.chooseAnotherFolder))
    }

    func testAccessExpiredStateRendersReconnectFolderRecovery() {
        let path = "/tmp/Mobile Documents/AreaMatrixRepo"
        let content = ICloudPermissionContent(
            error: .accessExpired(path),
            cloudState: .iCloudAccessExpired(path: path)
        )

        XCTAssertEqual(content.title, "Repository access expired")
        XCTAssertEqual(content.status, "Access expired")
        XCTAssertEqual(content.repositoryText, path)
        XCTAssertEqual(content.primaryAction, .reconnectFolder)
        XCTAssertTrue(content.secondaryActions.contains(.chooseAnotherFolder))
        XCTAssertTrue(content.secondaryActions.contains(.openSettings))
    }

    func testPermissionDeniedStateUsesReconnectAndSettingsActions() {
        let path = "/tmp/Mobile Documents/AreaMatrixRepo"
        let content = ICloudPermissionContent(
            error: .permissionDenied(path),
            cloudState: .iCloudPermissionDenied(path: path)
        )

        XCTAssertEqual(content.title, "Repository access expired")
        XCTAssertEqual(content.status, "Permission denied")
        XCTAssertEqual(content.primaryAction, .reconnectFolder)
        XCTAssertTrue(content.secondaryActions.contains(.openSettings))
        XCTAssertTrue(content.safetyText.contains("will not delete, move, or modify"))
    }

    func testUnavailableWithoutRepoStateKeepsExecutableRecoveryActions() {
        let content = ICloudPermissionContent(
            error: .unavailable("iCloud Drive is unavailable."),
            cloudState: nil
        )

        XCTAssertEqual(content.title, "iCloud Drive is not available")
        XCTAssertEqual(content.repositoryText, nil)
        XCTAssertEqual(content.primaryAction, .tryAgain)
        XCTAssertEqual(content.secondaryActions, [.chooseAnotherFolder, .openSettings])
    }
}
