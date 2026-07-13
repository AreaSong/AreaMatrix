@testable import AreaMatrix
import XCTest

final class SyncConflictReviewResolutionFeatureTests: XCTestCase {
    @MainActor
    func testSyncConflictReviewSyncConflictResolveCoreLoadedViewShowsSummaryVersionsAndDefaultImpact() async throws {
        let conflict = SyncConflictSnapshot.syncConflictReviewFixture()
        let resolver = SyncConflictReviewResolver(previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture())
        ])
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictDetector: SyncConflictReviewDetector(result: .success([conflict])),
            conflictResolver: resolver,
            errorMapper: StaticCoreErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.load()
        let loadedConflict = try XCTUnwrap(model.conflict)
        let body = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body

        XCTAssertEqual(loadedConflict.conflictType.displayName, "Same name, different content")
        XCTAssertEqual(loadedConflict.primaryPath, "docs/report.pdf")
        XCTAssertEqual(loadedConflict.affectedFiles.map(\.role.displayName), ["Existing file", "Incoming file"])
        await resolver.assertResolutionPreviewRequests([
            SyncConflictPreviewRequest(
                repoPath: "/tmp/syncConflictReview-repo",
                conflictID: "conflict-report",
                resolution: .keepBoth
            )
        ])
        XCTAssertEqual(model.selectedResolution, .keepBoth)
        XCTAssertEqual(model.previewState.preview?.changeLogAction, "conflict_resolved_keep_both")
        XCTAssertTrue(model.canApplyResolution)
        XCTAssertEqual(SyncConflictResolutionStrategySnapshot.allCases.map(\.title), [
            "Keep both",
            "Use existing version",
            "Use incoming version"
        ])
        assertSyncConflictReviewLoadedBody(body)
    }

    @MainActor
    func testSyncConflictReviewSyncConflictResolveCoreSwitchingStrategyRefreshesPreviewWithoutApplying() async {
        let resolver = SyncConflictReviewResolver(previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture()),
            .useExisting: .success(.syncConflictReviewPreviewFixture(
                resolution: .useExisting,
                previewToken: "preview-token-use-existing"
            ))
        ])
        let model = makeSyncConflictReviewModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useExisting)

        XCTAssertEqual(model.selectedResolution, .useExisting)
        XCTAssertEqual(model.previewState.preview?.resolution, .useExisting)
        XCTAssertTrue(model.canApplyResolution)
        await resolver.assertPreviewedResolutionStrategies([.keepBoth, .useExisting])
        await resolver.assertResolutionApplyRequests([])
    }

    @MainActor
    func testReplaceResolutionReplaceConfirmCrossPlatformCoreUseIncomingRequiresReplaceConfirmationBeforeResolve(
    ) async throws {
        let resolver = SyncConflictReviewResolver(previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture()),
            .useIncoming: .success(.syncConflictReviewPreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                blockedReason: "Replace confirmation required",
                previewToken: "preview-token-use-incoming"
            ))
        ])
        let model = makeSyncConflictReviewModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useIncoming)
        await model.applyResolution()
        let preview = try XCTUnwrap(model.previewState.preview)
        let replacePlan = try XCTUnwrap(preview.replacePlan)

        XCTAssertFalse(model.canApplyResolution)
        XCTAssertTrue(model.canConfirmReplacePlan)
        XCTAssertEqual(
            model.applyDisabledReason,
            "Confirm the replace-resolution replace plan before applying Use incoming version."
        )
        await resolver.assertResolutionApplyRequests([])
        XCTAssertEqual(preview.blockedReasonDisplay, "Replace confirmation required")
        XCTAssertEqual(replacePlan.changeLogAction, "conflict_resolved_use_incoming")
        XCTAssertEqual(replacePlan.backupTarget, "Trash")
        XCTAssertNil(model.replaceConfirmationDisabledReason)
    }

    @MainActor
    func testReplaceResolutionReplaceConfirmCrossPlatformCoreConfirmedReplaceUsesPreviewTokenAndCoreResolveFlag(
    ) async throws {
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
        let model = makeSyncConflictReviewModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useIncoming)
        model.confirmReplacePlan(understandsReplace: false)
        XCTAssertNil(model.replaceConfirmation)

        model.confirmReplacePlan(understandsReplace: true)
        await model.applyResolution()
        let preview = try XCTUnwrap(model.previewState.preview)
        let confirmation = try XCTUnwrap(model.replaceConfirmation)
        let panelBody = SyncConflictReplaceConfirmationPanel(
            preview: preview,
            confirmation: confirmation,
            disabledReason: model.replaceConfirmationDisabledReason,
            onConfirm: { _ in }
        ).body

        XCTAssertEqual(confirmation.previewToken, "preview-token-use-incoming")
        await resolver.assertResolutionApplyRequests([
            SyncConflictResolveRequest(
                repoPath: "/tmp/syncConflictReview-repo",
                conflictID: "conflict-report",
                request: .testFixture(
                    strategy: .useIncoming,
                    previewToken: "preview-token-use-incoming",
                    replaceConfirmed: true,
                    replaceConfirmationID: "replace-resolution-replace-confirmation-"
                        + "conflict-report-preview-token-use-incoming"
                )
            )
        ])
        XCTAssertEqual(model.applyState, .succeeded(.syncConflictReviewResolveFixture(resolution: .useIncoming)))
        assertSyncConflictReviewConfirmedReplacePanel(panelBody)
    }

    @MainActor
    func testReplaceResolutionReplaceConfirmCrossPlatformCoreTrashUnavailableDisablesReplaceConfirmationAndResolve(
    ) async {
        let resolver = SyncConflictReviewResolver(previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture()),
            .useIncoming: .success(.syncConflictReviewPreviewFixture(
                resolution: .useIncoming,
                canApply: false,
                requiresReplaceConfirmation: true,
                trashAvailable: false,
                blockedReason: "Replace requires Trash or safety backup",
                previewToken: "preview-token-use-incoming"
            ))
        ])
        let model = makeSyncConflictReviewModel(resolver: resolver)

        await model.load()
        await model.selectResolution(.useIncoming)
        model.confirmReplacePlan(understandsReplace: true)
        await model.applyResolution()

        XCTAssertNil(model.replaceConfirmation)
        XCTAssertFalse(model.canConfirmReplacePlan)
        XCTAssertEqual(model.replaceConfirmationDisabledReason, "Replace requires Trash or safety backup")
        XCTAssertFalse(model.canApplyResolution)
        await resolver.assertResolutionApplyRequests([])
    }

    @MainActor
    func testSyncConflictReviewSyncConflictResolveCoreApplyUsesPreviewTokenAndShowsCoreReport() async {
        let resolver = SyncConflictReviewResolver(previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture(previewToken: "preview-token-142"))
        ])
        let model = makeSyncConflictReviewModel(resolver: resolver)

        await model.load()
        await model.applyResolution()
        let body = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body

        await resolver.assertResolutionApplyRequests([
            SyncConflictResolveRequest(
                repoPath: "/tmp/syncConflictReview-repo",
                conflictID: "conflict-report",
                request: .testFixture(
                    previewToken: "preview-token-142"
                )
            )
        ])
        XCTAssertEqual(model.applyState, .succeeded(.syncConflictReviewResolveFixture()))
        XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
        XCTAssertFalse(model.canApplyResolution)
        assertSyncConflictReviewAppliedBody(body, report: .syncConflictReviewResolveFixture())
    }

    @MainActor
    func testSyncConflictReviewSyncConflictResolveCoreApplyCannotReuseResolvedPreviewToken() async {
        let resolver = SyncConflictReviewResolver(previewResults: [
            .keepBoth: .success(.syncConflictReviewPreviewFixture(previewToken: "preview-token-142"))
        ])
        let model = makeSyncConflictReviewModel(resolver: resolver)

        await model.load()
        await model.applyResolution()
        await model.applyResolution()

        await resolver.assertResolutionApplyRequestCount(1)
        XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
    }

    @MainActor
    func testSyncConflictReviewSyncConflictResolveCorePreviewAndApplyFailuresUseCoreErrorMapping() async {
        let mapper =
            StaticCoreErrorMapper(
                mapping: .syncConflictReviewMapping(rawContext: "sync conflict locked")
            )
        let resolver = SyncConflictReviewResolver(
            previewResults: [
                .keepBoth: .failure(CoreError.Db(message: "preview locked")),
                .useExisting: .success(.syncConflictReviewPreviewFixture(
                    resolution: .useExisting,
                    previewToken: "preview-token-use-existing"
                ))
            ],
            resolveResult: .failure(CoreError.Conflict(path: "stale sync conflict"))
        )
        let model = makeSyncConflictReviewModel(resolver: resolver, errorMapper: mapper)

        await model.load()
        XCTAssertFalse(model.canApplyResolution)
        guard case .failed(.keepBoth, _) = model.previewState else {
            XCTFail("Expected preview failure")
            return
        }

        await model.selectResolution(.useExisting)
        await model.applyResolution()

        await mapper.assertMappedCoreErrors([
            CoreError.Db(message: "preview locked"),
            CoreError.Conflict(path: "stale sync conflict")
        ])
        guard case .failed(.useExisting, _) = model.applyState else {
            XCTFail("Expected apply failure")
            return
        }
    }
}

