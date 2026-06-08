@testable import AreaMatrix
import XCTest

final class SyncConflictReviewResolutionPageFeatureTests: XCTestCase {
    @MainActor
    func testS4X01C416LoadedViewShowsSummaryVersionsAndDefaultImpact() async throws {
        let conflict = SyncConflictSnapshot.s4x01Fixture()
        let resolver = S4X01RecordingSyncConflictResolver(previewResults: [
            .keepBoth: .success(.s4x01PreviewFixture())
        ])
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([conflict])),
            conflictResolver: resolver,
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await model.load()
        let loadedConflict = try XCTUnwrap(model.conflict)
        let body = s4x01MirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)
        let previewRequests = await resolver.recordedPreviewRequests()

        XCTAssertEqual(loadedConflict.conflictType.displayName, "Same name, different content")
        XCTAssertEqual(loadedConflict.primaryPath, "docs/report.pdf")
        XCTAssertEqual(loadedConflict.affectedFiles.map(\.role.displayName), ["Existing file", "Incoming file"])
        XCTAssertEqual(previewRequests, [
            S4X01SyncConflictPreviewRequest(
                repoPath: "/tmp/s4x01-repo",
                conflictID: "conflict-report",
                resolution: .keepBoth
            )
        ])
        XCTAssertEqual(model.selectedResolution, .keepBoth)
        XCTAssertEqual(model.previewState.preview?.changeLogAction, "conflict_resolved_keep_both")
        XCTAssertTrue(model.canApplyResolution)
        XCTAssertTrue(body.contains(SyncConflictReviewAccessibilityID.resolution))
        XCTAssertTrue(body.contains(SyncConflictReviewAccessibilityID.impact))
        XCTAssertTrue(body.contains(SyncConflictReviewCopy.applyAction))
        XCTAssertEqual(SyncConflictResolutionStrategySnapshot.allCases.map(\.title), [
            "Keep both",
            "Use existing version",
            "Use incoming version"
        ])
        XCTAssertTrue(body.contains("Keep both"))
        XCTAssertTrue(body.contains("conflict_resolved_keep_both"))
    }

    @MainActor
    func testS4X01C416SwitchingStrategyRefreshesPreviewWithoutApplying() async {
        let resolver = S4X01RecordingSyncConflictResolver(previewResults: [
            .keepBoth: .success(.s4x01PreviewFixture()),
            .useExisting: .success(.s4x01PreviewFixture(
                resolution: .useExisting,
                previewToken: "preview-token-use-existing"
            ))
        ])
        let model = makeModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useExisting)
        let previewRequests = await resolver.recordedPreviewRequests()
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertEqual(model.selectedResolution, .useExisting)
        XCTAssertEqual(model.previewState.preview?.resolution, .useExisting)
        XCTAssertTrue(model.canApplyResolution)
        XCTAssertEqual(previewRequests.map(\.resolution), [.keepBoth, .useExisting])
        XCTAssertEqual(resolveRequests, [])
    }

    @MainActor
    func testS4X01C416UseIncomingRequiresS4X09AndDoesNotResolveDirectly() async {
        let resolver = S4X01RecordingSyncConflictResolver(previewResults: [
            .keepBoth: .success(.s4x01PreviewFixture()),
            .useIncoming: .success(.s4x01PreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                blockedReason: "Replace confirmation required",
                previewToken: "preview-token-use-incoming"
            ))
        ])
        let model = makeModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useIncoming)
        await model.applyResolution()
        let body = s4x01MirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertFalse(model.canApplyResolution)
        XCTAssertEqual(model.applyDisabledReason, "Use incoming version requires S4-X-09 replace confirmation.")
        XCTAssertEqual(resolveRequests, [])
        XCTAssertTrue(body.contains("Use incoming version requires S4-X-09 replace confirmation."))
        XCTAssertTrue(body.contains("Replace confirmation required"))
    }

    @MainActor
    func testS4X01C416ApplyUsesPreviewTokenAndShowsCoreReport() async {
        let resolver = S4X01RecordingSyncConflictResolver(previewResults: [
            .keepBoth: .success(.s4x01PreviewFixture(previewToken: "preview-token-142"))
        ])
        let model = makeModel(resolver: resolver)

        await model.load()
        await model.applyResolution()
        let body = s4x01MirrorDescription(of: SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body)
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertEqual(resolveRequests, [
            S4X01SyncConflictResolveRequest(
                repoPath: "/tmp/s4x01-repo",
                conflictID: "conflict-report",
                request: SyncConflictResolutionRequestSnapshot(
                    strategy: .keepBoth,
                    previewToken: "preview-token-142",
                    replaceConfirmed: false,
                    replaceConfirmationID: nil
                )
            )
        ])
        XCTAssertEqual(model.applyState, .succeeded(.s4x01ResolveFixture()))
        XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
        XCTAssertFalse(model.canApplyResolution)
        XCTAssertTrue(body.contains(SyncConflictReviewAccessibilityID.applySuccess))
        XCTAssertTrue(body.contains("Resolution applied."))
        XCTAssertTrue(body.contains("conflict_resolved_keep_both"))
    }

    @MainActor
    func testS4X01C416ApplyCannotReuseResolvedPreviewToken() async {
        let resolver = S4X01RecordingSyncConflictResolver(previewResults: [
            .keepBoth: .success(.s4x01PreviewFixture(previewToken: "preview-token-142"))
        ])
        let model = makeModel(resolver: resolver)

        await model.load()
        await model.applyResolution()
        await model.applyResolution()
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertEqual(resolveRequests.count, 1)
        XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
    }

    @MainActor
    func testS4X01C416PreviewAndApplyFailuresUseCoreErrorMapping() async {
        let mapper = S4X01RecordingErrorMapper(mapping: .s4x01Mapping(rawContext: "sync conflict locked"))
        let resolver = S4X01RecordingSyncConflictResolver(
            previewResults: [
                .keepBoth: .failure(CoreError.Db(message: "preview locked")),
                .useExisting: .success(.s4x01PreviewFixture(
                    resolution: .useExisting,
                    previewToken: "preview-token-use-existing"
                ))
            ],
            resolveResult: .failure(CoreError.Conflict(path: "stale sync conflict"))
        )
        let model = makeModel(resolver: resolver, errorMapper: mapper)

        await model.load()
        XCTAssertFalse(model.canApplyResolution)
        guard case .failed(.keepBoth, _) = model.previewState else {
            XCTFail("Expected preview failure")
            return
        }

        await model.selectResolution(.useExisting)
        await model.applyResolution()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [
            CoreError.Db(message: "preview locked"),
            CoreError.Conflict(path: "stale sync conflict")
        ])
        guard case .failed(.useExisting, _) = model.applyState else {
            XCTFail("Expected apply failure")
            return
        }
    }

    @MainActor
    private func makeModel(
        resolver: S4X01RecordingSyncConflictResolver,
        errorMapper: S4X01RecordingErrorMapper = S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
    ) -> SyncConflictReviewModel {
        SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictDetector: S4X01RecordingSyncConflictDetector(result: .success([.s4x01Fixture()])),
            conflictResolver: resolver,
            errorMapper: errorMapper
        )
    }
}
