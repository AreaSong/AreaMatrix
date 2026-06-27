@testable import AreaMatrix
import XCTest

final class SyncConflictEntryPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["sync-conflict-detect"]

    func testSyncConflictEntryDeclaresOnlySyncConflictDetectCoreBoundary() {
        XCTAssertEqual(Self.declaredCapabilities, ["sync-conflict-detect"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.detectSyncConflicts))
    }

    @MainActor
    func testSyncConflictEntryLoadsNeedsReviewConflictsFromCoreDetector() async {
        let reviewable = SyncConflictSnapshot.syncConflictReviewFixture(
            conflictID: "entry-review",
            primaryPath: "docs/review.pdf"
        )
        let detector = SyncConflictReviewDetector(result: .success([
            .syncConflictReviewFixture(conflictID: "entry-resolved", status: .resolved),
            reviewable
        ]))
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/syncConflictEntry-repo",
            conflictDetector: detector,
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.loadIfNeeded()
        let requests = await detector.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/syncConflictEntry-repo"])
        XCTAssertEqual(model.snapshot?.conflicts, [reviewable])
        XCTAssertEqual(model.snapshot?.count, 1)
        XCTAssertTrue(model.isBannerVisible)
    }

    @MainActor
    func testSyncConflictEntryLaterOnlyDismissesBannerAndKeepsNeedsReviewList() async {
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/syncConflictEntry-repo",
            conflictDetector: SyncConflictReviewDetector(result: .success([
                .syncConflictReviewFixture(conflictID: "entry-later")
            ])),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.loadIfNeeded()
        model.dismissBanner()

        XCTAssertFalse(model.isBannerVisible)
        XCTAssertEqual(model.snapshot?.conflicts.count, 1)
        XCTAssertEqual(model.snapshot?.conflicts.first?.status, .needsReview)
    }

    @MainActor
    func testSyncConflictEntryReviewRouteUsesStableConflictIDFromCore() async {
        let conflict = SyncConflictSnapshot.syncConflictReviewFixture(
            conflictID: "entry-route",
            primaryPath: "docs/route.pdf"
        )
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/syncConflictEntry-repo",
            conflictDetector: SyncConflictReviewDetector(result: .success([conflict])),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.loadIfNeeded()
        let route = model.reviewRoute(for: conflict)

        XCTAssertEqual(route, SyncConflictReviewRoute(
            repoPath: "/tmp/syncConflictEntry-repo",
            conflictID: "entry-route",
            primaryPath: "docs/route.pdf"
        ))
    }

    @MainActor
    func testSyncConflictEntryMissingConflictIDDisablesReviewAndShowsRepairCopy() async {
        let conflict = SyncConflictSnapshot.syncConflictReviewFixture(conflictID: "   ")
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/syncConflictEntry-repo",
            conflictDetector: SyncConflictReviewDetector(result: .success([conflict])),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.loadIfNeeded()

        XCTAssertNil(conflict.normalizedConflictID)
        XCTAssertNil(model.snapshot?.firstReviewableConflict)
        XCTAssertEqual(model.snapshot?.conflicts, [conflict])
        XCTAssertNil(model.reviewRoute(for: conflict).conflictID)
    }

    @MainActor
    func testSyncConflictEntryErrorStateMapsCoreErrorAndKeepsRetryVisible() async {
        let mapper = SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping(
            kind: .db,
            rawContext: "conflict state locked"
        ))
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/syncConflictEntry-repo",
            conflictDetector: SyncConflictReviewDetector(result: .failure(CoreError.Db(
                message: "conflict state locked"
            ))),
            errorMapper: mapper
        )

        await model.loadIfNeeded()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "conflict state locked")])
        assertTestMirrorDescription(of: SyncConflictEntryPanel(model: model, onReview: { _ in
        }).body, contains: [
            SyncConflictEntryAccessibilityID.error,
            SyncConflictEntryCopy.retryAction
        ])
    }

    @MainActor
    func testSyncConflictEntryDetailBannerRoutesSelectedFileToConflictReview() {
        let conflict = SyncConflictSnapshot.syncConflictReviewFixture(
            conflictID: "entry-detail",
            primaryPath: "docs/report.pdf"
        )
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/syncConflictEntry-repo",
            conflictDetector: SyncConflictReviewDetector(result: .success([conflict])),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )
        let file = FileEntrySnapshot.syncConflictReviewFixture(
            id: 42,
            path: "docs/report.pdf",
            currentName: "report.pdf"
        )

        let route = model.reviewRoute(for: conflict)
        let body = SyncConflictDetailBanner(
            conflict: conflict,
            onReview: { _ in }
        ).body

        XCTAssertTrue(conflict.matchesSyncConflictEntry(file: file))
        XCTAssertEqual(route.conflictID, "entry-detail")
        assertTestMirrorDescription(of: body, contains: [
            SyncConflictEntryCopy.detailTitle,
            SyncConflictEntryAccessibilityID.detailBanner
        ])
    }
}
