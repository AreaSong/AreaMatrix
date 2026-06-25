@testable import AreaMatrix
import SwiftUI
import XCTest

// swiftlint:disable file_length
final class ImportBatchICloudPageIntegrationTests: XCTestCase {
    func testBatchAddTagsPageIntegrationAllowsReadOnlyEntryButBlocksApply() {
        let disabledReason = MainFileWriteActionDisabledReason.repoReadOnly.rawValue
        let help = BatchAddTagsEntryPolicy.openHelp(disabledReason: disabledReason)
        let pending = BatchTagValidation.pendingStateAfterAdding(
            input: "urgent",
            pendingTags: [],
            catalog: .batchAddTagsTagCatalogFixture(fileID: 31),
            disabledReason: disabledReason
        )

        XCTAssertEqual(
            help,
            "Repository is read-only. You can still review selected files and tag candidates."
        )
        XCTAssertEqual(pending.fieldError, "Tag store is read-only.")
        XCTAssertFalse(BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: false,
            disabledReason: disabledReason,
            input: "",
            pendingTags: ["urgent"],
            fieldError: nil,
            selectedCount: 2
        )))
    }

    func testBatchAddTagsPageIntegrationBuildsListAndCommandPaletteRoutesForSameSheet() {
        let first = FileEntrySnapshot.batchAddTagsRouteFixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.batchAddTagsRouteFixture(id: 2, currentName: "b.pdf")
        let route = BatchAddTagsRoute(
            source: .listContextMenu,
            fileIDs: [first.id, second.id],
            selectedCount: 2,
            disabledReason: BatchAddTagsEntryPolicy.disabledReason(
                selectedFiles: [first, second],
                isReadOnly: false,
                isLoading: false,
                writeLockedFileIDs: []
            )
        )
        let commandRoute = BatchAddTagsRoute(
            source: .commandPalette,
            fileIDs: route.fileIDs,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason
        )

        XCTAssertEqual(route.fileIDs, [1, 2])
        XCTAssertEqual(route.selectedCount, 2)
        XCTAssertNil(route.disabledReason)
        XCTAssertEqual(commandRoute.fileIDs, route.fileIDs)
        XCTAssertEqual(commandRoute.selectedCount, route.selectedCount)
    }

    func testBatchAddTagsCommandPaletteRouteExposesContextualAddTagsCommand() {
        var commandQuery = "tag"
        let body = batchAddTagsRouteMirrorDescription(of: SearchCommandPaletteRouteView(
            query: Binding(get: { commandQuery }, set: { commandQuery = $0 }),
            state: .idle,
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        ).body)

        XCTAssertTrue(body.contains("command-palette-search-route"))
        XCTAssertTrue(body.contains("CommandPaletteView"))
    }

    @MainActor
    func testUndoToastUndoActionLogCoreLoadsLatestUndoActionFromCoreActionLog() async {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let undoStore = UndoToastRecordingUndoStore(results: [.list(.success([action]))])
        let result = await BatchTagUndoAction.loadLatestAction(
            repoPath: "/tmp/repo",
            undoStore: undoStore,
            errorMapper: UndoToastErrorMapper()
        )

        XCTAssertEqual(result.toastState, .ready(action))
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo"])
        XCTAssertEqual(action.summary, "Moved 3 files to Trash.")
    }

    @MainActor
    func testUndoToastUndoActionLogCoreRefreshLatestToastCoversUndoableWriteSummaries() async {
        let actions: [UndoActionRecordSnapshot] = [
            .undoToastRenamedFiles(),
            .undoToastMovedFilesToCategory(),
            .undoToastMovedFilesToTrash(),
            .undoToastAddedTags()
        ]

        for action in actions {
            let undoStore = UndoToastRecordingUndoStore(results: [.list(.success([action]))])
            let state = await BatchTagUndoAction.refreshLatestToastState(
                repoPath: "/tmp/repo",
                undoStore: undoStore,
                errorMapper: UndoToastErrorMapper()
            )

            XCTAssertEqual(state, .ready(action))
            let listRequests = await undoStore.listRequests()
            XCTAssertEqual(listRequests, ["/tmp/repo"])
        }
    }

    @MainActor
    func testUndoToastUndoActionLogCoreExecutesUndoAndUsesRefreshTargets() async {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let undoStore = UndoToastRecordingUndoStore(results: [
            .undo(.success(.undoToastUndoneTrashMove())),
            .list(.success([.undoToastExecutedTrashMove()]))
        ])

        let applied = await BatchTagUndoAction.undo(
            repoPath: "/tmp/repo",
            action: action,
            undoStore: undoStore,
            errorMapper: UndoToastErrorMapper()
        )
        let plan = BatchTagUndoRefreshPlan(refreshTargets: applied.result?.refreshTargets ?? [])
        let refreshed = await BatchTagUndoAction.refreshActionLog(
            repoPath: "/tmp/repo",
            actionID: action.actionID,
            undoStore: undoStore,
            errorMapper: UndoToastErrorMapper()
        )

        XCTAssertEqual(applied.result, .undoToastUndoneTrashMove())
        XCTAssertTrue(plan.refreshesCurrentList)
        XCTAssertTrue(plan.refreshesUndoActions)
        XCTAssertEqual(refreshed.action, .undoToastExecutedTrashMove())
        let undoRequests = await undoStore.undoRequests()
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(undoRequests, ["/tmp/repo|\(action.actionID)"])
        XCTAssertEqual(listRequests, ["/tmp/repo"])
    }

    @MainActor
    func testUndoToastUndoActionLogCoreBlockedUndoKeepsVisibleReasonWithoutExecuting() async {
        let action = UndoActionRecordSnapshot.undoToastBlockedRename()
        let undoStore = UndoToastRecordingUndoStore(results: [.list(.success([action]))])
        let result = await BatchTagUndoAction.loadLatestAction(
            repoPath: "/tmp/repo",
            undoStore: undoStore,
            errorMapper: UndoToastErrorMapper()
        )

        XCTAssertEqual(result.toastState, .disabled(action, reason: "External change prevents undo."))
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(undoRequests, [])
    }

    func testUndoToastUndoActionLogCoreViewHistoryCreatesToastScopedRequest() {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let request = UndoToastHistoryRequest(source: .viewHistory, state: .ready(action), actionLogRefreshFailure: nil)

        XCTAssertTrue(request.id.contains("viewHistory:\(action.actionID)"))
        XCTAssertEqual(request.source, .viewHistory)
        XCTAssertEqual(request.state, .ready(action))
    }

    func testUndoToastUndoActionLogCoreViewDetailsCreatesToastScopedFailureRequest() {
        let action = UndoActionRecordSnapshot.undoToastMovedFilesToTrash()
        let failure = CoreErrorMappingSnapshot.undoToastUndoFailure()
        let request = UndoToastHistoryRequest(
            source: .viewDetails,
            state: .failed(failure, previous: action),
            actionLogRefreshFailure: nil
        )

        XCTAssertTrue(request.id.contains("viewDetails:failed:\(action.actionID):\(failure.kind.rawValue)"))
        XCTAssertEqual(request.source, .viewDetails)
        XCTAssertEqual(request.state, .failed(failure, previous: action))
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func testImportBatchICloudPendingRowsDoNotSilentlyImportUnavailableRows() async {
        let localURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let request = importBatchBatchRequest(urls: [localURL, cloudURL])
        let rows = [
            importBatchReadyBatchRow(url: localURL),
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: cloudURL,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        ]
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.iCloudPlaceholderCount, 1)
        XCTAssertNil(model.importDisabledReason)

        model.markICloudPlaceholderPending(rowID: rows[1].id)
        XCTAssertNil(model.importDisabledReason)

        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.succeededEntries.first?.storageMode, "Copied")
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            skipped: 0,
            pending: 1,
            items: [
                ImportBatchProgressSnapshot.Item(
                    fileID: 42,
                    sourcePath: "/tmp/source.pdf",
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .done,
                    errorMessage: nil
                )
            ]
        ))
        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
    }

    @MainActor
    func testImportBatchAllICloudPendingStillBlocksImport() {
        let cloudURLs = [
            URL(fileURLWithPath: "/tmp/iCloudOnlyA.pdf.icloud"),
            URL(fileURLWithPath: "/tmp/iCloudOnlyB.pdf.icloud")
        ]
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: cloudURLs,
            kind: .multipleItems(2),
            availableCategories: ["inbox", "finance"]
        )
        let rows = cloudURLs.map { url in
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: url,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        }
        let model = ImportBatchCopyImportModel(
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: ImportSingleFileRecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)

        XCTAssertEqual(model.iCloudPlaceholderCount, 2)
        XCTAssertEqual(model.importDisabledReason, "没有可导入的批量项目")
    }
}

