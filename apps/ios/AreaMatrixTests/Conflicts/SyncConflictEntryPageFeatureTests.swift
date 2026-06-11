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
        XCTAssertTrue(routeViewSource.contains("previewSyncConflictResolution"))
        XCTAssertTrue(routeViewSource.contains("resolveSyncConflict"))
        XCTAssertTrue(routeViewSource.contains("S4-X-09-C4-21-ios-replace-confirm"))
    }

    func testS4X09ReviewRoutePreviewsConfirmsAndAppliesReplace() async {
        let route = SyncConflictEntryReviewRoute(
            repoPath: "/tmp/Repo",
            conflictID: "ios-replace",
            primaryPath: "docs/existing.pdf"
        )
        let bridge = RecordingSyncConflictEntryCoreBridge()
        let model = SyncConflictReviewRouteViewModel(route: route, bridge: bridge)

        await model.loadPreviewIfNeeded()
        model.setReplaceAcknowledged(true)
        await model.applyReplace()

        let previewRequests = await bridge.previewRequests()
        let resolveRequests = await bridge.resolveRequests()

        XCTAssertEqual(previewRequests, [
            SyncConflictPreviewRequest(
                repoPath: "/tmp/Repo",
                conflictID: "ios-replace",
                resolution: .useIncoming
            )
        ])
        XCTAssertEqual(resolveRequests.first?.request, SyncConflictResolutionRequest(
            strategy: .useIncoming,
            previewToken: "ios-preview-token",
            replaceConfirmed: true,
            replaceConfirmationID: "S4-X-09-C4-21-ios-replace-ios-preview-token"
        ))
        XCTAssertEqual(model.result?.status, .resolved)
        XCTAssertNil(model.error)
    }

    func testS4X09ReviewRouteKeepsPreviewFailureRetryable() async {
        let route = SyncConflictEntryReviewRoute(
            repoPath: "/tmp/Repo",
            conflictID: "ios-preview-failure",
            primaryPath: "docs/existing.pdf"
        )
        let bridge = RecordingSyncConflictEntryCoreBridge(previewError: .permissionDenied("Trash unavailable"))
        let model = SyncConflictReviewRouteViewModel(route: route, bridge: bridge)

        await model.loadPreviewIfNeeded()

        let previewRequests = await bridge.previewRequests()

        XCTAssertEqual(previewRequests.count, 1)
        XCTAssertNil(model.preview)
        XCTAssertEqual(model.error?.message, "AreaMatrix cannot read conflict metadata")
        XCTAssertFalse(model.canApplyReplace)
    }

    func testS4X03ConnectRoutePassesReviewHandlerToMobileLibrary() throws {
        let connectSource = try Self.readSource("../../AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift")
        let routeSource = try Self.readSource(
            "../../AreaMatrix/Features/Onboarding/ConnectRepositoryRouteDestinationView.swift"
        )

        XCTAssertTrue(connectSource.contains("@State private var pendingSyncConflictReviewRoute"))
        XCTAssertTrue(connectSource.contains("onOpenSyncConflictReview: openSyncConflictReview"))
        XCTAssertTrue(connectSource.contains("SyncConflictReviewRouteView(route: route)"))
        XCTAssertTrue(connectSource.contains("pendingSyncConflictReviewRoute = route"))
        XCTAssertTrue(routeSource.contains("onOpenSyncConflictReview: onOpenSyncConflictReview"))
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
    private var previewRecords: [SyncConflictPreviewRequest] = []
    private var resolveRecords: [SyncConflictResolveRequest] = []
    private let conflicts: [SyncConflictEntryConflict]
    private let error: SyncConflictEntryError?
    private let previewError: SyncConflictEntryError?
    private let resolveError: SyncConflictEntryError?

    init(
        conflicts: [SyncConflictEntryConflict] = [],
        error: SyncConflictEntryError? = nil,
        previewError: SyncConflictEntryError? = nil,
        resolveError: SyncConflictEntryError? = nil
    ) {
        self.conflicts = conflicts
        self.error = error
        self.previewError = previewError
        self.resolveError = resolveError
    }

    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictEntryConflict] {
        requests.append(repoPath)
        if let error {
            throw error
        }
        return conflicts
    }

    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategy
    ) async throws -> SyncConflictResolutionPreviewReport {
        previewRecords.append(SyncConflictPreviewRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            resolution: resolution
        ))
        if let previewError {
            throw previewError
        }
        return .fixture(conflictID: conflictID, resolution: resolution)
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequest
    ) async throws -> SyncConflictResolveReport {
        resolveRecords.append(SyncConflictResolveRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            request: request
        ))
        if let resolveError {
            throw resolveError
        }
        return .fixture(conflictID: conflictID, request: request)
    }

    func repoPaths() -> [String] {
        requests
    }

    func previewRequests() -> [SyncConflictPreviewRequest] {
        previewRecords
    }

    func resolveRequests() -> [SyncConflictResolveRequest] {
        resolveRecords
    }
}

private struct SyncConflictPreviewRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var resolution: SyncConflictResolutionStrategy
}

private struct SyncConflictResolveRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var request: SyncConflictResolutionRequest
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

private extension SyncConflictResolutionPreviewReport {
    static func fixture(
        conflictID: String,
        resolution: SyncConflictResolutionStrategy
    ) -> SyncConflictResolutionPreviewReport {
        SyncConflictResolutionPreviewReport(
            conflictID: conflictID,
            resolution: resolution,
            defaultResolution: .keepBoth,
            statusAfter: .needsReview,
            versionImpacts: [
                SyncConflictVersionImpact(
                    path: "docs/existing.pdf",
                    fileID: 42,
                    role: .existing,
                    willKeep: false,
                    willBeCanonical: false,
                    willRemainUserVisible: false,
                    willMoveToTrash: true,
                    recoveryTarget: "Core safety backup",
                    reason: "Use incoming replaces the existing visible version."
                )
            ],
            keptPaths: [],
            retainedPaths: [],
            plannedTrashPaths: ["docs/existing.pdf"],
            affectedFileIDs: [42],
            canonicalPath: "docs/incoming.pdf",
            changeLogAction: "replace_file",
            destructive: true,
            requiresReplaceConfirmation: true,
            trashRequired: true,
            trashAvailable: true,
            canApply: true,
            blockedReason: nil,
            previewToken: "ios-preview-token",
            replacePlan: SyncConflictReplacePlan(
                oldPath: "docs/existing.pdf",
                newPath: "docs/incoming.pdf",
                oldHashSha256: "old-hash",
                newHashSha256: "new-hash",
                affectedFileID: 42,
                backupTarget: "Core safety backup",
                databaseUpdate: "canonical record will point to incoming file",
                changeLogAction: "replace_file",
                recoveryNote: "Existing file remains available if Core apply fails."
            )
        )
    }
}

private extension SyncConflictResolveReport {
    static func fixture(
        conflictID: String,
        request: SyncConflictResolutionRequest
    ) -> SyncConflictResolveReport {
        SyncConflictResolveReport(
            conflictID: conflictID,
            resolution: request.strategy,
            status: .resolved,
            keptPaths: [],
            retainedPaths: [],
            trashedPaths: ["docs/existing.pdf"],
            affectedFileIDs: [42],
            changeLogAction: "replace_file",
            undoToken: "undo-token",
            resolvedAt: 1_700_000_300
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
