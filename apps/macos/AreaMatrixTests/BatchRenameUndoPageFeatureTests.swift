@testable import AreaMatrix
import Foundation
import XCTest

final class BatchRenameUndoPageFeatureTests: XCTestCase {
    @MainActor
    func testBatchRenameUndoUndoActionLogCoreBatchRenameLoadsUndoActionFromCoreActionLog() async {
        let action = UndoActionRecordSnapshot.batchRenameUndoPendingBatchRename()
        let undoStore = BatchRenameUndoStore(results: [.list(.success([action]))])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .report(token: action.actionID),
            failure: nil,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertEqual(state, .ready(action))
        let listRequests = await undoStore.listRequests()
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo"])
        XCTAssertEqual(undoRequests, [])
    }

    @MainActor
    func testBatchRenameUndoUndoActionLogCoreBatchRenameReportsUnavailableWhenUndoTokenIsMissing() async {
        let undoStore = BatchRenameUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .report(token: nil),
            failure: nil,
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertEqual(state, .unavailable(reason: "Undo is unavailable for this rename result."))
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [])
    }

    @MainActor
    func testBatchRenameUndoUndoActionLogCoreBatchRenameDoesNotFakeUndoStateOnApplyFailure() async {
        let undoStore = BatchRenameUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: nil,
            failure: .batchRenameUndoUndoFailure(),
            undoStore: undoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertNil(state)
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [])
    }

    @MainActor
    func testRedoActionLogRedoActionLogCoreRedoLatestUsesRealRedoActionLogAndRefreshesSnapshot() async {
        let undo = UndoActionRecordSnapshot.batchRenameUndoPendingBatchRename()
        let redo = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let redoStore = RedoActionLogRecordingRedoStore(results: [
            .redo(.success(.redoActionLogRedoneMove())),
            .list(.success([.redoActionLogExecutedMoveRedo()]))
        ])
        let undoStore = BatchRenameUndoStore(results: [.list(.success([undo]))])

        let state = await UndoHistoryActionLog.redoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [undo], redoActions: [redo]),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        guard case let .redone(result, refreshed) = state else {
            return XCTFail("expected redone, got \(state)")
        }
        XCTAssertEqual(result, .redoActionLogRedoneMove())
        XCTAssertEqual(refreshed.redoActions, [.redoActionLogExecutedMoveRedo()])
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, ["/tmp/repo|\(redo.actionID)"])
    }

    @MainActor
    func testRedoActionLogRedoActionLogCoreClearedRedoShowsReasonWithoutExecuting() async {
        let cleared = RedoActionRecordSnapshot.redoActionLogClearedMoveRedo()
        let redoStore = RedoActionLogRecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.redoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [], redoActions: [cleared]),
            undoStore: BatchRenameUndoStore(results: []),
            redoStore: redoStore,
            errorMapper: StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())
        )

        XCTAssertEqual(state.failure?.kind, .conflict)
        XCTAssertEqual(state.failure?.userMessage, "Redo was cleared by the next file operation.")
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, [])
    }

    @MainActor
    func testRedoActionLogRedoActionLogCoreFeedbackLoadsLatestRedoAndExecutesThroughStore() async {
        let action = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let redoStore = RedoActionLogRecordingRedoStore(results: [
            .list(.success([action])),
            .redo(.success(.redoActionLogRedoneMove()))
        ])
        let errorMapper = StaticCoreErrorMapper(mapping: .batchRenameUndoUndoFailure())

        let loaded = await RedoActionFeedback.loadLatestAction(
            repoPath: "/tmp/repo",
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        XCTAssertEqual(loaded.feedbackState(), .available(action))

        let applied = await RedoActionFeedback.redo(
            repoPath: "/tmp/repo",
            action: action,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        XCTAssertEqual(applied.result, .redoActionLogRedoneMove())
        XCTAssertNil(applied.failure)
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, ["/tmp/repo|\(action.actionID)"])
    }
}