extension MainRepositoryDetailPaneTagActions {
    static var noop: MainRepositoryDetailPaneTagActions {
        let noAction: () -> Void = {}; let noStringAction: (String) -> Void = { _ in }
        let noEditAction: (String, String) -> Void = { _, _ in }; let noBatchAction: (BatchTagUndoState)
            -> Void = { _ in
            }
        return MainRepositoryDetailPaneTagActions(
            aiSuggestionState: .idle, aiBatchSuggestionState: .idle, onLoadTags: noAction, onRetryTags: noAction,
            onAddTag: noStringAction, onRemoveTag: noStringAction,
            onLoadSuggestions: noAction, onRetrySuggestions: noAction,
            onToggleSuggestion: noStringAction, onSelectAllSuggestions: noAction,
            onClearSuggestions: noAction, onStartEditingSuggestions: noAction, onCancelEditingSuggestions: noAction,
            onEditSuggestionDisplayName: noEditAction, onEditSuggestionSlug: noEditAction,
            onRegenerateSuggestionSlug: noStringAction, onApplySuggestions: noAction,
            onApplyEditedSuggestions: noAction, onRetryFailedSuggestions: noAction,
            onLoadAISuggestions: noAction, onRetryAISuggestions: noAction,
            onToggleAISuggestion: noStringAction, onApplySingleAISuggestion: noStringAction,
            onSelectHighConfidenceAISuggestions: noAction,
            onClearAISuggestions: noAction, onStartEditingAISuggestions: noAction,
            onCancelEditingAISuggestions: noAction,
            onEditAISuggestionDisplayName: noEditAction, onEditAISuggestionSlug: noEditAction,
            onRegenerateAISuggestionSlug: noStringAction, onApplyAISuggestions: noAction,
            onApplyEditedAISuggestions: noAction, onRetryFailedAISuggestions: noAction,
            aiBatchActions: .noop, onOpenAISettings: noAction, onSuggestionPresentationConsumed: { _ in },
            onUndoTagChange: noAction, onDismissTagUndoToast: noAction, onBatchTagUndoStateChange: noBatchAction
        )
    }
}

