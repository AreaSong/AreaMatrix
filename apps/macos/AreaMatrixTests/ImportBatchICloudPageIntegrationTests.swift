@testable import AreaMatrix
import SwiftUI
import XCTest

final class ImportBatchICloudPageIntegrationTests: XCTestCase {
    func testBatchAddTagsPageIntegrationAllowsReadOnlyEntryButBlocksApply() {
        let disabledReason = MainFileWriteActionDisabledReason.repoReadOnly.message
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
            disabledReason: MainFileBatchEntryPolicy.disabledReason(
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
        assertTestMirrorDescription(of: SearchCommandPaletteRouteView(
            query: Binding(get: { commandQuery }, set: { commandQuery = $0 }),
            state: .idle,
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        ).body, contains: [
            "command-palette-search-route",
            "CommandPaletteView"
        ])
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
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
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
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)

        XCTAssertEqual(model.iCloudPlaceholderCount, 2)
        XCTAssertEqual(model.importDisabledReason, "没有可导入的批量项目")
    }
}