final class BatchRenameUndoBatchRenameVerifyTests: XCTestCase {
    func testBatchRenameUndoPageIntegrationUsesRealCorePreviewApplyUndoAndExitRefresh() async throws {
        let context = try await makeBatchRenameUndoIntegrationContext()
        defer { context.cleanUp() }

        let route = makeBatchRenameUndoRoute(context: context)
        XCTAssertEqual(route.fileIDs, [context.indexOnly.id, context.repoOwned.id])
        XCTAssertNil(route.disabledReason)

        let rule = BatchRenameRuleSnapshot(
            mode: .keepBaseSequence,
            prefix: nil,
            dateSource: nil,
            dateFormat: nil,
            separator: "_",
            startNumber: 1,
            padding: 2,
            find: nil,
            replacement: nil,
            caseSensitive: false
        )
        let preview = try await context.bridge.previewBatchRename(
            repoPath: context.repoURL.path,
            fileIDs: route.fileIDs,
            rule: rule
        )
        assertBatchRenameUndoPreview(preview, context: context, route: route)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedOriginalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedRenamedURL.path))

        let report = try await context.bridge.batchRename(
            repoPath: context.repoURL.path,
            fileIDs: route.fileIDs,
            rule: preview.rule,
            previewToken: preview.previewToken
        )
        try await assertBatchRenameUndoApplied(report, context: context)

        let undoState = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: context.repoURL.path,
            report: report,
            failure: nil,
            undoStore: context.bridge,
            errorMapper: context.bridge
        )
        let action = try XCTUnwrap(undoState?.executableAction)
        XCTAssertEqual(action.actionID, report.undoToken)
        XCTAssertEqual(action.kind, "rename_files")
        XCTAssertTrue(action.canUndo)

        let undo = try await context.bridge.undoAction(repoPath: context.repoURL.path, actionID: action.actionID)
        XCTAssertEqual(undo.status, .executed)
        XCTAssertTrue(undo.refreshTargets.contains("files"))
        XCTAssertTrue(undo.refreshTargets.contains("undo_actions"))
        try await assertBatchRenameUndoUndoRestored(context)
    }

    func testBatchRenameUndoPageIntegrationKeepsApplyDisabledForRealNoChangePreview() async throws {
        let context = try await makeBatchRenameUndoIntegrationContext()
        defer { context.cleanUp() }
        let rule = BatchRenameRuleSnapshot.batchRenameRule(.prefix)

        let preview = try await context.bridge.previewBatchRename(
            repoPath: context.repoURL.path,
            fileIDs: [context.repoOwned.id],
            rule: rule
        )

        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.unchangedCount, 1)
        XCTAssertEqual(preview.blockedCount, 0)
        XCTAssertEqual(preview.items.map(\.status), [.unchanged])
        XCTAssertEqual(preview.applyBlockedReason, "No filename changes.")
        XCTAssertFalse(BatchRenameValidation.canApply(
            fileIDs: [context.repoOwned.id],
            preview: preview,
            rule: rule,
            disabledReason: nil,
            isApplying: false
        ))
    }
}

private struct BatchRenameUndoIntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let repoOwnedOriginalURL: URL
    let repoOwnedRenamedURL: URL
    let indexOnlySourceURL: URL
    let bridge: CoreBridge
    let repoOwned: FileEntrySnapshot
    let indexOnly: FileEntrySnapshot

    func cleanUp() {
        removeTestTemporaryItems(repoURL, sourceRootURL)
    }
}

private func makeBatchRenameUndoIntegrationContext() async throws -> BatchRenameUndoIntegrationContext {
    let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "batchRenameUndo-repo")
    let sourceRootURL = try makeImportSingleFileTemporaryDirectory(prefix: "batchRenameUndo-source")
    let repoOwnedSourceURL = sourceRootURL.appendingPathComponent("owned-source.pdf")
    let indexOnlySourceURL = sourceRootURL.appendingPathComponent("indexed-source.pdf")
    try Data("repo owned bytes".utf8).write(to: repoOwnedSourceURL)
    try Data("indexed bytes".utf8).write(to: indexOnlySourceURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let repoOwned = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: repoOwnedSourceURL,
        overrideCategory: "docs",
        overrideFilename: "owned.pdf",
        duplicateStrategy: .skip
    )
    let indexOnly = try await bridge.importIndexedFile(
        repoPath: repoURL.path,
        sourceURL: indexOnlySourceURL,
        overrideCategory: "docs",
        overrideFilename: "indexed.pdf",
        duplicateStrategy: .skip
    )
    return BatchRenameUndoIntegrationContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        repoOwnedOriginalURL: repoURL.appendingPathComponent(repoOwned.path),
        repoOwnedRenamedURL: repoURL.appendingPathComponent("docs/owned_02.pdf"),
        indexOnlySourceURL: indexOnlySourceURL,
        bridge: bridge,
        repoOwned: repoOwned,
        indexOnly: indexOnly
    )
}

