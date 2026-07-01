@testable import AreaMatrix
import XCTest

final class ImportProgressPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testImportProgressMainListTemporaryImportRowsCanDriveDetailPane() {
        let rows = Self.runningProgress.items.map(ImportProgressListRow.init)

        XCTAssertEqual(rows.map(\.displayName), ["invoice.pdf", "contract.pdf", "later.pdf"])
        XCTAssertEqual(rows.map(\.statusText), ["Imported", "Copying file", "Queued"])
        XCTAssertEqual(rows[1].sourcePath, "/tmp/contract.pdf")
        XCTAssertEqual(rows[1].targetPath, "docs/contract.pdf")
    }

    @MainActor
    func testImportProgressFatalImportExitMustRouteThroughImportResultResultSummary() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.fatalProgress)
        model.failImportEntry(
            progress: Self.fatalProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalProgressError,
            retryContext: nil,
            recoveryCheck: .retryBlocked("Recovery state could not be confirmed.", nil)
        )
        model.stopImportProgressAndViewResults()

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 2, pending 1.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed, .skipped, .skipped, .pending])
        XCTAssertEqual(result.items[1].reason, "Storage write failed")
    }

    @MainActor
    func testUndoToastViewHistoryRequestBuildsSharedUndoHistoryPanelRoute() {
        let action = UndoActionRecordSnapshot.undoToastHistoryFixture()
        let request = UndoToastHistoryRequest(source: .viewHistory, state: .ready(action), actionLogRefreshFailure: nil)
        let content = MainRepositoryContentView(
            opening: .importSingleFileFixture(repoPath: "/tmp/repo"),
            state: .list,
            onImport: {},
            onDropImport: { _, _ in },
            errorMapper: StaticCoreErrorMapper(mapping: .undoToastHistoryFailure)
        )

        assertTestMirrorDescription(
            of: content.undoHistorySheet(request),
            contains: "UndoHistoryPanel",
            doesNotContain: "UndoToastHistoryRouteSheet"
        )
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "undo-history-undo-action-log-undo-history-panel")
        XCTAssertEqual(request.focusedActionID, action.actionID)
    }

    @MainActor
    func testUndoToastViewDetailsRequestCarriesFailedActionContext() {
        let action = UndoActionRecordSnapshot.undoToastHistoryFixture()
        let failure = CoreErrorMappingSnapshot.undoToastHistoryFailure
        let request = UndoToastHistoryRequest(
            source: .viewDetails,
            state: .failed(failure, previous: action),
            actionLogRefreshFailure: nil
        )

        XCTAssertEqual(request.focusedActionID, action.actionID)
        XCTAssertEqual(request.failureMapping, failure)
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreLoadsUndoHistorySnapshotAndSelectsFocusedAction() async {
        let latest = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let older = UndoActionRecordSnapshot.undoHistoryRenamedFiles()
        let undoStore = UndoHistoryRecordingUndoStore(results: [.list(.success([latest, older]))])
        let redoStore = RedoActionLogRecordingRedoStore(results: [.list(.success([]))])
        let state = await UndoHistoryActionLog.load(
            repoPath: "/tmp/repo",
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        XCTAssertEqual(state.actions, [latest, older])
        XCTAssertEqual(UndoHistoryActionLog.action(in: state.actions, focusedActionID: older.actionID), older)
        XCTAssertNil(state.failure)
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo"])
        let redoListRequests = await redoStore.listRequests()
        XCTAssertEqual(redoListRequests, ["/tmp/repo"])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreUndoLatestExecutesOnlyTopActionAndRefreshesSnapshot() async {
        let latest = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let older = UndoActionRecordSnapshot.undoHistoryRenamedFiles()
        let redo = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let undoStore = UndoHistoryRecordingUndoStore(results: [
            .undo(.success(.undoHistoryUndoneTrashMove())),
            .list(.success([.undoHistoryExecutedTrashMove(), older]))
        ])
        let redoStore = RedoActionLogRecordingRedoStore(results: [.list(.success([redo]))])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [latest, older], redoActions: []),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        XCTAssertEqual(state.actions, [.undoHistoryExecutedTrashMove(), older])
        XCTAssertEqual(state.snapshot.redoActions, [redo])
        let undoRequests = await undoStore.undoRequests()
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(undoRequests, ["/tmp/repo|\(latest.actionID)"])
        XCTAssertEqual(listRequests, ["/tmp/repo"])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreUndoLatestReportsRefreshFailureWithoutSwallowingIt() async {
        let latest = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let undoStore = UndoHistoryRecordingUndoStore(results: [
            .undo(.success(.undoHistoryUndoneTrashMove())),
            .list(.failure(CoreError.Db(message: "refresh failed")))
        ])
        let redoStore = RedoActionLogRecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [latest], redoActions: []),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        guard case let .refreshFailed(mapping, previous) = state else {
            return XCTFail("expected refreshFailed, got \(state)")
        }
        XCTAssertEqual(mapping.kind, .db)
        XCTAssertEqual(previous.undoActions, [latest])
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo"])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreBlockedLatestDoesNotCallUndoAction() async {
        let blocked = UndoActionRecordSnapshot.undoHistoryBlockedRename()
        let undoStore = UndoHistoryRecordingUndoStore(results: [])
        let redoStore = RedoActionLogRecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [blocked], redoActions: []),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: RecordingCoreErrorMapper.undoHistory()
        )

        XCTAssertEqual(state.actions, [blocked])
        XCTAssertEqual(state.failure?.userMessage, "External change prevents undo.")
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(undoRequests, [])
    }

    @MainActor
    func testUndoHistoryUndoActionLogCorePanelShowsActionStatesAndDisabledRedoWithoutRedoActionLogCoreCall() {
        let ready = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let blocked = UndoActionRecordSnapshot.undoHistoryBlockedRename()
        let panel = UndoHistoryPanel(
            repoPath: "/tmp/repo",
            focusedActionID: ready.actionID,
            initialFailure: nil,
            undoStore: UndoHistoryRecordingUndoStore(results: [.list(.success([ready, blocked]))]),
            redoStore: RedoActionLogRecordingRedoStore(results: [.list(.success([.redoActionLogAvailableMoveRedo()]))]),
            errorMapper: RecordingCoreErrorMapper.undoHistory(),
            onClose: {},
            onUndoCompleted: { _ in },
            onRedoCompleted: { _ in }
        )
        assertTestMirrorDescription(of: panel.body, contains: [
            "Undo History",
            "Undo latest",
            "Redo latest"
        ])
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "undo-history-undo-action-log-undo-history-panel")
    }

    @MainActor
    func testUndoHistoryUndoActionLogCoreMenuAndShortcutRequestsShareUndoHistoryPanelRoute() {
        let action = UndoActionRecordSnapshot.undoHistoryMovedFilesToTrash()
        let failure = CoreErrorMappingSnapshot.undoToastHistoryFailure
        let menuRequest = UndoHistoryActionLog.menuRequest(state: .ready(action), failure: nil)
        let shortcutRequest = UndoHistoryActionLog.shortcutRequest(state: .ready(action), failure: nil)
        let redoShortcutRequest = UndoHistoryActionLog.redoShortcutRequest(state: .ready(action), failure: failure)

        XCTAssertEqual(menuRequest.source, .viewHistory)
        XCTAssertEqual(shortcutRequest.source, .viewHistory)
        XCTAssertEqual(redoShortcutRequest.source, .viewHistory)
        XCTAssertEqual(menuRequest.focusedActionID, action.actionID)
        XCTAssertEqual(shortcutRequest.focusedActionID, action.actionID)
        XCTAssertEqual(redoShortcutRequest.failureMapping, failure)
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "undo-history-undo-action-log-undo-history-panel")
    }

    func testRedoActionLogUndoActionLogCoreRedoSourceUsesLoadedUndoActionLogSummary() {
        let undo = UndoActionRecordSnapshot.undoHistoryExecutedTrashMove()
        let redo = RedoActionRecordSnapshot.redoActionLogAvailableMoveRedo()
        let presentation = RedoUndoSourcePresentation(redoAction: redo, undoActions: [undo])

        XCTAssertEqual(presentation.sourceText, "Source undo: Moved 3 files to Trash.")
        XCTAssertEqual(presentation.statusText, "Available until the next file operation")
        XCTAssertEqual(UndoHistorySnapshot(undoActions: [undo], redoActions: [redo]).sourceUndoAction(for: redo), undo)
    }
}

