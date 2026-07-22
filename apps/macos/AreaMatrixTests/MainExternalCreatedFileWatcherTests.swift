@testable import AreaMatrix
import Foundation
import XCTest

final class MainExternalCreatedFileWatcherTests: XCTestCase {
    @MainActor
    func testRelayDrainKeepsBacklogOrderAndOtherRepositoryWindows() throws {
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()
        let repoA = "/tmp/repo-a"
        let repoB = "/tmp/repo-b"
        let a100 = try XCTUnwrap(try MainExternalSyncWindow(
            repoPath: repoA,
            events: [XCTUnwrap(MainExternalCreatedFileEvent(relativePath: "docs/a.pdf", fsEventID: 100))],
            cursorWatermark: 100
        ))
        let b101 = try XCTUnwrap(try MainExternalSyncWindow(
            repoPath: repoB,
            events: [XCTUnwrap(MainExternalCreatedFileEvent(relativePath: "docs/b.pdf", fsEventID: 101))],
            cursorWatermark: 101
        ))
        let a102 = try XCTUnwrap(try MainExternalSyncWindow(
            repoPath: repoA,
            events: [XCTUnwrap(MainExternalCreatedFileEvent(relativePath: "docs/c.pdf", fsEventID: 102))],
            cursorWatermark: 102
        ))
        AreaMatrixExternalCreatedFileRelay.publish(a100)
        AreaMatrixExternalCreatedFileRelay.publish(b101)
        AreaMatrixExternalCreatedFileRelay.publish(a102)

        XCTAssertEqual(
            AreaMatrixExternalCreatedFileRelay.takePendingWindows(matchingRepoPath: repoA),
            [a100, a102]
        )
        XCTAssertEqual(
            AreaMatrixExternalCreatedFileRelay.takePendingWindows(matchingRepoPath: repoB),
            [b101]
        )
    }

    @MainActor
    func testSameWatermarkMergesFilteredAckWithBusinessWindow() throws {
        _ = AreaMatrixExternalCreatedFileRelay.takePendingSignals()
        let repoPath = "/tmp/repo-same-watermark"
        let event = try XCTUnwrap(MainExternalCreatedFileEvent(
            relativePath: "docs/business.pdf",
            fsEventID: 900,
            cursorWatermark: 900
        ))
        let filtered = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: repoPath,
            events: [],
            cursorWatermark: 900
        ))
        let business = try XCTUnwrap(MainExternalSyncWindow(
            repoPath: repoPath,
            events: [event],
            cursorWatermark: 900
        ))

        AreaMatrixExternalCreatedFileRelay.publish(filtered)
        AreaMatrixExternalCreatedFileRelay.publish(business)
        XCTAssertEqual(
            AreaMatrixExternalCreatedFileRelay.takePendingWindows(matchingRepoPath: repoPath),
            [business]
        )

        let opening = RepositoryOpeningResult.detailMetaFixture(repoPath: repoPath, files: [])
        let shell = makeShellMainListFixture(opening: opening, model: makeShellOnboardingModel())
        XCTAssertTrue(shell.model.handleExternalSyncWindows([filtered, business]))
        XCTAssertEqual(shell.model.externalSyncWindows(for: opening), [business])
    }

    @MainActor
    func testPendingQueueKeepsDistinctPathsAndLatestPathEvent() throws {
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            model: makeShellOnboardingModel()
        )
        let signals = try [
            XCTUnwrap(MainExternalCreatedFileSignal(
                repoPath: "/tmp/repo",
                relativePath: "docs/second.pdf",
                fsEventID: 320,
                cursorWatermark: 330
            )),
            XCTUnwrap(MainExternalCreatedFileSignal(
                repoPath: "/tmp/repo",
                relativePath: "docs/first.pdf",
                fsEventID: 310,
                cursorWatermark: 330
            )),
            XCTUnwrap(MainExternalCreatedFileSignal(
                kind: .modified,
                repoPath: "/tmp/repo",
                relativePath: "docs/first.pdf",
                fsEventID: 330,
                cursorWatermark: 330
            ))
        ]

        XCTAssertTrue(fixture.model.handleExternalCreatedFiles(signals))
        XCTAssertEqual(fixture.model.externalCreatedEvents(for: fixture.opening), [
            MainExternalCreatedFileEvent(
                kind: .created,
                relativePath: "docs/second.pdf",
                fsEventID: 320,
                cursorWatermark: 330
            ),
            MainExternalCreatedFileEvent(
                kind: .created,
                relativePath: "docs/first.pdf",
                fsEventID: 330
            )
        ])
    }

    @MainActor
    func testRescanRecoveryClearsPendingEventsAndRoutesToRepair() throws {
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            model: makeShellOnboardingModel()
        )
        let signal = try XCTUnwrap(MainExternalCreatedFileSignal(
            repoPath: "/tmp/repo",
            relativePath: "docs/pending.pdf",
            fsEventID: 350
        ))
        XCTAssertTrue(fixture.model.handleExternalCreatedFile(signal))

        fixture.model.handleExternalWatcherRecovery(MainExternalWatcherRecoveryRequest(
            kind: .rescanRequired,
            repoPath: "/tmp/repo",
            resumeEventID: 351,
            reason: "history unavailable"
        ))

        XCTAssertEqual(fixture.model.externalCreatedEvents(for: fixture.opening), [])
        XCTAssertEqual(fixture.model.pendingWatcherRescanSeed?.repoPath, "/tmp/repo")
        XCTAssertEqual(fixture.model.pendingWatcherRescanSeed?.eventID, 351)
        guard case let .dbRepairConfirm(route) = fixture.model.route else {
            return XCTFail("Expected watcher recovery to route to repository repair")
        }
        XCTAssertEqual(route.repoPath, "/tmp/repo")
    }

    @MainActor
    func testRootChangedRecoveryRoutesToRepositoryReconnectError() {
        let fixture = makeShellMainListFixture(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: []),
            model: makeShellOnboardingModel()
        )

        fixture.model.handleExternalWatcherRecovery(MainExternalWatcherRecoveryRequest(
            kind: .rootChanged,
            repoPath: "/tmp/repo",
            resumeEventID: nil,
            reason: "root moved"
        ))

        guard case let .mainRepoError(repoPath, mapping) = fixture.model.route else {
            return XCTFail("Expected watcher root change to route to repository error")
        }
        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(mapping?.kind, .fileNotFound)
        XCTAssertEqual(mapping?.recoverability, .userActionRequired)
    }

    func testInFlightTrackerUsesReferenceCountsAndTTL() async {
        let tracker = InFlightFileChangeTracker(ttl: 0.02)
        await tracker.mark(repoPath: "/tmp/repo/./", relativePath: " docs/file.pdf ")
        await tracker.mark(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        await tracker.unmark(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")

        let remainsInFlight = await tracker.contains(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        XCTAssertTrue(remainsInFlight)
        await tracker.unmark(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        let remainsDuringGrace = await tracker.contains(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        XCTAssertTrue(remainsDuringGrace)
        try? await Task.sleep(for: .milliseconds(40))
        let expiredAfterGrace = await tracker.contains(repoPath: "/tmp/repo", relativePath: "docs/file.pdf")
        XCTAssertFalse(expiredAfterGrace)

        let expiredTracker = InFlightFileChangeTracker(ttl: 0)
        await expiredTracker.mark(repoPath: "/tmp/repo", relativePath: "docs/expired.pdf")
        let expired = await expiredTracker.contains(repoPath: "/tmp/repo", relativePath: "docs/expired.pdf")
        XCTAssertFalse(expired)
    }
}
