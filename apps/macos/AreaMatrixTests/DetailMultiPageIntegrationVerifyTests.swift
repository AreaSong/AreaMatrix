@testable import AreaMatrix
import XCTest

final class DetailMultiPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testBatchAddTagsUndoActionLogCoreLoadsActionLogExecutesUndoAndBlocksUnsafeAction() async {
        let action = UndoActionRecordSnapshot.batchAddTagsPendingBatchAddTags()
        var blockedAction = action
        blockedAction.status = .blocked
        blockedAction.canUndo = false
        blockedAction.disabledReason = "External change prevents undo."
        let undoStore = BatchAddTagsRecordingUndoStore(results: [
            .list(.success([action])),
            .undo(.success(.batchAddTagsExecutedBatchAddTags())),
            .list(.success([blockedAction]))
        ])
        let mapper = StaticCoreErrorMapper(mapping: .batchAddTagsUndoFailure())
        let load = await BatchTagUndoAction.loadAction(
            repoPath: "/tmp/repo",
            undoToken: action.actionID,
            undoStore: undoStore,
            errorMapper: mapper
        )
        let applied = await BatchTagUndoAction.undo(
            repoPath: "/tmp/repo",
            action: action,
            undoStore: undoStore,
            errorMapper: mapper
        )
        let blockedLoad = await BatchTagUndoAction.loadAction(
            repoPath: "/tmp/repo",
            undoToken: blockedAction.actionID,
            undoStore: undoStore,
            errorMapper: mapper
        )

