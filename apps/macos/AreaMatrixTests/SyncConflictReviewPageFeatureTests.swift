@testable import AreaMatrix
import XCTest

final class SyncConflictReviewPageFeatureTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = [
        "sync-conflict-detect",
        "sync-conflict-resolve",
        "replace-confirmation"
    ]

    func testSyncConflictReviewDeclaresOnlyDetectResolveAndReplaceConfirmBoundaries() {
        XCTAssertEqual(
            Self.declaredCapabilities,
            ["sync-conflict-detect", "sync-conflict-resolve", "replace-confirmation"]
        )
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.detectSyncConflicts))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.previewSyncConflictResolution))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.resolveSyncConflict))
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreLoadUsesCoreBridgeDetectorAndSelectsRequestedConflict() async {
        let expected = SyncConflictSnapshot.syncConflictReviewFixture(conflictID: "conflict-selected")
        let detector = SyncConflictReviewDetector(result: .success([
            .syncConflictReviewFixture(conflictID: "conflict-other"),
            expected
        ]))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictID: "conflict-selected",
            conflictDetector: detector,
            conflictResolver: SyncConflictReviewResolver(previewResults: [
                .keepBoth: .success(.syncConflictReviewPreviewFixture(conflictID: "conflict-selected"))
            ]),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.load()
        let requests = await detector.recordedRequests()

        XCTAssertEqual(requests, ["/tmp/syncConflictReview-repo"])
        XCTAssertEqual(model.state, .loaded(expected))
        XCTAssertEqual(model.conflict, expected)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreFileDetailRouteSelectsConflictByAffectedPath() async {
        let expected = SyncConflictSnapshot.syncConflictReviewFixture(conflictID: "conflict-matching-file")
        let detector = SyncConflictReviewDetector(result: .success([
            .syncConflictReviewFixture(conflictID: "conflict-other", primaryPath: "docs/other.pdf"),
            expected
        ]))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            primaryPath: "docs/report (Windows conflict).pdf",
            conflictDetector: detector,
            conflictResolver: SyncConflictReviewResolver(previewResults: [
                .keepBoth: .success(.syncConflictReviewPreviewFixture(conflictID: "conflict-matching-file"))
            ]),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.load()

        XCTAssertEqual(model.state, .loaded(expected))
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreFileDetailEntryCanRouteToReviewSheet() async {
        let file = FileEntrySnapshot.syncConflictReviewFixture(
            id: 141,
            path: "docs/report.pdf",
            currentName: "report.pdf"
        )
        let opening = RepositoryOpeningResult.syncConflictReviewFixture(
            repoPath: "/tmp/syncConflictReview-repo",
            files: [file]
        )
        var routedFile: FileEntrySnapshot?

        let model = MainFileListModel(
            opening: opening,
            fileLister: NoopFileLister(),
            fileDetailer: SyncConflictReviewRecordingFileDetailer(result: .success(file)),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )
        await model.selectFiles([file.id])
        let detailPane = makeSyncConflictReviewDetailPane(
            model: model,
            opening: opening,
            onBeginSyncConflictReview: { routedFile = $0 }
        )
        let route = SyncConflictReviewRoute.fileDetail(repoPath: opening.config.repoPath, file: file)

        assertTestMirrorDescription(of: detailPane.body, contains: "MainRepositoryDetailFileActionMenu")
        assertMainRepositoryDetailFileActionMenu(for: file, contains: [
            "Review Sync Conflict..."
        ])
        XCTAssertEqual(route, SyncConflictReviewRoute(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictID: nil,
            primaryPath: "docs/report.pdf"
        ))
        XCTAssertNil(routedFile)
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreMissingOrResolvedConflictShowsEmptyState() async {
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictID: "missing-conflict",
            conflictDetector: SyncConflictReviewDetector(result: .success([
                .syncConflictReviewFixture(conflictID: "resolved-conflict", status: .resolved)
            ])),
            conflictResolver: SyncConflictReviewResolver(previewResults: [:]),
            errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
        )

        await model.load()
        let body = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body

        XCTAssertEqual(model.state, .empty)
        assertTestMirrorDescription(of: body, contains: [
            SyncConflictReviewCopy.emptyTitle,
            SyncConflictReviewCopy.backAction,
            SyncConflictReviewAccessibilityID.empty
        ])
    }

    @MainActor
    func testSyncConflictReviewSyncConflictDetectCoreErrorStateMapsCoreErrorAndKeepsRetryVisible() async {
        let mapper = SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping(
            kind: .conflict,
            rawContext: "stale conflict id"
        ))
        let model = SyncConflictReviewModel(
            repoPath: "/tmp/syncConflictReview-repo",
            conflictDetector: SyncConflictReviewDetector(result: .failure(CoreError.Conflict(
                path: "stale conflict id"
            ))),
            conflictResolver: SyncConflictReviewResolver(previewResults: [:]),
            errorMapper: mapper
        )

        await model.load()
        let body = SyncConflictReviewView(
            model: model,
            onBackToNeedsReview: {},
            onClose: {}
        ).body
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: "stale conflict id")])
        assertTestMirrorDescription(of: body, contains: [
            SyncConflictReviewAccessibilityID.error,
            SyncConflictReviewCopy.errorTitle,
            "Retry"
        ])
    }
}