private extension FileEntrySnapshot {
    static func batchAddTagsRouteFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "batchAddTags-route-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private func batchAddTagsRouteMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendBatchAddTagsRouteMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendBatchAddTagsRouteMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendBatchAddTagsRouteMirrorDescription(of: child.value, to: &lines)
    }
}

private extension UndoActionRecordSnapshot {
    static func undoToastMovedFilesToTrash() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-trash-3",
            kind: "trash_delete",
            summary: "Moved 3 files to Trash.",
            affectedCount: 3,
            affectedFileNames: ["a.pdf", "b.pdf", "c.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_010
        )
    }

    static func undoToastBlockedRename() -> UndoActionRecordSnapshot {
        var action = undoToastRenamedFiles()
        action.actionID = "undo-rename-blocked"
        action.status = .blocked
        action.canUndo = false
        action.disabledReason = "External change prevents undo."
        return action
    }

    static func undoToastRenamedFiles() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-rename-12",
            kind: "rename_files",
            summary: "Renamed 12 files.",
            affectedCount: 12,
            affectedFileNames: ["a.pdf", "b.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_020,
            updatedAt: 1_700_000_020
        )
    }

    static func undoToastMovedFilesToCategory() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-move-finance-5",
            kind: "move_files",
            summary: "Moved 5 files to finance.",
            affectedCount: 5,
            affectedFileNames: ["statement.pdf", "invoice.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_030,
            updatedAt: 1_700_000_030
        )
    }

    static func undoToastAddedTags() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-tags-24",
            kind: "batch_add_tags",
            summary: #"Added tag "finance" to 24 files."#,
            affectedCount: 24,
            affectedFileNames: ["invoice.pdf", "receipt.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_040,
            updatedAt: 1_700_000_040
        )
    }

    static func undoToastExecutedTrashMove() -> UndoActionRecordSnapshot {
        var action = undoToastMovedFilesToTrash()
        action.status = .executed
        action.canUndo = false
        action.updatedAt = 1_700_000_030
        return action
    }
}

private extension UndoActionResultSnapshot {
    static func undoToastUndoneTrashMove() -> UndoActionResultSnapshot {
        UndoActionResultSnapshot(
            actionID: "undo-trash-3",
            status: .executed,
            summary: "Undone: moved 3 files to Trash.",
            affectedCount: 3,
            refreshTargets: ["files", "undo_actions", "change_log"],
            completedAt: 1_700_000_040
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func undoToastUndoFailure() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "Undo failed",
            severity: .medium,
            suggestedAction: "View details in Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }
}

private actor UndoToastRecordingUndoStore: CoreUndoActionLogging {
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
        guard !results.isEmpty else { return [] }
        guard case let .list(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected listUndoActions")
        }
        return try result.get()
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: actionID)
        }
        guard case let .undo(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected undoAction")
        }
        return try result.get()
    }

    func listRequests() -> [String] {
        recordedListRequests
    }

    func undoRequests() -> [String] {
        recordedUndoRequests
    }
}

private actor UndoToastErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind(for: error),
            userMessage: "Undo failed",
            severity: .medium,
            suggestedAction: "View details in Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }

    private func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        ImportBatchICloudErrorKindMapper.kind(for: error)
    }
}