private func makeBatchRenameUndoRoute(context: BatchRenameUndoIntegrationContext) -> BatchRenameRoute {
    let filesInListOrder = [context.indexOnly, context.repoOwned]
    let summary = MultiSelectionDetailSummary(
        selection: .multiple([context.repoOwned.id, context.indexOnly.id]),
        files: filesInListOrder
    )
    return BatchRenameRoute(
        source: .listContextMenu,
        fileIDs: BatchRenameEntryPolicy.fileIDsForPreview(summary: summary),
        selectedFiles: summary.files,
        selectedCount: summary.selectedCount,
        disabledReason: MainFileBatchEntryPolicy.disabledReason(
            selectedFiles: summary.files,
            isReadOnly: false,
            isLoading: false,
            writeLockedFileIDs: []
        )
    )
}

private func assertBatchRenameUndoPreview(
    _ preview: BatchRenamePreviewReportSnapshot,
    context: BatchRenameUndoIntegrationContext,
    route: BatchRenameRoute
) {
    XCTAssertTrue(preview.canApply)
    XCTAssertEqual(preview.requestedFileCount, 2)
    XCTAssertEqual(preview.willRenameCount, 1)
    XCTAssertEqual(preview.displayOnlyCount, 1)
    XCTAssertEqual(preview.unchangedCount, 0)
    XCTAssertEqual(preview.blockedCount, 0)
    XCTAssertEqual(preview.conflictCount, 0)
    XCTAssertEqual(preview.items.map(\.fileID), route.fileIDs)
    XCTAssertEqual(preview.items.map(\.status), [.displayOnly, .ok])
    XCTAssertEqual(preview.items.map(\.newName), ["indexed_01.pdf", "owned_02.pdf"])
    XCTAssertEqual(preview.items.first?.fileID, context.indexOnly.id)
}

private func assertBatchRenameUndoApplied(
    _ report: BatchRenameReportSnapshot,
    context: BatchRenameUndoIntegrationContext
) async throws {
    XCTAssertEqual(report.requestedFileCount, 2)
    XCTAssertEqual(report.renamedCount, 1)
    XCTAssertEqual(report.displayNameUpdatedCount, 1)
    XCTAssertEqual(report.unchangedCount, 0)
    XCTAssertEqual(report.failedCount, 0)
    XCTAssertEqual(report.itemResults.map(\.status), [.displayNameUpdated, .renamed])
    XCTAssertNotNil(report.undoToken)
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedOriginalURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedRenamedURL.path))
    XCTAssertEqual(try Data(contentsOf: context.indexOnlySourceURL), Data("indexed bytes".utf8))
    let files = try await context.bridge.listFiles(repoPath: context.repoURL.path, filter: .currentCategory(nil))
    XCTAssertEqual(files.first { $0.id == context.indexOnly.id }?.currentName, "indexed_01.pdf")
    XCTAssertEqual(files.first { $0.id == context.repoOwned.id }?.currentName, "owned_02.pdf")
}

private func assertBatchRenameUndoUndoRestored(_ context: BatchRenameUndoIntegrationContext) async throws {
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedOriginalURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedRenamedURL.path))
    XCTAssertEqual(try Data(contentsOf: context.indexOnlySourceURL), Data("indexed bytes".utf8))
    let files = try await context.bridge.listFiles(repoPath: context.repoURL.path, filter: .currentCategory(nil))
    XCTAssertEqual(files.first { $0.id == context.indexOnly.id }?.currentName, "indexed.pdf")
    XCTAssertEqual(files.first { $0.id == context.repoOwned.id }?.currentName, "owned.pdf")
}

private typealias BatchRenameUndoStore = UndoActionRecordingTestStore

private extension UndoActionRecordSnapshot {
    static func batchRenameUndoPendingBatchRename() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-rename-files",
            kind: "rename_files",
            summary: "Renamed 2 files.",
            affectedCount: 2,
            affectedFileNames: ["old-a.pdf", "old-b.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_300,
            updatedAt: 1_700_000_300
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func batchRenameUndoUndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Could not load rename undo action.",
            severity: .medium,
            suggestedAction: "Open Undo History and refresh.",
            recoverability: .refreshRequired,
            rawContext: "batch-rename undo-action-log undo-action-log"
        )
    }
}