@MainActor
private func makeSyncConflictReviewDetailPane(
    model: MainFileListModel,
    opening: RepositoryOpeningResult,
    onBeginSyncConflictReview: @escaping (FileEntrySnapshot) -> Void
) -> MainRepositoryDetailPane {
    MainRepositoryDetailPane(
        selection: model.selection,
        multiSelectionSummary: MultiSelectionDetailSummary(selection: model.selection, files: model.files),
        detailErrorMapping: model.detailErrorMapping,
        isDetailLoading: model.isDetailLoading,
        selectedFileDetail: model.selectedFileDetail,
        noteWriteBlock: model.selectedFileNoteWriteBlock,
        detailLogState: model.detailLogState,
        detailLogDiagnosticsState: model.detailLogDiagnosticsState,
        detailExternalCreateSyncState: model.detailExternalCreateSyncState,
        detailTagEditorState: model.detailTagEditorState,
        detailTagSuggestionState: model.detailTagSuggestionState,
        tagSuggestionPresentationRequest: model.tagSuggestionPresentationRequest,
        detailTagUndoToast: model.detailTagUndoToast,
        detailTabRequest: model.detailTabRequest,
        selectedImportProgressRow: nil,
        semanticDetail: nil,
        repoPath: opening.config.repoPath,
        batchTagStore: CoreBridge(),
        batchTagUndoStore: CoreBridge(),
        batchTagErrorMapper: model.errorMapper,
        batchDeleter: CoreBridge(),
        batchCategoryChanger: CoreBridge(),
        batchRenamer: CoreBridge(),
        categoryRows: opening.tree.sidebarRows,
        onBatchCategoryApplied: { _ in },
        onBatchDeleteApplied: { _ in },
        onBatchRenameApplied: { _ in },
        onBatchCategoryCreateNewCategory: { _ in },
        onRetrySelectedFileDetail: {},
        tagActions: .noop,
        onCopyPaths: { _ in },
        onOpenNoteFile: { _ in },
        onRefreshChangeLog: {},
        onRequestDetailLogDiagnostics: {},
        onConfirmDetailLogDiagnostics: {},
        onCancelDetailLogDiagnostics: {},
        onDetailTabRequestConsumed: { _ in },
        onBeginRenameFile: { _ in },
        onBeginChangeCategoryFile: { _ in },
        onBeginClassifierCorrectionFile: { _ in },
        onBeginAIClassificationSuggestionFile: { _ in },
        onBeginDeleteFile: { _ in },
        onBeginICloudConflictResolution: { _ in },
        onBeginSyncConflictReview: onBeginSyncConflictReview,
        onOpenAISettings: {},
        writeActionDisabledReason: model.writeActionDisabledReason,
        summaryExitController: AISummaryEditorExitController(),
        noteModel: makeSyncConflictReviewDetailNoteModel(repoPath: opening.config.repoPath)
    )
}

@MainActor
private func makeSyncConflictReviewDetailNoteModel(repoPath: String) -> DetailNoteModel {
    DetailNoteModel(
        repoPath: repoPath,
        noteStore: NoopNoteStore(),
        errorMapper: SyncConflictReviewRecordingErrorMapper(mapping: .syncConflictReviewMapping())
    )
}
