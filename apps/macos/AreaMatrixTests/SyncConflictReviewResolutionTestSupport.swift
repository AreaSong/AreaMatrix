@testable import AreaMatrix
import Foundation
import XCTest

actor SyncConflictReviewResolver: CoreSyncConflictResolving {
    private let previewResults: [
        SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>
    ]
    private let resolveResult: Result<SyncConflictResolveReportSnapshot, Error>
    private var previewRequests: [SyncConflictPreviewRequest] = []
    private var resolveRequests: [SyncConflictResolveRequest] = []

    init(
        previewResults: [SyncConflictResolutionStrategySnapshot: Result<SyncConflictResolutionPreviewSnapshot, Error>],
        resolveResult: Result<SyncConflictResolveReportSnapshot, Error> = .success(.syncConflictReviewResolveFixture())
    ) {
        self.previewResults = previewResults
        self.resolveResult = resolveResult
    }

    func previewSyncConflictResolution(
        repoPath: String,
        conflictID: String,
        resolution: SyncConflictResolutionStrategySnapshot
    ) async throws -> SyncConflictResolutionPreviewSnapshot {
        previewRequests.append(SyncConflictPreviewRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            resolution: resolution
        ))
        return try (previewResults[resolution] ?? .success(.syncConflictReviewPreviewFixture(resolution: resolution)))
            .get()
    }

    func resolveSyncConflict(
        repoPath: String,
        conflictID: String,
        request: SyncConflictResolutionRequestSnapshot
    ) async throws -> SyncConflictResolveReportSnapshot {
        resolveRequests.append(SyncConflictResolveRequest(
            repoPath: repoPath,
            conflictID: conflictID,
            request: request
        ))
        return try resolveResult.get()
    }

    func recordedPreviewRequests() -> [SyncConflictPreviewRequest] {
        previewRequests
    }

    func recordedResolveRequests() -> [SyncConflictResolveRequest] {
        resolveRequests
    }
}

actor SyncConflictReviewDetector: CoreSyncConflictDetecting {
    private let result: Result<[SyncConflictSnapshot], Error>
    private var requests: [String] = []

    init(result: Result<[SyncConflictSnapshot], Error>) {
        self.result = result
    }

    func detectSyncConflicts(repoPath: String) async throws -> [SyncConflictSnapshot] {
        requests.append(repoPath)
        return try result.get()
    }

    func recordedRequests() -> [String] {
        requests
    }
}

struct SyncConflictReplaceContext {
    let detector: SyncConflictReviewDetector
    let resolver: SyncConflictReviewResolver
    let model: SyncConflictReviewModel
    let view: SyncConflictReviewView
    let resolvedReports: SyncConflictReplaceReports
}

final class SyncConflictReplaceReports {
    var reports: [SyncConflictResolveReportSnapshot] = []
}

@MainActor
func makeSyncConflictReplaceContext() -> SyncConflictReplaceContext {
    let detector = SyncConflictReviewDetector(result: .success([.syncConflictReviewFixture()]))
    let resolver = SyncConflictReviewResolver(
        previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture()),
            .useIncoming: .success(.syncConflictReviewPreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                blockedReason: "Replace confirmation required",
                previewToken: "preview-token-use-incoming"
            ))
        ],
        resolveResult: .success(.syncConflictReviewResolveFixture(resolution: .useIncoming))
    )
    let model = SyncConflictReviewModel(
        repoPath: "/tmp/syncConflictReview-repo",
        conflictDetector: detector,
        conflictResolver: resolver,
        errorMapper: StaticCoreErrorMapper(mapping: .syncConflictReviewMapping())
    )
    let resolvedReports = SyncConflictReplaceReports()
    let view = SyncConflictReviewView(
        model: model,
        onBackToNeedsReview: {},
        onClose: {},
        onResolved: { resolvedReports.reports.append($0) }
    )
    return SyncConflictReplaceContext(
        detector: detector,
        resolver: resolver,
        model: model,
        view: view,
        resolvedReports: resolvedReports
    )
}

@MainActor
func assertSyncConflictReplaceResolutionBlocksUnconfirmedApply(
    model: SyncConflictReviewModel,
    unresolvedRequests: [SyncConflictResolveRequest],
    panelBody: Any
) {
    XCTAssertEqual(unresolvedRequests, [])
    XCTAssertFalse(model.canApplyResolution)
    XCTAssertTrue(model.canConfirmReplacePlan)
    assertTestMirrorDescription(of: panelBody, contains: [
        "Confirm Replace",
        "Old file path",
        "Old version will be kept at",
        "Affected record",
        "Change log",
        "Recovery note"
    ])
}

@MainActor
func assertSyncConflictReplaceResolutionApplyExit(
    model: SyncConflictReviewModel,
    detectRequests: [String],
    previewRequests: [SyncConflictPreviewRequest],
    resolveRequests: [SyncConflictResolveRequest],
    resolvedReports: [SyncConflictResolveReportSnapshot]
) {
    XCTAssertEqual(detectRequests, ["/tmp/syncConflictReview-repo"])
    XCTAssertEqual(previewRequests.map(\.resolution), [.keepBoth, .useIncoming])
    XCTAssertEqual(resolveRequests, [.useIncomingConfirmedRequest])
    XCTAssertEqual(resolvedReports, [.syncConflictReviewResolveFixture(resolution: .useIncoming)])
    XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
}
