@testable import AreaMatrix
import XCTest

final class SyncConflictEntryPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["C4-15"]

    func testS4X03DeclaresOnlyC415Boundary() {
        XCTAssertEqual(Self.declaredCapabilities, ["C4-15"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.detectSyncConflicts))
    }

    @MainActor
    func testS4X03LoadsNeedsReviewConflictsFromCoreDetector() async {
        let reviewable = SyncConflictSnapshot.s4x01Fixture(
            conflictID: "entry-review",
            primaryPath: "docs/review.pdf"
        )
        let detector = S4X01RecordingSyncConflictDetector(result: .success([
            .s4x01Fixture(conflictID: "entry-resolved", status: .resolved),
            reviewable
        ]))
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/s4x03-repo",
            conflictDetector: detector,
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.loadIfNeeded()
        let requests = await detector.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/s4x03-repo"])
        XCTAssertEqual(model.snapshot?.conflicts, [reviewable])
        XCTAssertEqual(model.snapshot?.count, 1)
        XCTAssertTrue(model.isBannerVisible)
    }

    @MainActor
    func testS4X03LaterOnlyDismissesBannerAndKeepsNeedsReviewList() async {
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/s4x03-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([
                .s4x01Fixture(conflictID: "entry-later")
            ])),
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.loadIfNeeded()
        model.dismissBanner()

        XCTAssertFalse(model.isBannerVisible)
        XCTAssertEqual(model.snapshot?.conflicts.count, 1)
        XCTAssertEqual(model.snapshot?.conflicts.first?.status, .needsReview)
    }

    @MainActor
    func testS4X03ReviewRouteUsesStableConflictIDFromCore() async {
        let conflict = SyncConflictSnapshot.s4x01Fixture(
            conflictID: "entry-route",
            primaryPath: "docs/route.pdf"
        )
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/s4x03-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([conflict])),
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.loadIfNeeded()
        let route = model.reviewRoute(for: conflict)

        XCTAssertEqual(route, SyncConflictReviewRoute(
            repoPath: "/tmp/s4x03-repo",
            conflictID: "entry-route",
            primaryPath: "docs/route.pdf"
        ))
    }

    @MainActor
    func testS4X03MissingConflictIDDisablesReviewAndShowsRepairCopy() async {
        let conflict = SyncConflictSnapshot.s4x01Fixture(conflictID: "   ")
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/s4x03-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([conflict])),
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.loadIfNeeded()

        XCTAssertNil(conflict.normalizedConflictID)
        XCTAssertNil(model.snapshot?.firstReviewableConflict)
        XCTAssertEqual(model.snapshot?.conflicts, [conflict])
        XCTAssertNil(model.reviewRoute(for: conflict).conflictID)
    }

    @MainActor
    func testS4X03ErrorStateMapsCoreErrorAndKeepsRetryVisible() async {
        let mapper = S4X01RecordingErrorMapper(mapping: .s4x01Mapping(
            kind: .db,
            rawContext: "conflict state locked"
        ))
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/s4x03-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .failure(CoreError.Db(
                message: "conflict state locked"
            ))),
            errorMapper: mapper
        )

        await model.loadIfNeeded()
        let body = s4x01MirrorDescription(of: SyncConflictEntryPanel(model: model, onReview: { _ in }).body)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "conflict state locked")])
        XCTAssertTrue(body.contains(SyncConflictEntryAccessibilityID.error))
        XCTAssertTrue(body.contains(SyncConflictEntryCopy.retryAction))
    }

    @MainActor
    func testS4X03DetailBannerRoutesSelectedFileToConflictReview() {
        let conflict = SyncConflictSnapshot.s4x01Fixture(
            conflictID: "entry-detail",
            primaryPath: "docs/report.pdf"
        )
        let model = SyncConflictEntryModel(
            repoPath: "/tmp/s4x03-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([conflict])),
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )
        let file = FileEntrySnapshot.s4x01Fixture(
            id: 42,
            path: "docs/report.pdf",
            currentName: "report.pdf"
        )

        let route = model.reviewRoute(for: conflict)
        let body = s4x01MirrorDescription(of: SyncConflictDetailBanner(
            conflict: conflict,
            onReview: { _ in }
        ).body)

        XCTAssertTrue(conflict.matchesSyncConflictEntry(file: file))
        XCTAssertEqual(route.conflictID, "entry-detail")
        XCTAssertTrue(body.contains(SyncConflictEntryCopy.detailTitle))
        XCTAssertTrue(body.contains(SyncConflictEntryAccessibilityID.detailBanner))
    }
}
