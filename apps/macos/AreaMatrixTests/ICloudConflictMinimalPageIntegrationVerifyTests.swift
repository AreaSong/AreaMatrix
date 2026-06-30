@testable import AreaMatrix
import XCTest

final class ICloudConflictMinimalIntegrationTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["validate-repo-path", "error-mapping"]

    func testICloudConflictMinimalPageIntegrationUsesOnlyDeclaredControlMapCapabilities() {
        XCTAssertEqual(Self.declaredCapabilities, ["validate-repo-path", "error-mapping"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.validateRepoPath))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.mapCoreError))
        XCTAssertFalse(Self.declaredCapabilities.contains("delete-remove-index"))
        XCTAssertFalse(Self.declaredCapabilities.contains("icloud-conflicts-core"))
    }

    @MainActor
    func testICloudConflictMinimalEntryCancelAndApplyBlockedByMissingCoreResolutionEndpoint() async {
        let conflictFile = FileEntrySnapshot.iCloudConflictMinimalConflictFixture(id: 125)
        let core = ICloudConflictMinimalRecordingMainCore(files: [conflictFile])
        let blockedCapability = ICloudConflictResolutionCapability.blocked(.missingCoreResolutionEndpoint)
        let model = makeMainFileListModel(conflictFile: conflictFile, core: core)

        await model.selectFiles([conflictFile.id])
        let detailPaneBody = makeDetailPaneBody(model: model)
        assertTestMirrorDescription(of: detailPaneBody, contains: "MainRepositorySelectedFileDetailPane")
        assertMainRepositoryDetailFileActionMenu(for: conflictFile, contains: [
            "Resolve iCloud Conflict..."
        ])

        model.beginICloudConflictResolution(fileID: conflictFile.id)
        XCTAssertEqual(model.pendingActionDestination, .iCloudConflict(fileID: conflictFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "icloud-conflict-minimal")

        model.clearPendingActionDestination()
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertNil(model.statusBanner)

        model.beginICloudConflictResolution(fileID: conflictFile.id)
        let body = await makeICloudConflictSheetBody(
            model: makeReadyICloudConflictModel(),
            resolutionState: model.iCloudConflictResolutionState,
            resolutionCapability: blockedCapability,
            isTrashAvailable: true
        )
        let outOfScopeActions = await core.recordedOutOfScopeActions()

        assertTestMirrorDescription(of: body, contains: [
            "icloud-conflict-minimal-core-resolution-blocked",
            "Core resolution unavailable",
            "Missing Core API: resolve_icloud_conflict or mark_icloud_conflict_resolved"
        ])
        XCTAssertEqual(outOfScopeActions, [])
        XCTAssertEqual(model.pendingActionDestination, .iCloudConflict(fileID: conflictFile.id))
        XCTAssertNil(model.statusBanner)
        XCTAssertNil(model.detailLogState.iCloudConflictMinimalLoadedFileID)
    }

    @MainActor
    func testICloudConflictMinimalApplyMapsCapabilityBlockerWithoutCallingOutOfScopeCoreActions() async {
        let conflictFile = FileEntrySnapshot.iCloudConflictMinimalConflictFixture(id: 126)
        let core = ICloudConflictMinimalRecordingMainCore(files: [conflictFile])
        let mapper = ICloudErrorMapper(mapping: .iCloudConflictMinimalMapping(
            kind: .internal,
            rawContext: ICloudConflictResolutionBlocker.missingCoreResolutionEndpoint.rawContext
        ))
        let blockedResolver = ICloudConflictResolver(
            capability: .blocked(.missingCoreResolutionEndpoint),
            result: .failure(ICloudConflictResolutionBlocker.missingCoreResolutionEndpoint.coreError)
        )
        let model = MainFileListModel(
            opening: .iCloudConflictMinimalFixture(repoPath: "/tmp/iCloudConflictMinimal-repo", files: [conflictFile]),
            fileLister: core,
            fileDetailer: core,
            iCloudConflictResolver: blockedResolver,
            changeLogLister: core,
            externalChangesSyncer: core,
            errorMapper: mapper,
            diagnosticsCollector: core
        )

        model.beginICloudConflictResolution(fileID: conflictFile.id)
        await model.applyKeepBothICloudConflict(fileID: conflictFile.id)
        let failedBody = await makeICloudConflictSheetBody(
            model: makeReadyICloudConflictModel(),
            resolutionState: model.iCloudConflictResolutionState,
            resolutionCapability: blockedResolver.iCloudConflictResolutionCapability,
            isTrashAvailable: true
        )

        XCTAssertEqual(model.pendingActionDestination, .iCloudConflict(fileID: conflictFile.id))
        let recordedErrors = await mapper.recordedErrors()
        XCTAssertEqual(recordedErrors, [ICloudConflictResolutionBlocker.missingCoreResolutionEndpoint.coreError])
        assertTestMirrorDescription(of: failedBody, contains: [
            "icloud-conflict-minimal-error-mapping-apply-failure",
            "Apply failed: Internal",
            "Retry",
            "Cancel",
            "Collect Diagnostics..."
        ])
        let outOfScopeActions = await core.recordedOutOfScopeActions()
        XCTAssertEqual(outOfScopeActions, [])
        XCTAssertNil(model.statusBanner)
    }

    func testICloudConflictVisualCoreBridgeResolutionCapabilityIsSupported() {
        XCTAssertEqual(CoreBridge().iCloudConflictResolutionCapability, .supported)
    }

    @MainActor
    func testICloudConflictMinimalSheetDefinesThreeStrategiesAndTrashBoundary() async {
        let model = await makeReadyICloudConflictModel()
        let body = makeICloudConflictSheetBody(
            model: model,
            resolutionState: .idle,
            resolutionCapability: .blocked(.missingCoreResolutionEndpoint),
            isTrashAvailable: false
        )

        XCTAssertEqual(ICloudConflictResolutionStrategy.allCases, [
            .keepBoth,
            .keepOriginalOnly,
            .keepConflictedCopyOnly
        ])
        XCTAssertEqual(ICloudConflictResolutionStrategy.allCases.map(\.title), [
            "保留两份（推荐）",
            "仅保留第一份（把另一份移到回收站）",
            "仅保留第二份（把另一份移到回收站）"
        ])
        XCTAssertEqual(
            ICloudConflictResolutionStrategy.keepOriginalOnly.actionTitle,
            "Move other version to Trash and Apply"
        )
        XCTAssertTrue(ICloudConflictResolutionStrategy.keepOriginalOnly.requiresSecondConfirmation)
        assertTestMirrorDescription(of: body, contains: [
            "Single-version resolution requires system Trash",
            "requires Core support to clear conflict state and write change_log",
            "icloud-conflict-minimal-core-resolution-blocked"
        ])
    }

    @MainActor
    func testICloudConflictMinimalValidationErrorStateMapsCoreError() async {
        let failedValidator = ICloudPathValidator(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/iCloudConflictMinimal-repo"))
        )
        let mapper = ICloudErrorMapper(mapping: .iCloudConflictMinimalMapping(
            kind: .permissionDenied,
            rawContext: "/tmp/iCloudConflictMinimal-repo"
        ))
        let failedModel = makeICloudConflictModel(pathValidator: failedValidator, errorMapper: mapper)

        await failedModel.validateRepositoryPath()
        let failedBody = makeICloudConflictSheetBody(
            model: failedModel,
            resolutionState: .idle,
            resolutionCapability: .blocked(.missingCoreResolutionEndpoint),
            isTrashAvailable: true
        )

        let recordedErrors = await mapper.recordedErrors()
        XCTAssertEqual(recordedErrors, [CoreError.PermissionDenied(path: "/tmp/iCloudConflictMinimal-repo")])
        XCTAssertFalse(failedModel.canApplyKeepBoth)
        assertTestMirrorDescription(of: failedBody, contains: [
            "icloud-conflict-minimal-error-mapping-error-mapping",
            "Repository check failed: PermissionDenied",
            "Retry repository check"
        ])
    }

    @MainActor
    func testICloudConflictMinimalSupportedResolverCompletesRefreshAndChangeLogEvidence() async {
        let conflictFile = FileEntrySnapshot.iCloudConflictMinimalConflictFixture(id: 127)
        let core = ICloudConflictMinimalRecordingMainCore(files: [conflictFile])
        let resolver = ICloudConflictResolver(
            result: .success(ICloudConflictResolutionResult(
                focusFileID: conflictFile.id,
                didClearConflictState: true,
                didWriteChangeLog: true
            ))
        )
        let model = MainFileListModel(
            opening: .iCloudConflictMinimalFixture(repoPath: "/tmp/iCloudConflictMinimal-repo", files: [conflictFile]),
            fileLister: core,
            fileDetailer: core,
            iCloudConflictResolver: resolver,
            changeLogLister: core,
            externalChangesSyncer: core,
            errorMapper: ICloudErrorMapper(mapping: .iCloudConflictMinimalMapping()),
            diagnosticsCollector: core
        )

        await model.selectFiles([conflictFile.id])
        model.beginICloudConflictResolution(fileID: conflictFile.id)
        await model.applyKeepBothICloudConflict(fileID: conflictFile.id)

        let requests = await resolver.recordedRequests()
        XCTAssertEqual(requests.map(\.strategy), [.keepBoth])
        XCTAssertEqual(requests.first?.repoPath, "/tmp/iCloudConflictMinimal-repo")
        XCTAssertEqual(requests.first?.fileID, conflictFile.id)
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.iCloudConflictResolutionState, .idle)
        XCTAssertEqual(model.statusBanner, .resolvedICloudConflict(fileID: conflictFile.id, strategy: .keepBoth))
        XCTAssertEqual(model.detailLogState.iCloudConflictMinimalLoadedFileID, conflictFile.id)
    }

    @MainActor
    private func makeMainFileListModel(
        conflictFile: FileEntrySnapshot,
        core: ICloudConflictMinimalRecordingMainCore,
        errorMapper: ICloudErrorMapper =
            ICloudErrorMapper(mapping: .iCloudConflictMinimalMapping())
    ) -> MainFileListModel {
        MainFileListModel(
            opening: .iCloudConflictMinimalFixture(repoPath: "/tmp/iCloudConflictMinimal-repo", files: [conflictFile]),
            fileLister: core,
            fileDetailer: core,
            fileRenamer: core,
            fileDeleter: core,
            fileCategoryMover: core,
            iCloudConflictResolver: CoreBridge(),
            changeLogLister: core,
            externalChangesSyncer: core,
            errorMapper: errorMapper,
            diagnosticsCollector: core
        )
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    private func makeDetailPaneBody(model: MainFileListModel) -> Any {
        let detailPane = MainRepositoryDetailPane(
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
            repoPath: "/tmp/iCloudConflictMinimal-repo",
            batchTagStore: model.tagStore,
            batchTagUndoStore: model.undoActionStore,
            batchTagErrorMapper: model.errorMapper,
            batchDeleter: CoreBridge(),
            batchCategoryChanger: model.batchCategoryChanger,
            batchRenamer: CoreBridge(),
            categoryRows: [],
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
            onBeginRenameFile: model.beginRename,
            onBeginChangeCategoryFile: model.beginChangeCategory,
            onBeginClassifierCorrectionFile: model.beginClassifierCorrection,
            onBeginAIClassificationSuggestionFile: model.beginAIClassificationSuggestion,
            onBeginDeleteFile: model.beginDelete,
            onBeginICloudConflictResolution: model.beginICloudConflictResolution,
            onBeginSyncConflictReview: { _ in },
            onOpenAISettings: {},
            writeActionDisabledReason: model.writeActionDisabledReason,
            canPerformWriteAction: model.canPerformWriteAction,
            summaryExitController: AISummaryEditorExitController(),
            noteModel: DetailNoteModel(
                repoPath: "/tmp/iCloudConflictMinimal-repo",
                noteStore: NoopNoteStore(),
                errorMapper: ICloudErrorMapper(mapping: .iCloudConflictMinimalMapping())
            )
        )

        return detailPane.body
    }

    @MainActor
    private func makeReadyICloudConflictModel() async -> ICloudConflictMinimalModel {
        let validator =
            ICloudPathValidator(result: .success(.iCloudConflictMinimalICloudConflictFixture()))
        let model = makeICloudConflictModel(pathValidator: validator)
        await model.validateRepositoryPath()
        return model
    }

    @MainActor
    private func makeICloudConflictModel(
        pathValidator: CoreRepositoryPathValidating,
        errorMapper: CoreErrorMapping =
            ICloudErrorMapper(mapping: .iCloudConflictMinimalMapping())
    ) -> ICloudConflictMinimalModel {
        ICloudConflictMinimalModel(
            repoPath: "/tmp/iCloudConflictMinimal-repo",
            originalVersion: .iCloudConflictMinimalOriginal(repoPath: "/tmp/iCloudConflictMinimal-repo"),
            conflictedCopyVersion: .iCloudConflictMinimalConflictedCopy(repoPath: "/tmp/iCloudConflictMinimal-repo"),
            pathValidator: pathValidator,
            conflictReviewer: nil,
            errorMapper: errorMapper
        )
    }

    @MainActor
    private func makeICloudConflictSheetBody(
        model: ICloudConflictMinimalModel,
        resolutionState: ICloudConflictResolutionState,
        resolutionCapability: ICloudConflictResolutionCapability,
        isTrashAvailable: Bool
    ) -> Any {
        ICloudConflictMinimalSheet(
            model: model,
            resolutionState: resolutionState,
            resolutionCapability: resolutionCapability,
            isTrashAvailable: isTrashAvailable,
            onCancel: {},
            onApply: { _ in },
            onCollectDiagnostics: {}
        ).body
    }
}
