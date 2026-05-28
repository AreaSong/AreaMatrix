@testable import AreaMatrix
import XCTest

final class ImportProgressPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS120MainListTemporaryImportRowsCanDriveDetailPane() {
        let rows = Self.runningProgress.items.map(ImportProgressListRow.init)

        XCTAssertEqual(rows.map(\.displayName), ["invoice.pdf", "contract.pdf", "later.pdf"])
        XCTAssertEqual(rows.map(\.phaseText), ["Done", "Copying", "Pending"])
        XCTAssertEqual(rows[1].sourcePath, "/tmp/contract.pdf")
        XCTAssertEqual(rows[1].targetPath, "docs/contract.pdf")
    }

    @MainActor
    func testS120FatalImportExitMustRouteThroughS121ResultSummary() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.fatalProgress)
        model.failImportEntry(
            progress: Self.fatalProgress,
            mapping: CoreErrorMappingSnapshot.s120FatalProgressError,
            retryContext: nil,
            recoveryCheck: .retryBlocked("Recovery state could not be confirmed.", nil)
        )
        model.stopImportProgressAndViewResults()

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 2, pending 1.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed, .skipped, .skipped, .pending])
        XCTAssertEqual(result.items[1].reason, "Storage write failed")
    }

    @MainActor
    func testS210ViewHistoryRequestBuildsSharedUndoHistoryPanelRoute() {
        let action = UndoActionRecordSnapshot.s210HistoryFixture()
        let request = UndoToastHistoryRequest(source: .viewHistory, state: .ready(action), actionLogRefreshFailure: nil)
        let content = MainRepositoryContentView(
            opening: .s117Fixture(repoPath: "/tmp/repo"),
            state: .list,
            onImport: {},
            onDropImport: { _, _ in },
            errorMapper: S210HistoryErrorMapper()
        )

        let sheetDescription = importProgressMirrorDescription(of: content.undoHistorySheet(request))

        XCTAssertTrue(sheetDescription.contains("UndoHistoryPanel"))
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "S2-11-C2-07-undo-history-panel")
        XCTAssertFalse(sheetDescription.contains("UndoToastHistoryRouteSheet"))
        XCTAssertEqual(request.focusedActionID, action.actionID)
    }

    @MainActor
    func testS210ViewDetailsRequestCarriesFailedActionContext() {
        let action = UndoActionRecordSnapshot.s210HistoryFixture()
        let failure = CoreErrorMappingSnapshot.s210HistoryFailure
        let request = UndoToastHistoryRequest(
            source: .viewDetails,
            state: .failed(failure, previous: action),
            actionLogRefreshFailure: nil
        )

        XCTAssertEqual(request.focusedActionID, action.actionID)
        XCTAssertEqual(request.failureMapping, failure)
    }

    @MainActor
    func testS211C207LoadsUndoHistorySnapshotAndSelectsFocusedAction() async {
        let latest = UndoActionRecordSnapshot.s211MovedFilesToTrash()
        let older = UndoActionRecordSnapshot.s211RenamedFiles()
        let undoStore = S211RecordingUndoStore(results: [.list(.success([latest, older]))])
        let redoStore = S222RecordingRedoStore(results: [.list(.success([]))])
        let state = await UndoHistoryActionLog.load(
            repoPath: "/tmp/repo",
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: S211HistoryErrorMapper()
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
    func testS211C207UndoLatestExecutesOnlyTopActionAndRefreshesSnapshot() async {
        let latest = UndoActionRecordSnapshot.s211MovedFilesToTrash()
        let older = UndoActionRecordSnapshot.s211RenamedFiles()
        let redo = RedoActionRecordSnapshot.s222AvailableMoveRedo()
        let undoStore = S211RecordingUndoStore(results: [
            .undo(.success(.s211UndoneTrashMove())),
            .list(.success([.s211ExecutedTrashMove(), older]))
        ])
        let redoStore = S222RecordingRedoStore(results: [.list(.success([redo]))])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [latest, older], redoActions: []),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: S211HistoryErrorMapper()
        )

        XCTAssertEqual(state.actions, [.s211ExecutedTrashMove(), older])
        XCTAssertEqual(state.snapshot.redoActions, [redo])
        let undoRequests = await undoStore.undoRequests()
        let listRequests = await undoStore.listRequests()
        XCTAssertEqual(undoRequests, ["/tmp/repo|\(latest.actionID)"])
        XCTAssertEqual(listRequests, ["/tmp/repo"])
    }

    @MainActor
    func testS211C207UndoLatestReportsRefreshFailureWithoutSwallowingIt() async {
        let latest = UndoActionRecordSnapshot.s211MovedFilesToTrash()
        let undoStore = S211RecordingUndoStore(results: [
            .undo(.success(.s211UndoneTrashMove())),
            .list(.failure(CoreError.Db(message: "refresh failed")))
        ])
        let redoStore = S222RecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [latest], redoActions: []),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: S211HistoryErrorMapper()
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
    func testS211C207BlockedLatestDoesNotCallUndoAction() async {
        let blocked = UndoActionRecordSnapshot.s211BlockedRename()
        let undoStore = S211RecordingUndoStore(results: [])
        let redoStore = S222RecordingRedoStore(results: [])
        let state = await UndoHistoryActionLog.undoLatest(
            repoPath: "/tmp/repo",
            snapshot: UndoHistorySnapshot(undoActions: [blocked], redoActions: []),
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: S211HistoryErrorMapper()
        )

        XCTAssertEqual(state.actions, [blocked])
        XCTAssertEqual(state.failure?.userMessage, "External change prevents undo.")
        let undoRequests = await undoStore.undoRequests()
        XCTAssertEqual(undoRequests, [])
    }

    @MainActor
    func testS211C207PanelShowsActionStatesAndDisabledRedoWithoutC218Call() {
        let ready = UndoActionRecordSnapshot.s211MovedFilesToTrash()
        let blocked = UndoActionRecordSnapshot.s211BlockedRename()
        let panel = UndoHistoryPanel(
            repoPath: "/tmp/repo",
            focusedActionID: ready.actionID,
            initialFailure: nil,
            undoStore: S211RecordingUndoStore(results: [.list(.success([ready, blocked]))]),
            redoStore: S222RecordingRedoStore(results: [.list(.success([.s222AvailableMoveRedo()]))]),
            errorMapper: S211HistoryErrorMapper(),
            onClose: {},
            onUndoCompleted: { _ in },
            onRedoCompleted: { _ in }
        )
        let description = importProgressMirrorDescription(of: panel.body)

        XCTAssertTrue(description.contains("Undo History"))
        XCTAssertTrue(description.contains("Undo latest"))
        XCTAssertTrue(description.contains("Redo latest"))
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "S2-11-C2-07-undo-history-panel")
    }

    @MainActor
    func testS211C207MenuAndShortcutRequestsShareUndoHistoryPanelRoute() {
        let action = UndoActionRecordSnapshot.s211MovedFilesToTrash()
        let failure = CoreErrorMappingSnapshot.s210HistoryFailure
        let menuRequest = UndoHistoryActionLog.menuRequest(state: .ready(action), failure: nil)
        let shortcutRequest = UndoHistoryActionLog.shortcutRequest(state: .ready(action), failure: nil)
        let redoShortcutRequest = UndoHistoryActionLog.redoShortcutRequest(state: .ready(action), failure: failure)

        XCTAssertEqual(menuRequest.source, .viewHistory)
        XCTAssertEqual(shortcutRequest.source, .viewHistory)
        XCTAssertEqual(redoShortcutRequest.source, .viewHistory)
        XCTAssertEqual(menuRequest.focusedActionID, action.actionID)
        XCTAssertEqual(shortcutRequest.focusedActionID, action.actionID)
        XCTAssertEqual(redoShortcutRequest.failureMapping, failure)
        XCTAssertEqual(UndoHistoryPanel.accessibilityID, "S2-11-C2-07-undo-history-panel")
    }

    func testS222C207RedoSourceUsesLoadedUndoActionLogSummary() {
        let undo = UndoActionRecordSnapshot.s211ExecutedTrashMove()
        let redo = RedoActionRecordSnapshot.s222AvailableMoveRedo()
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
    static var s120FatalProgressError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "S1-20 fatal import progress"
        )
    }

    static var s210HistoryFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Undo history could not be loaded",
            severity: .medium,
            suggestedAction: "Retry from Undo history.",
            recoverability: .refreshRequired,
            rawContext: "S2-10 C2-07 undo-action-log"
        )
    }
}