        XCTAssertEqual(load.action, action)
        XCTAssertEqual(applied.result, .batchAddTagsExecutedBatchAddTags())
        XCTAssertEqual(blockedLoad.unavailableReason, "External change prevents undo.")
        await undoStore.assertUndoActionListRequests(["/tmp/repo", "/tmp/repo"])
        await undoStore.assertUndoActionRequests(["/tmp/repo|\(action.actionID)"])
    }

    @MainActor
    func testBatchAddTagsUndoActionLogCoreMapsUndoFailureWithoutMockingSuccess() async {
        let action = UndoActionRecordSnapshot.batchAddTagsPendingBatchAddTags()
        let undoStore =
            BatchAddTagsRecordingUndoStore(results: [.undo(.failure(CoreError.Conflict(path: "docs/contract.pdf")))])
        let applied = await BatchTagUndoAction.undo(
            repoPath: "/tmp/repo",
            action: action,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchAddTagsUndoFailure())
        )

        XCTAssertNil(applied.result)
        XCTAssertEqual(applied.failure, .batchAddTagsUndoFailure())
        await undoStore.assertUndoActionRequests(["/tmp/repo|\(action.actionID)"])
    }

    @MainActor
    func testBatchAddTagsUndoActionLogCoreApplyCompletionHandsUndoActionToMainWindowToast() async {
        let action = UndoActionRecordSnapshot.batchAddTagsPendingBatchAddTags()
        let undoStore = BatchAddTagsRecordingUndoStore(results: [.list(.success([action]))])
        let completion = await BatchTagUndoAction.completionAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .batchAddTagsBatchAddTagsReport(),
            failure: nil,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchAddTagsUndoFailure())
        )

        XCTAssertEqual(completion.undoState, .ready(action))
        XCTAssertTrue(completion.closesSheet)
        await undoStore.assertUndoActionListRequests(["/tmp/repo"])
    }

    @MainActor
    func testBatchAddTagsUndoActionLogCoreUndoRefreshTargetsDriveVisibleRefreshes() async {
        let action = UndoActionRecordSnapshot.batchAddTagsPendingBatchAddTags()
        let undoStore = BatchAddTagsRecordingUndoStore(results: [
            .undo(.success(.batchAddTagsExecutedBatchAddTags())),
            .list(.success([.batchAddTagsExecutedActionLogRow()]))
        ])
        let applied = await BatchTagUndoAction.undo(
            repoPath: "/tmp/repo",
            action: action,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchAddTagsUndoFailure())
        )
        guard let result = applied.result else {
            return XCTFail("expected undo_action to return refresh_targets")
        }
        let plan = BatchTagUndoRefreshPlan(refreshTargets: result.refreshTargets)
        let refreshed = await BatchTagUndoAction.refreshActionLog(
            repoPath: "/tmp/repo",
            actionID: result.actionID,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchAddTagsUndoFailure())
        )

        XCTAssertTrue(plan.refreshesSelectionDetails)
        XCTAssertTrue(plan.refreshesChangeLog)
        XCTAssertTrue(plan.refreshesUndoActions)
        XCTAssertEqual(refreshed.action, .batchAddTagsExecutedActionLogRow())
        await undoStore.assertUndoActionRequests(["/tmp/repo|\(action.actionID)"])
        await undoStore.assertUndoActionListRequests(["/tmp/repo"])
    }

    @MainActor
    func testDetailMultiSelectPageIntegrationUsesRealListFilesCoreAndGetFileDetailCoreCoreBridgeForMultiSelection(
    ) async throws {
        let repoURL = try makeDetailMultiSelectTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }
        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "contract".write(to: docsURL.appendingPathComponent("contract.pdf"), atomically: true, encoding: .utf8)
        try "notes".write(to: docsURL.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let config = try await bridge.loadConfig(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")
        let model = MainFileListModel(
            opening: RepositoryOpeningResult(config: config, tree: tree, currentCategoryFiles: []),
            fileLister: bridge,
            fileDetailer: bridge,
            errorMapper: bridge
        )

        await model.loadCurrentCategory("docs")
        let selectedIDs = Set(model.files.map(\.id))
        await model.selectFiles(selectedIDs)
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)

        XCTAssertEqual(selectedIDs.count, 2)
        XCTAssertEqual(model.selection, .multiple(selectedIDs))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.selectedFileNoteWriteBlock)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(model.detailLogState, .notLoaded)
        XCTAssertFalse(model.isDetailLoading)
        XCTAssertEqual(summary.selectedCount, 2)
        XCTAssertEqual(summary.unresolvedMetadataCount, 0)
        XCTAssertFalse(summary.warningMessages.contains("部分选中项无法读取元数据"))
        XCTAssertEqual(summary.fileTypeRows.map(\.label).sorted(), ["Markdown", "PDF"])
    }

    @MainActor
    func testDetailMultiSelectPageIntegrationExitsToSingleAndEmptyWithoutBatchWriteActions() async {
        let first = FileEntrySnapshot.detailMultiSelectFixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.detailMultiSelectFixture(id: 2, currentName: "b.pdf")
        let detailer = RecordingFileDetailer(results: [
            .success(first),
            .success(second),
            .success(second)
        ])
        let model = MainFileListModel(
            opening: .detailMultiSelectFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: NoopFileLister(),
            fileDetailer: detailer,
            errorMapper: StaticCoreErrorMapper(mapping: .detailMultiSelectDbMapping())
        )

        await model.selectFiles([first.id, second.id])
        model.beginRename()
        model.beginChangeCategory()
        model.beginDelete()

        XCTAssertEqual(model.selection, .multiple([first.id, second.id]))
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.selectedFileNoteWriteBlock)
        XCTAssertEqual(model.detailLogState, .notLoaded)

        await model.selectFiles([second.id])
        XCTAssertEqual(model.selection, .single(second.id))
        XCTAssertEqual(model.selectedFileDetail, second)

        await model.selectFiles([])
        XCTAssertEqual(model.selection, .none)
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(model.detailLogState, .notLoaded)
    }

    @MainActor
    func testDetailMultiSelectPageIntegrationKeepsCopyPathsAvailableOnPartialGetFileDetailCoreFailure() async {
        let available = FileEntrySnapshot.detailMultiSelectFixture(id: 10, currentName: "available.pdf")
        let stale = FileEntrySnapshot.detailMultiSelectFixture(id: 11, currentName: "stale.pdf")
        let mapping = CoreErrorMappingSnapshot.detailMultiSelectFileNotFoundMapping()
        let model = MainFileListModel(
            opening: .detailMultiSelectFixture(repoPath: "/tmp/repo", files: [available, stale]),
            fileLister: NoopFileLister(),
            fileDetailer: RecordingFileDetailer(results: [
                .success(available),
                .failure(CoreError.FileNotFound(path: stale.path))
            ]),
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        await model.selectFiles([available.id, stale.id])
        let summary = MultiSelectionDetailSummary(selection: model.selection, files: model.files)
        let copier = ShellRecordingPathCopier()
        let announcer = RecordingAccessibilityAnnouncer()
        let shell = OnboardingModel(
            pathCopier: copier,
            accessibilityAnnouncer: announcer
        )
        shell.copyMainListPaths(
            opening: .detailMultiSelectFixture(repoPath: "/tmp/repo", files: model.files),
            relativePaths: summary.paths
        )

        XCTAssertEqual(model.selection, .multiple([available.id, stale.id]))
        XCTAssertEqual(model.detailErrorMapping, mapping)
        XCTAssertEqual(summary.paths, [available.path, stale.path])
        copier.assertMultiPathRequests([ShellRecordingPathCopier.MultiPathRequest(
            repoPath: "/tmp/repo",
            relativePaths: [available.path, stale.path]
        )])
        XCTAssertEqual(shell.toastMessage, L10n.pluralMessage("main-list.paths-copied", count: 2))
        announcer.assertAnnouncements(["2 paths copied."])
    }
}