final class SyncConflictReviewIntegrationTests: XCTestCase {
    @MainActor
    func testSyncConflictReviewIntegrationConnectsDetectResolveReplaceConfirmAndResolvedExit(
    ) async {
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
            conflictID: "conflict-report",
            conflictDetector: detector,
            conflictResolver: resolver,
            errorMapper: StaticCoreErrorMapper(mapping: .syncConflictReviewMapping())
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
        model.confirmReplacePlan(understandsReplace: true)
        await view.applySelectedResolution()

        await detector.assertDetectedSyncConflictRepos(["/tmp/syncConflictReview-repo"])
        await resolver.assertPreviewedResolutionStrategies([.keepBoth, .useIncoming])
        await resolver.assertResolutionApplyRequests([.useIncomingConfirmedRequest])
        XCTAssertEqual(resolvedReports, [.syncConflictReviewResolveFixture(resolution: .useIncoming)])
        XCTAssertEqual(model.applyDisabledReason, "Resolution has already been applied.")
    }

    @MainActor
    func testSyncConflictReviewPageIntegrationResolveFailureKeepsSheetCallbackUnfired() async {
        let mapper =
            StaticCoreErrorMapper(mapping: .syncConflictReviewMapping(rawContext: "apply failed"))
        let resolver = SyncConflictReviewResolver(
            previewResults: [.keepBoth: .success(.syncConflictReviewPreviewFixture(previewToken: "preview-token-144"))],
            resolveResult: .failure(CoreError.Conflict(path: "stale sync conflict"))
        )
        let model = makeSyncConflictReviewModel(resolver: resolver, errorMapper: mapper)
        var resolvedReports: [SyncConflictResolveReportSnapshot] = []
        let view = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {},
            onResolved: { resolvedReports.append($0) }
        )

