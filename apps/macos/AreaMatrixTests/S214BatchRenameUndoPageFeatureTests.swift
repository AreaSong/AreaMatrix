@testable import AreaMatrix
import Foundation
import XCTest

final class S214BatchRenameUndoPageFeatureTests: XCTestCase {
    @MainActor
    func testS214C207BatchRenameLoadsUndoActionFromCoreActionLog() async {
        let action = UndoActionRecordSnapshot.s214PendingBatchRename()
        let undoStore = S214BatchRenameRecordingUndoStore(results: [.list(.success([action]))])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .report(token: action.actionID),
            failure: nil,
            undoStore: undoStore,
            errorMapper: BatchRenameErrorMapper(mapping: .s214UndoFailure())
        )

        XCTAssertEqual(state, .ready(action))
        let listRequests = await undoStore.listRequests()
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo"])
        XCTAssertEqual(undoRequests, [])
    }

    @MainActor
    func testS214C207BatchRenameReportsUnavailableWhenUndoTokenIsMissing() async {
        let undoStore = S214BatchRenameRecordingUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: .report(token: nil),
            failure: nil,
            undoStore: undoStore,
            errorMapper: BatchRenameErrorMapper(mapping: .s214UndoFailure())
        )

        XCTAssertEqual(state, .unavailable(reason: "Undo is unavailable for this rename result."))
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [])
    }

    @MainActor
    func testS214C207BatchRenameDoesNotFakeUndoStateOnApplyFailure() async {
        let undoStore = S214BatchRenameRecordingUndoStore(results: [])
        let state = await BatchRenameUndoAction.stateAfterBatchApply(
            repoPath: "/tmp/repo",
            report: nil,
            failure: .s214UndoFailure(),
            undoStore: undoStore,
            errorMapper: BatchRenameErrorMapper(mapping: .s214UndoFailure())
        )

        XCTAssertNil(state)
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, [])
    }
}

final class S214BatchRenamePageIntegrationVerifyTests: XCTestCase {
    func testS214PageIntegrationUsesRealCorePreviewApplyUndoAndExitRefresh() async throws {
        let context = try await makeS214IntegrationContext()
        defer { context.cleanUp() }

        let route = makeS214Route(context: context)
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
        assertS214Preview(preview, context: context, route: route)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedOriginalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedRenamedURL.path))

        let report = try await context.bridge.batchRename(
            repoPath: context.repoURL.path,
            fileIDs: route.fileIDs,
            rule: preview.rule,
            previewToken: preview.previewToken
        )
        try await assertS214Applied(report, context: context)

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
        try await assertS214UndoRestored(context)
    }

    func testS214PageIntegrationKeepsApplyDisabledForRealNoChangePreview() async throws {
        let context = try await makeS214IntegrationContext()
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

private struct S214IntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let repoOwnedOriginalURL: URL
    let repoOwnedRenamedURL: URL
    let indexOnlySourceURL: URL
    let bridge: CoreBridge
    let repoOwned: FileEntrySnapshot
    let indexOnly: FileEntrySnapshot

    func cleanUp() {
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: sourceRootURL)
    }
}

private func makeS214IntegrationContext() async throws -> S214IntegrationContext {
    let repoURL = try makeImportSingleFileTemporaryDirectory(prefix: "s214-repo")
    let sourceRootURL = try makeImportSingleFileTemporaryDirectory(prefix: "s214-source")
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
    return S214IntegrationContext(
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

private func makeS214Route(context: S214IntegrationContext) -> BatchRenameRoute {
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
        disabledReason: BatchRenameEntryPolicy.disabledReason(
            selectedFiles: summary.files,
            isReadOnly: false,
            isLoading: false,
            writeLockedFileIDs: []
        )
    )
}

private func assertS214Preview(
    _ preview: BatchRenamePreviewReportSnapshot,
    context: S214IntegrationContext,
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

private func assertS214Applied(
    _ report: BatchRenameReportSnapshot,
    context: S214IntegrationContext
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

private func assertS214UndoRestored(_ context: S214IntegrationContext) async throws {
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.repoOwnedOriginalURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoOwnedRenamedURL.path))
    XCTAssertEqual(try Data(contentsOf: context.indexOnlySourceURL), Data("indexed bytes".utf8))
    let files = try await context.bridge.listFiles(repoPath: context.repoURL.path, filter: .currentCategory(nil))
    XCTAssertEqual(files.first { $0.id == context.indexOnly.id }?.currentName, "indexed.pdf")
    XCTAssertEqual(files.first { $0.id == context.repoOwned.id }?.currentName, "owned.pdf")
}

private actor S214BatchRenameRecordingUndoStore: CoreUndoActionLogging {
    enum Result {
        case list(Swift.Result<[UndoActionRecordSnapshot], Error>)
        case undo(Swift.Result<UndoActionResultSnapshot, Error>)
    }

    private var results: [Result]
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(results: [Result]) {
        self.results = results
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard case let .list(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
        }
        return try result.get()
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard case let .undo(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected undo_action result")
        }
        return try result.get()
    }

    func listRequests() -> [String] { recordedListRequests }

    func undoRequests() -> [String] { recordedUndoRequests }

    private func consumeResult() throws -> Result {
        guard !results.isEmpty else { throw CoreError.Db(message: "missing undo action result") }
        return results.removeFirst()
    }
}

private extension UndoActionRecordSnapshot {
    static func s214PendingBatchRename() -> UndoActionRecordSnapshot {
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
    static func s214UndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Could not load rename undo action.",
            severity: .medium,
            suggestedAction: "Open Undo History and refresh.",
            recoverability: .refreshRequired,
            rawContext: "S2-14 C2-07 undo-action-log"
        )
    }
}
