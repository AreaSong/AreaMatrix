@testable import AreaMatrix
import Combine
import Foundation
import XCTest

final class AppCommandRouterTests: XCTestCase {
    @MainActor
    func testPublishesTypedCommands() {
        let router = AppCommandRouter()
        var received: [AppCommandRouter.Command] = []
        let cancellable = router.commands.sink { received.append($0) }

        router.publish(.importRequested)
        router.publish(.settingsRequested)

        XCTAssertEqual(received, [.importRequested, .settingsRequested])
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testDockOpenRequestsAreQueuedUntilDrained() {
        let router = AppCommandRouter()
        let firstURL = URL(fileURLWithPath: "/tmp/first.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/second.pdf")

        router.publishDockOpen([firstURL])
        router.publishDockOpen([secondURL])

        XCTAssertEqual(router.takePendingDockOpenBatches(), [[firstURL], [secondURL]])
        XCTAssertEqual(router.takePendingDockOpenBatches(), [])
    }

    @MainActor
    func testExternalSyncWindowsMergeByRepositoryAndWatermark() throws {
        let router = AppCommandRouter()
        let repoPath = "/tmp/router-repo"
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: "docs/report.pdf",
            fsEventID: 100,
            cursorWatermark: 100
        ))
        let filtered = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: repoPath,
            events: [],
            cursorWatermark: 100
        ))
        let business = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: repoPath,
            events: [event],
            cursorWatermark: 100
        ))

        router.publishExternalSync(filtered)
        router.publishExternalSync(business)

        XCTAssertEqual(
            router.takePendingExternalWindows(matchingRepoPath: repoPath),
            [business]
        )
    }

    @MainActor
    func testExternalSyncDrainFiltersRepositoryAndCanDrainAll() throws {
        let router = AppCommandRouter()
        let repoA = try makeWindow(repoPath: "/tmp/router-a", path: "docs/a.pdf", cursor: 200)
        let repoB = try makeWindow(repoPath: "/tmp/router-b", path: "docs/b.pdf", cursor: 201)

        router.publishExternalSync(repoB)
        router.publishExternalSync(repoA)

        XCTAssertEqual(router.takePendingExternalWindows(matchingRepoPath: "/tmp/router-a"), [repoA])
        XCTAssertEqual(router.takePendingExternalWindows(matchingRepoPath: nil), [repoB])
        XCTAssertEqual(router.takePendingExternalWindows(matchingRepoPath: nil), [])
    }
}

private extension AppCommandRouterTests {
    @MainActor
    func makeWindow(repoPath: String, path: String, cursor: Int64) throws -> MainExternalSyncWindow {
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: path,
            fsEventID: cursor,
            cursorWatermark: cursor
        ))
        return try XCTUnwrap(MainExternalSyncWindow(
            repoPath: repoPath,
            events: [event],
            cursorWatermark: cursor
        ))
    }
}