        await model.load()
        await view.applySelectedResolution()

        XCTAssertTrue(resolvedReports.isEmpty)
        guard case .failed(.keepBoth, _) = model.applyState else {
            return XCTFail("Expected apply failure to remain in sync-conflict-review")
        }
        await mapper.assertMappedCoreErrors([CoreError.Conflict(path: "stale sync conflict")])
    }

    @MainActor
    func testSyncConflictReviewPageIntegrationOuterResolvedHandlerClosesRouteAndRefreshesNeedsReview() async {
        let docsFile = FileEntrySnapshot.syncConflictReviewFixture(
            id: 144,
            path: "docs/report.pdf",
            currentName: "report.pdf"
        )
        let lister = MainListRecordingFileLister(results: [.success([docsFile]), .success([])])
        let content = MainRepositoryContentView(
            opening: .syncConflictReviewFixture(repoPath: "/tmp/syncConflictReview-repo", files: [docsFile]),
            state: .list,
            assembly: .make(
                opening: .syncConflictReviewFixture(repoPath: "/tmp/syncConflictReview-repo", files: [docsFile]),
                fileLister: lister,
                fileDetailer: RecordingFileDetailer(results: [.success(docsFile)]),
                errorMapper: StaticCoreErrorMapper(mapping: .syncConflictReviewMapping())
            ),
            onImport: {},
            onDropImport: { _, _ in }
        )

        await content.fileListModel.loadCurrentCategory("docs")
        content.beginSyncConflictReview(file: docsFile)
        await lister.assertFileListFilters([.currentCategory("docs")])

        await content.handleSyncConflictResolved(.syncConflictReviewResolveFixture())

        XCTAssertNil(content.pendingSyncConflictReviewRoute)
        await lister.assertFileListRequestCount(2)
    }
}

private func assertSyncConflictReviewLoadedBody(_ body: Any) {
    assertTestMirrorDescription(of: body, contains: [
        SyncConflictReviewAccessibilityID.resolution,
        SyncConflictReviewAccessibilityID.impact,
        SyncConflictReviewCopy.applyAction,
        "Keep both",
        "conflict_resolved_keep_both"
    ])
}

private func assertSyncConflictReviewAppliedBody(
    _ body: Any,
    report: SyncConflictResolveReportSnapshot
) {
    assertTestMirrorDescription(of: body, contains: [
        "SyncConflictReviewApplySuccess"
    ])
    assertTestMirrorDescription(of: SyncConflictReviewApplySuccess(report: report).body, contains: [
        SyncConflictReviewAccessibilityID.applySuccess,
        "Resolution applied.",
        report.changeLogAction
    ])
}

private func assertSyncConflictReviewConfirmedReplacePanel(_ panelBody: Any) {
    assertTestMirrorDescription(of: panelBody, contains: [
        SyncConflictReviewAccessibilityID.replaceConfirmation,
        SyncConflictReviewAccessibilityID.replaceConfirm,
        "Confirm Replace",
        "I understand this will replace the existing file.",
        "Old file path",
        "Old version will be kept at",
        "Replace plan confirmed for this preview token.",
        "conflict_resolved_use_incoming"
    ])
}

@MainActor
private func makeSyncConflictReviewModel(
    resolver: SyncConflictReviewResolver,
    errorMapper: any CoreErrorMapping =
        StaticCoreErrorMapper(mapping: .syncConflictReviewMapping())
) -> SyncConflictReviewModel {
    SyncConflictReviewModel(
        repoPath: "/tmp/syncConflictReview-repo",
        conflictDetector: SyncConflictReviewDetector(
            result: .success([.syncConflictReviewFixture()])
        ),
        conflictResolver: resolver,
        errorMapper: errorMapper
    )
}