private extension UndoActionRecordSnapshot {
    static func s210HistoryFixture() -> UndoActionRecordSnapshot {
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

private func importProgressMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendImportProgressMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendImportProgressMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendImportProgressMirrorDescription(of: child.value, to: &lines)
    }
}

private actor S210HistoryErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        .s210HistoryFailure
    }
}

private extension UndoActionRecordSnapshot {
    static func s211MovedFilesToTrash() -> UndoActionRecordSnapshot {
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

    static func s211BlockedRename() -> UndoActionRecordSnapshot {
        var action = s211RenamedFiles()
        action.actionID = "undo-rename-blocked"
        action.status = .blocked
        action.canUndo = false
        action.disabledReason = "External change prevents undo."
        return action
    }

    static func s211RenamedFiles() -> UndoActionRecordSnapshot {
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

    static func s211ExecutedTrashMove() -> UndoActionRecordSnapshot {
        var action = s211MovedFilesToTrash()
        action.status = .executed
        action.canUndo = false
        action.updatedAt = 1_700_000_030
        return action
    }
}

private extension UndoActionResultSnapshot {
    static func s211UndoneTrashMove() -> UndoActionResultSnapshot {
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

private actor S211RecordingUndoStore: CoreUndoActionLogging {
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

private actor S211HistoryErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind(for: error),
            userMessage: "Undo failed",
            severity: .medium,
            suggestedAction: "View details in Undo history.",
            recoverability: .refreshRequired,
            rawContext: "S2-11 C2-07 undo-action-log"
        )
    }

    private func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        switch error {
        case .Conflict:
            .conflict
        case .FileNotFound:
            .fileNotFound
        case .PermissionDenied:
            .permissionDenied
        case .Db:
            .db
        case .Io:
            .io
        default:
            .internal
        }
    }
}
