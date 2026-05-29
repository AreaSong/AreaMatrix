@testable import AreaMatrix
import XCTest

final class ICloudConflictMinimalIntegrationTests: XCTestCase {
    private static let declaredCapabilities: Set<String> = ["C1-01", "C1-21"]

    func testS125PageIntegrationUsesOnlyDeclaredControlMapCapabilities() {
        XCTAssertEqual(Self.declaredCapabilities, ["C1-01", "C1-21"])
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.validateRepoPath))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.mapCoreError))
        XCTAssertFalse(Self.declaredCapabilities.contains("C1-23"))
        XCTAssertFalse(Self.declaredCapabilities.contains("C1-25"))
    }

    @MainActor
    func testS125EntryCancelAndApplyBlockedByMissingCoreResolutionEndpoint() async {
        let conflictFile = FileEntrySnapshot.s125ConflictFixture(id: 125)
        let core = S125RecordingMainCore(files: [conflictFile])
        let blockedCapability = ICloudConflictResolutionCapability.blocked(.missingCoreResolutionEndpoint)
        let model = makeMainFileListModel(conflictFile: conflictFile, core: core)

        await model.selectFiles([conflictFile.id])
        XCTAssertTrue(makeDetailPaneBody(model: model).contains("Resolve iCloud Conflict..."))

        model.beginICloudConflictResolution(fileID: conflictFile.id)
        XCTAssertEqual(model.pendingActionDestination, .iCloudConflict(fileID: conflictFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S1-25")

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

        XCTAssertTrue(body.contains("S1-25-core-resolution-blocked"))
        XCTAssertTrue(body.contains("Core resolution unavailable"))
        XCTAssertTrue(body.contains("Missing Core API: resolve_icloud_conflict or mark_icloud_conflict_resolved"))
        XCTAssertEqual(outOfScopeActions, [])
        XCTAssertEqual(model.pendingActionDestination, .iCloudConflict(fileID: conflictFile.id))
        XCTAssertNil(model.statusBanner)
        XCTAssertNil(model.detailLogState.s125LoadedFileID)
    }

    @MainActor
    func testS125ApplyMapsCapabilityBlockerWithoutCallingOutOfScopeCoreActions() async {
        let conflictFile = FileEntrySnapshot.s125ConflictFixture(id: 126)
        let core = S125RecordingMainCore(files: [conflictFile])
        let mapper = S125RecordingErrorMapper(mapping: .s125Mapping(
            kind: .internal,
            rawContext: ICloudConflictResolutionBlocker.missingCoreResolutionEndpoint.rawContext
        ))
        let blockedResolver = S125RecordingICloudConflictResolver(
            capability: .blocked(.missingCoreResolutionEndpoint),
            result: .failure(ICloudConflictResolutionBlocker.missingCoreResolutionEndpoint.coreError)
        )
        let model = MainFileListModel(
            opening: .s125Fixture(repoPath: "/tmp/s125-repo", files: [conflictFile]),
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
        XCTAssertTrue(failedBody.contains("S1-25-C1-21-apply-failure"))
        XCTAssertTrue(failedBody.contains("Apply failed: Internal"))
        XCTAssertTrue(failedBody.contains("Retry"))
        XCTAssertTrue(failedBody.contains("Cancel"))
        XCTAssertTrue(failedBody.contains("Collect Diagnostics..."))
        let outOfScopeActions = await core.recordedOutOfScopeActions()
        XCTAssertEqual(outOfScopeActions, [])
        XCTAssertNil(model.statusBanner)
    }

    func testS220CoreBridgeResolutionCapabilityIsSupported() {
        XCTAssertEqual(CoreBridge().iCloudConflictResolutionCapability, .supported)
    }

    @MainActor
    func testS125SheetDefinesThreeStrategiesAndTrashBoundary() async {
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
        XCTAssertTrue(body.contains("Single-version resolution requires system Trash"))
        XCTAssertTrue(body.contains("requires Core support to clear conflict state and write change_log"))
        XCTAssertTrue(body.contains("S1-25-core-resolution-blocked"))
    }

    @MainActor
    func testS125ValidationErrorStateMapsCoreError() async {
        let failedValidator = S125RecordingPathValidator(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/s125-repo"))
        )
        let mapper = S125RecordingErrorMapper(mapping: .s125Mapping(
            kind: .permissionDenied,
            rawContext: "/tmp/s125-repo"
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
        XCTAssertEqual(recordedErrors, [CoreError.PermissionDenied(path: "/tmp/s125-repo")])
        XCTAssertFalse(failedModel.canApplyKeepBoth)
        XCTAssertTrue(failedBody.contains("S1-25-C1-21-error-mapping"))
        XCTAssertTrue(failedBody.contains("Repository check failed: PermissionDenied"))
        XCTAssertTrue(failedBody.contains("Retry repository check"))
    }

    @MainActor
    func testS125SupportedResolverCompletesRefreshAndChangeLogEvidence() async {
        let conflictFile = FileEntrySnapshot.s125ConflictFixture(id: 127)
        let core = S125RecordingMainCore(files: [conflictFile])
        let resolver = S125RecordingICloudConflictResolver(
            result: .success(ICloudConflictResolutionResult(
                focusFileID: conflictFile.id,
                didClearConflictState: true,
                didWriteChangeLog: true
            ))
        )
        let model = MainFileListModel(
            opening: .s125Fixture(repoPath: "/tmp/s125-repo", files: [conflictFile]),
            fileLister: core,
            fileDetailer: core,
            iCloudConflictResolver: resolver,
            changeLogLister: core,
            externalChangesSyncer: core,
            errorMapper: S125RecordingErrorMapper(mapping: .s125Mapping()),
            diagnosticsCollector: core
        )

        await model.selectFiles([conflictFile.id])
        model.beginICloudConflictResolution(fileID: conflictFile.id)
        await model.applyKeepBothICloudConflict(fileID: conflictFile.id)

        let requests = await resolver.recordedRequests()
        XCTAssertEqual(requests.map(\.strategy), [.keepBoth])
        XCTAssertEqual(requests.first?.repoPath, "/tmp/s125-repo")
        XCTAssertEqual(requests.first?.fileID, conflictFile.id)
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.iCloudConflictResolutionState, .idle)
        XCTAssertEqual(model.statusBanner, .resolvedICloudConflict(fileID: conflictFile.id, strategy: .keepBoth))
        XCTAssertEqual(model.detailLogState.s125LoadedFileID, conflictFile.id)
    }

    @MainActor
    private func makeMainFileListModel(
        conflictFile: FileEntrySnapshot,
        core: S125RecordingMainCore,
        errorMapper: S125RecordingErrorMapper = S125RecordingErrorMapper(mapping: .s125Mapping())
    ) -> MainFileListModel {
        MainFileListModel(
            opening: .s125Fixture(repoPath: "/tmp/s125-repo", files: [conflictFile]),
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
    private func makeDetailPaneBody(model: MainFileListModel) -> String {
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
            repoPath: "/tmp/s125-repo",
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
            writeActionDisabledReason: model.writeActionDisabledReason,
            noteModel: DetailNoteModel(
                repoPath: "/tmp/s125-repo",
                noteStore: S125NoopNoteStore(),
                errorMapper: S125RecordingErrorMapper(mapping: .s125Mapping())
            )
        )

        return s125IntegrationMirrorDescription(of: detailPane.body)
    }

    @MainActor
    private func makeReadyICloudConflictModel() async -> ICloudConflictMinimalModel {
        let validator = S125RecordingPathValidator(result: .success(.s125ICloudConflictFixture()))
        let model = makeICloudConflictModel(pathValidator: validator)
        await model.validateRepositoryPath()
        return model
    }

    @MainActor
    private func makeICloudConflictModel(
        pathValidator: CoreRepositoryPathValidating,
        errorMapper: CoreErrorMapping = S125RecordingErrorMapper(mapping: .s125Mapping())
    ) -> ICloudConflictMinimalModel {
        ICloudConflictMinimalModel(
            repoPath: "/tmp/s125-repo",
            originalVersion: .s125Original(repoPath: "/tmp/s125-repo"),
            conflictedCopyVersion: .s125ConflictedCopy(repoPath: "/tmp/s125-repo"),
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
    ) -> String {
        s125IntegrationMirrorDescription(of: ICloudConflictMinimalSheet(
            model: model,
            resolutionState: resolutionState,
            resolutionCapability: resolutionCapability,
            isTrashAvailable: isTrashAvailable,
            onCancel: {},
            onApply: { _ in },
            onCollectDiagnostics: {}
        ).body)
    }
}
