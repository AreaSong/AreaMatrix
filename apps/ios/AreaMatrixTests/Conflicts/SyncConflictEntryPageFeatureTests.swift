@testable import AreaMatrixIOS
import XCTest

@MainActor
final class SyncConflictEntryPageFeatureTests: XCTestCase {
    func testS4X03LoadsNeedsReviewConflictsFromC415CoreBridge() async {
        let reviewable = SyncConflictEntryConflict.fixture(
            conflictID: "ios-review",
            primaryPath: "docs/review.pdf"
        )
        let bridge = RecordingSyncConflictEntryCoreBridge(conflicts: [
            .fixture(conflictID: "ios-resolved", status: .resolved),
            reviewable
        ])
        let model = SyncConflictEntryViewModel(repoPath: "/tmp/Repo", bridge: bridge)

        await model.loadIfNeeded()
        let repoPaths = await bridge.repoPaths()

        XCTAssertEqual(repoPaths, ["/tmp/Repo"])
        XCTAssertEqual(model.reviewableConflicts, [reviewable])
        XCTAssertTrue(model.isBannerVisible)
    }

    func testS4X03LaterDoesNotClearNeedsReviewList() async {
        let bridge = RecordingSyncConflictEntryCoreBridge(conflicts: [
            .fixture(conflictID: "ios-later")
        ])
        let model = SyncConflictEntryViewModel(repoPath: "/tmp/Repo", bridge: bridge)

        await model.loadIfNeeded()
        model.dismissBanner()

        XCTAssertFalse(model.isBannerVisible)
        XCTAssertEqual(model.reviewableConflicts.map(\.conflictID), ["ios-later"])
        XCTAssertEqual(model.reviewableConflicts.first?.status, .needsReview)
    }

    func testS4X03ReviewRouteUsesStableConflictID() async {
        let conflict = SyncConflictEntryConflict.fixture(
            conflictID: "ios-route",
            primaryPath: "docs/route.pdf"
        )
        let bridge = RecordingSyncConflictEntryCoreBridge(conflicts: [conflict])
        let model = SyncConflictEntryViewModel(repoPath: "/tmp/Repo", bridge: bridge)

        await model.loadIfNeeded()

        XCTAssertEqual(model.reviewRoute(for: conflict), SyncConflictEntryReviewRoute(
            repoPath: "/tmp/Repo",
            conflictID: "ios-route",
            primaryPath: "docs/route.pdf"
        ))
    }

    func testS4X03DetailEntryMatchesAffectedFile() async {
        let conflict = SyncConflictEntryConflict.fixture(
            conflictID: "ios-detail",
            primaryPath: "docs/current.pdf",
            affectedFiles: [
                .fixture(path: "docs/archive.pdf", fileID: 42)
            ]
        )
        let bridge = RecordingSyncConflictEntryCoreBridge(conflicts: [conflict])
        let model = SyncConflictEntryViewModel(repoPath: "/tmp/Repo", bridge: bridge)

        await model.loadIfNeeded()

        XCTAssertEqual(model.detailConflict(fileID: 42, path: "docs/archive.pdf"), conflict)
    }

    func testS4X03MapsCoreLoadFailureToRetryableError() async {
        let bridge = RecordingSyncConflictEntryCoreBridge(error: .database("metadata locked"))
        let model = SyncConflictEntryViewModel(repoPath: "/tmp/Repo", bridge: bridge)

        await model.loadIfNeeded()

        guard case let .failed(error) = model.state else {
            return XCTFail("expected failed state")
        }
        XCTAssertEqual(error.message, SyncConflictEntryCopy.error)
        XCTAssertEqual(error.recovery, "Try again after the repository database is available.")
    }

    func testS4X03TopLevelTakeoverRoutesReviewAction() throws {
        let appSource = try Self.readSource("../../AreaMatrix/App/AreaMatrixIOSApp.swift")
        let routeViewSource = try Self.readSource(
            "../../AreaMatrix/Features/Conflicts/SyncConflictReviewRouteView.swift"
        )

        XCTAssertTrue(appSource.contains("@State private var pendingSyncConflictReviewRoute"))
        XCTAssertTrue(appSource.contains("onOpenSyncConflictReview: openSyncConflictReview"))
        XCTAssertTrue(appSource.contains(".navigationDestination(item: $pendingSyncConflictReviewRoute)"))
        XCTAssertTrue(appSource.contains("SyncConflictReviewRouteView(route: route)"))
        XCTAssertTrue(routeViewSource.contains("S4-X-01-C4-15-ios-review-route"))
        XCTAssertFalse(routeViewSource.contains("resolveSyncConflict"))
        XCTAssertFalse(routeViewSource.contains("previewSyncConflictResolution"))
    }

    func testS4X03ConnectRoutePassesReviewHandlerToMobileLibrary() throws {
        let connectSource = try Self.readSource("../../AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift")

        XCTAssertTrue(connectSource.contains("@State private var pendingSyncConflictReviewRoute"))
        XCTAssertTrue(connectSource.contains("onOpenSyncConflictReview: openSyncConflictReview"))
        XCTAssertTrue(connectSource.contains("onOpenSyncConflictReview: onOpenSyncConflictReview"))
        XCTAssertTrue(connectSource.contains("SyncConflictReviewRouteView(route: route)"))
        XCTAssertTrue(connectSource.contains("pendingSyncConflictReviewRoute = route"))
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

private actor RecordingSyncConflictEntryCoreBridge: SyncConflictEntryCoreBridge {
    private var requests: [String] = []
    private let conflicts: [SyncConflictEntryConflict]
    private let error: SyncConflictEntryError?

    init(
        conflicts: [SyncConflictEntryConflict] = [],
        error: SyncConflictEntryError? = nil
    ) {
        self.conflicts = conflicts
        self.error = error
    }

    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictEntryConflict] {
        requests.append(repoPath)
        if let error {
            throw error
        }
        return conflicts
    }

    func repoPaths() -> [String] {
        requests
    }
}

private extension SyncConflictEntryConflict {
    static func fixture(
        conflictID: String,
        status: SyncConflictEntryStatus = .needsReview,
        primaryPath: String = "docs/file.pdf",
        affectedFiles: [SyncConflictEntryAffectedFile] = []
    ) -> SyncConflictEntryConflict {
        SyncConflictEntryConflict(
            conflictID: conflictID,
            conflictType: .sameNameDifferentContent,
            severity: .high,
            status: status,
            primaryPath: primaryPath,
            affectedFiles: affectedFiles,
            versionCount: 2,
            sourceProvider: "iCloud",
            detectedAt: 1_700_000_000,
            summary: "Two versions need review."
        )
    }
}

private extension SyncConflictEntryAffectedFile {
    static func fixture(path: String, fileID: Int64?) -> SyncConflictEntryAffectedFile {
        SyncConflictEntryAffectedFile(
            path: path,
            fileID: fileID,
            role: .conflictCopy,
            sizeBytes: 100,
            modifiedAt: 1_700_000_000,
            hashSha256: "hash",
            sourcePlatform: "iOS"
        )
    }
}
