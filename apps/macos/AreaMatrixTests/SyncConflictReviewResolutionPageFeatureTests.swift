@testable import AreaMatrix
import XCTest

final class SyncConflictReviewResolutionFeatureTests: XCTestCase {
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
    func testS4X09C416UseIncomingRequiresReplaceConfirmationBeforeResolve() async throws {
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
        let preview = try XCTUnwrap(model.previewState.preview)
        let replacePlan = try XCTUnwrap(preview.replacePlan)
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertFalse(model.canApplyResolution)
        XCTAssertTrue(model.canConfirmReplacePlan)
        XCTAssertEqual(
            model.applyDisabledReason,
            "Confirm the S4-X-09 replace plan before applying Use incoming version."
        )
        XCTAssertEqual(resolveRequests, [])
        XCTAssertEqual(preview.blockedReasonDisplay, "Replace confirmation required")
        XCTAssertEqual(replacePlan.changeLogAction, "conflict_resolved_use_incoming")
        XCTAssertEqual(replacePlan.backupTarget, "Trash")
        XCTAssertNil(model.replaceConfirmationDisabledReason)
    }

    @MainActor
    func testS4X09C416ConfirmedReplaceUsesPreviewTokenAndCoreResolveFlag() async throws {
        let resolver = S4X01RecordingSyncConflictResolver(
            previewResults: [
                .keepBoth: .success(.s4x01PreviewFixture()),
                .useIncoming: .success(.s4x01PreviewFixture(
                    resolution: .useIncoming,
                    canApply: false,
                    requiresReplaceConfirmation: true,
                    blockedReason: "Replace confirmation required",
                    previewToken: "preview-token-use-incoming"
                ))
            ],
            resolveResult: .success(.s4x01ResolveFixture(resolution: .useIncoming))
        )
        let model = makeModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useIncoming)
        model.confirmReplacePlan()
        await model.applyResolution()
        let preview = try XCTUnwrap(model.previewState.preview)
        let confirmation = try XCTUnwrap(model.replaceConfirmation)
        let panelBody = s4x01MirrorDescription(of: SyncConflictReplaceConfirmationPanel(
            preview: preview,
            confirmation: confirmation,
            disabledReason: model.replaceConfirmationDisabledReason,
            onConfirm: {}
        ).body)
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertEqual(confirmation.previewToken, "preview-token-use-incoming")
        XCTAssertEqual(resolveRequests, [
            S4X01SyncConflictResolveRequest(
                repoPath: "/tmp/s4x01-repo",
                conflictID: "conflict-report",
                request: SyncConflictResolutionRequestSnapshot(
                    strategy: .useIncoming,
                    previewToken: "preview-token-use-incoming",
                    replaceConfirmed: true,
                    replaceConfirmationID: "S4-X-09-C4-16-conflict-report-preview-token-use-incoming"
                )
            )
        ])
        XCTAssertEqual(model.applyState, .succeeded(.s4x01ResolveFixture(resolution: .useIncoming)))
        XCTAssertTrue(panelBody.contains(SyncConflictReviewAccessibilityID.replaceConfirmation))
        XCTAssertTrue(panelBody.contains(SyncConflictReviewAccessibilityID.replaceConfirm))
        XCTAssertTrue(panelBody.contains("Replace plan confirmed for this preview token."))
        XCTAssertTrue(panelBody.contains("conflict_resolved_use_incoming"))
    }

    @MainActor
    func testS4X09C416TrashUnavailableDisablesReplaceConfirmationAndResolve() async {
        let resolver = S4X01RecordingSyncConflictResolver(previewResults: [
            .keepBoth: .success(.s4x01PreviewFixture()),
            .useIncoming: .success(.s4x01PreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                trashAvailable: false,
                blockedReason: "Replace requires Trash or safety backup",
                previewToken: "preview-token-use-incoming"
            ))
        ])
        let model = makeModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useIncoming)
        model.confirmReplacePlan()
        await model.applyResolution()
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertNil(model.replaceConfirmation)
        XCTAssertFalse(model.canConfirmReplacePlan)
        XCTAssertEqual(model.replaceConfirmationDisabledReason, "Replace requires Trash or safety backup")
        XCTAssertFalse(model.canApplyResolution)
        XCTAssertEqual(resolveRequests, [])
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
    func testS4X01PageIntegrationConnectsC415C416C421AndResolvedExit() async throws {
        let detector = S4X01RecordingSyncConflictDetector(result: .success([.s4x01Fixture()]))
        let resolver = S4X01RecordingSyncConflictResolver(
            previewResults: [
                .keepBoth: .success(.s4x01PreviewFixture()),
                .useIncoming: .success(.s4x01PreviewFixture(
                    resolution: .useIncoming,
                    canApply: false,
                    requiresReplaceConfirmation: true,
                    blockedReason: "Replace confirmation required",
                    previewToken: "preview-token-use-incoming"
                ))
            ],
            resolveResult: .success(.s4x01ResolveFixture(resolution: .useIncoming))
        )
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/s4x01-repo",
            conflictID: "conflict-report",
            conflictDetector: detector,
            conflictResolver: resolver,
            errorMapper: S4X01RecordingErrorMapper(mapping: .s4x01Mapping())
        )
        var resolvedReports: [SyncConflictResolveReportSnapshot] = []
        let view = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {},
            onResolved: { resolvedReports.append($0) }
        )

        await model.load()
        await model.selectResolution(.useIncoming)
        model.confirmReplacePlan()
        await view.applySelectedResolution()
        let detectRequests = await detector.recordedRequests()
        let previewRequests = await resolver.recordedPreviewRequests()
        let resolveRequests = await resolver.recordedResolveRequests()

        XCTAssertEqual(detectRequests, ["/tmp/s4x01-repo"])
        XCTAssertEqual(previewRequests.map(\.resolution), [.keepBoth, .useIncoming])
        XCTAssertEqual(resolveRequests, [.s4x01UseIncomingConfirmedRequest])
        XCTAssertEqual(resolvedReports, [.s4x01ResolveFixture(resolution: .useIncoming)])
        XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
    }

    @MainActor
    func testS4X01PageIntegrationResolveFailureKeepsSheetCallbackUnfired() async {
        let mapper = S4X01RecordingErrorMapper(mapping: .s4x01Mapping(rawContext: "apply failed"))
        let resolver = S4X01RecordingSyncConflictResolver(
            previewResults: [.keepBoth: .success(.s4x01PreviewFixture(previewToken: "preview-token-144"))],
            resolveResult: .failure(CoreError.Conflict(path: "stale sync conflict"))
        )
        let model = makeModel(resolver: resolver, errorMapper: mapper)
        var resolvedReports: [SyncConflictResolveReportSnapshot] = []
        let view = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {},
            onResolved: { resolvedReports.append($0) }
        )

        await model.load()
        await view.applySelectedResolution()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertTrue(resolvedReports.isEmpty)
        guard case .failed(.keepBoth, _) = model.applyState else {
            return XCTFail("Expected apply failure to remain in S4-X-01")
        }
        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: "stale sync conflict")])
    }

    @MainActor
    func testS4X01PageIntegrationOuterResolvedHandlerClosesRouteAndRefreshesNeedsReview() async {
        let docsFile = FileEntrySnapshot.s4x01Fixture(id: 144, path: "docs/report.pdf", currentName: "report.pdf")
        let lister = MainListRecordingFileLister(results: [.success([docsFile]), .success([])])
        var content = MainRepositoryContentView(
            opening: .s4x01Fixture(repoPath: "/tmp/s4x01-repo", files: [docsFile]),
            state: .list,
            onImport: {},
            onDropImport: { _, _ in },
            fileLister: lister,
            fileDetailer: MainListRecordingFileDetailer(results: [.success(docsFile)]),
            errorMapper: MainListRecordingErrorMapper(mapping: .s4x01Mapping())
        )

        await content.fileListModel.loadCurrentCategory("docs")
        content.beginSyncConflictReview(file: docsFile)
        let beforeResolveRequests = await lister.recordedRequests()

        await content.handleSyncConflictResolved(.s4x01ResolveFixture())
        let listRequests = await lister.recordedRequests()

        XCTAssertNil(content.pendingSyncConflictReviewRoute)
        XCTAssertEqual(beforeResolveRequests, [FileFilterSnapshot.currentCategory("docs")])
        XCTAssertEqual(listRequests.count, beforeResolveRequests.count + 1)
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
