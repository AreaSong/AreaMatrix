@testable import AreaMatrix
import AreaMatrixFeatureOperation
import Foundation
import XCTest

private func batchRenameUndoRepoOwnedSourceFilename() -> String {
    "owned-source.pdf"
}

private func batchRenameUndoIndexOnlySourceFilename() -> String {
    "indexed-source.pdf"
}

private func batchRenameUndoRepoOwnedFilename() -> String {
    "owned.pdf"
}

private func batchRenameUndoIndexOnlyFilename() -> String {
    "indexed.pdf"
}

private func batchRenameUndoRepoOwnedRenamedPath() -> String {
    "docs/\(batchRenameUndoRepoOwnedRenamedFilename())"
}

private func batchRenameUndoRepoOwnedRenamedFilename() -> String {
    "owned_02.pdf"
}

private func batchRenameUndoIndexOnlyRenamedFilename() -> String {
    "indexed_01.pdf"
}

private func batchRenameUndoIndexOnlyBytes() -> Data {
    Data("indexed bytes".utf8)
}

final class BatchRenameUndoIntegrationVerifyTests: XCTestCase {
    func testBatchRenameUndoPageIntegrationUsesRealCorePreviewApplyUndoAndExitRefresh() async throws {
        let context = try await makeBatchRenameUndoIntegrationContext()
        defer { context.cleanUp() }

        let route = makeBatchRenameUndoRoute(context: context)
        XCTAssertEqual(route.fileIDs, [context.indexOnly.id, context.repoOwned.id])
        XCTAssertNil(route.disabledReason)

        let rule = BatchRenameRuleSnapshot.testFixture(.keepBaseSequence) {
            $0.separator = "_"
            $0.startNumber = 1
            $0.padding = 2
        }
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
    let repoOwnedSourceURL = sourceRootURL.appendingPathComponent(batchRenameUndoRepoOwnedSourceFilename())
    let indexOnlySourceURL = sourceRootURL.appendingPathComponent(batchRenameUndoIndexOnlySourceFilename())
    try Data("repo owned bytes".utf8).write(to: repoOwnedSourceURL)
    try batchRenameUndoIndexOnlyBytes().write(to: indexOnlySourceURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let repoOwned = try await bridge.importCopiedFile(
        repoPath: repoURL.path,
        sourceURL: repoOwnedSourceURL,
        overrideCategory: "docs",
        overrideFilename: batchRenameUndoRepoOwnedFilename(),
        duplicateStrategy: .skip
    )
    let indexOnly = try await bridge.importIndexedFile(
        repoPath: repoURL.path,
        sourceURL: indexOnlySourceURL,
        overrideCategory: "docs",
        overrideFilename: batchRenameUndoIndexOnlyFilename(),
        duplicateStrategy: .skip
    )
    return BatchRenameUndoIntegrationContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        repoOwnedOriginalURL: repoURL.appendingPathComponent(repoOwned.path),
        repoOwnedRenamedURL: repoURL.appendingPathComponent(batchRenameUndoRepoOwnedRenamedPath()),
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
    XCTAssertEqual(preview.items.map(\.newName), [
        batchRenameUndoIndexOnlyRenamedFilename(),
        batchRenameUndoRepoOwnedRenamedFilename()
    ])
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
    XCTAssertEqual(try Data(contentsOf: context.indexOnlySourceURL), batchRenameUndoIndexOnlyBytes())
    let files = try await context.bridge.listFiles(repoPath: context.repoURL.path, filter: .currentCategory(nil))
    XCTAssertEqual(
        files.first { $0.id == context.indexOnly.id }?.currentName,
        batchRenameUndoIndexOnlyRenamedFilename()
    )
    XCTAssertEqual(
        files.first { $0.id == context.repoOwned.id }?.currentName,
        batchRenameUndoRepoOwnedRenamedFilename()
    )
}

private func assertBatchRenameUndoUndoRestored(_ context: BatchRenameUndoIntegrationContext) async throws {
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedOriginalURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedRenamedURL.path))
    XCTAssertEqual(try Data(contentsOf: context.indexOnlySourceURL), batchRenameUndoIndexOnlyBytes())
    let files = try await context.bridge.listFiles(repoPath: context.repoURL.path, filter: .currentCategory(nil))
    XCTAssertEqual(files.first { $0.id == context.indexOnly.id }?.currentName, batchRenameUndoIndexOnlyFilename())
    XCTAssertEqual(files.first { $0.id == context.repoOwned.id }?.currentName, batchRenameUndoRepoOwnedFilename())
}