private extension ImportProgressPageIntegrationVerifyTests {
    static let runningProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 3,
        remaining: 2,
        currentPath: "docs/contract.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/contract.pdf",
                targetPath: "docs/contract.pdf",
                phase: .copying,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/later.pdf",
                targetPath: "docs/later.pdf",
                phase: .pending,
                errorMessage: nil
            )
        ]
    )

    static let fatalProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 5,
        remaining: 1,
        currentPath: "docs/contracts/合同.pdf",
        skipped: 2,
        pending: 0,
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/合同.pdf",
                targetPath: "docs/contracts/合同.pdf",
                phase: .failed,
                errorMessage: "Storage write failed"
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/skipped-a.pdf",
                targetPath: "docs/skipped-a.pdf",
                phase: .pending,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/skipped-b.pdf",
                targetPath: "docs/skipped-b.pdf",
                phase: .pending,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/pending.pdf",
                targetPath: "docs/pending.pdf",
                phase: .writingIndex,
                errorMessage: nil
            )
        ]
    )
}

private extension CoreErrorMappingSnapshot {
    static var importProgressFatalProgressError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "import-progress fatal import progress"
        )
    }

    static var undoToastHistoryFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Undo history could not be loaded",
            severity: .medium,
            suggestedAction: "Retry from Undo history.",
            recoverability: .refreshRequired,
            rawContext: "undo-toast undo-action-log undo-action-log"
        )
    }
}

private extension UndoActionRecordSnapshot {
    static func undoToastHistoryFixture() -> UndoActionRecordSnapshot {
        UndoActionRecordSnapshot(
            actionID: "undo-history-1",
            kind: "batch_add_tags",
            summary: #"Added tag "finance" to 3 files."#,
            affectedCount: 3,
            affectedFileNames: ["invoice.pdf", "receipt.pdf"],
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_010
        )
    }
}

private extension UndoActionRecordSnapshot {
    static func undoHistoryMovedFilesToTrash() -> UndoActionRecordSnapshot {
        testMovedFilesToTrashUndoAction()
    }

    static func undoHistoryBlockedRename() -> UndoActionRecordSnapshot {
        testBlockedRenameUndoAction()
    }

    static func undoHistoryRenamedFiles() -> UndoActionRecordSnapshot {
        testRenamedFilesUndoAction()
    }

    static func undoHistoryExecutedTrashMove() -> UndoActionRecordSnapshot {
        testExecutedTrashMoveUndoAction()
    }
}

private extension UndoActionResultSnapshot {
    static func undoHistoryUndoneTrashMove() -> UndoActionResultSnapshot {
        testUndoneTrashMoveUndoResult()
    }
}

private typealias UndoHistoryRecordingUndoStore = LenientUndoActionRecordingTestStore
