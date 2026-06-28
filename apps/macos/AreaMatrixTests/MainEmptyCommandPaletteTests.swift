@testable import AreaMatrix
import SwiftUI
import XCTest

final class MainEmptyCommandPaletteTests: XCTestCase {
    func testCommandPaletteCommandPaletteRendersSmartListSmartListsCoreTargets() {
        let saved = SavedSearchSnapshot.commandPaletteCommandPaletteFixture()
        let targets = CommandPaletteSmartListTarget.matching([saved], query: "fin")

        XCTAssertEqual(targets.map(\.savedSearch.id), [77])
        XCTAssertEqual(targets.map(\.title), ["Finance"])
        XCTAssertEqual(targets.map(\.accessibilityIdentifier), ["command-palette-smart-list-smart-list-77"])
    }

    @MainActor
    func testCommandPaletteCommandIndexCoreLoadsCommandIndexAndKeepsQuerySeparateFromFileSearch() async {
        let searcher = MainListRecordingSearchQuerying(results: [])
        let target = CommandTarget.commandPaletteFixture(
            id: "selection.delete",
            title: "Delete selected files...",
            action: .openConfirmation,
            route: "batch-delete"
        )
        let indexer = CommandPaletteCommandIndexStore(results: [.success(.commandPaletteFixture(commands: [target]))])
        let model = MainFileListModel(
            opening: .mainEmptyImportFixture(repoPath: "/tmp/repo"),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            commandIndexer: indexer,
            errorMapper: CommandPaletteCommandErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))
        )

        await model.loadCommandIndex(query: " delete ", selectedFileIDs: [20, 10], currentPath: "docs")
        let requests = await indexer.recordedRequests()
        let searchRequests = await searcher.recordedRequests()

        XCTAssertEqual(searchRequests, [])
        XCTAssertEqual(requests.map(\.context.query), ["delete"])
        XCTAssertEqual(requests.map(\.context.selectedFileIds), [[10, 20]])
        XCTAssertEqual(model.commandPaletteState.snapshot?.sections[0].targets.first?.title, "Delete selected files...")
    }

    @MainActor
    func testCommandPaletteCommandIndexCoreMapsCommandIndexFailureForInlineError() async {
        let mapping = CoreErrorMappingSnapshot.commandPaletteCommandDb(rawContext: "command db locked")
        let mapper = CommandPaletteCommandErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .mainEmptyImportFixture(repoPath: "/tmp/repo"),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            commandIndexer: CommandPaletteCommandIndexStore(results: [.failure(CoreError
                    .Db(message: "command db locked"))]),
            errorMapper: mapper
        )

        await model.loadCommandIndex(query: "", selectedFileIDs: Set<Int64>(), currentPath: String?.none)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.commandPaletteState.errorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "command db locked")])
    }

    func testCommandPaletteCommandIndexCoreCommandPaletteRowsAreExecutableAndShowDangerBoundary() {
        var query = "delete"
        let target = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "batch-delete",
            requiresConfirmation: true
        )
        let snapshot = CommandPaletteSnapshot(
            sections: [.init(title: "Current Selection", targets: [target])],
            generatedAt: 1
        )
        let body = CommandPaletteView(
            query: Binding(get: { query }, set: { query = $0 }),
            state: .loaded(snapshot),
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        ).body

        assertTestMirrorDescription(of: body, contains: [
            "Button",
            "Delete selected files..."
        ], includeLabels: false)
        XCTAssertEqual(target.confirmationLabel, "Requires confirmation")
        XCTAssertEqual(target.executionRoute, .batchDelete)
    }

    func testCommandPaletteCommandIndexCoreDisabledCommandTargetsCannotExecute() {
        let target = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "batch-delete",
            disabled: true,
            disabledReason: "Select files first.",
            requiresConfirmation: true
        )

        XCTAssertFalse(target.isExecutable)
        XCTAssertEqual(target.executionRoute, .batchDelete)
    }

    func testCommandPaletteCommandIndexCoreBuildsCoreDeleteTargetAsBatchDeleteConfirmationRoute() {
        let file = FileEntrySnapshot.commandPaletteCommandFileFixture(id: 515, currentName: "delete.pdf")
        let target = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "batch-delete",
            requiresConfirmation: true
        )
        let route = CommandPaletteBatchRouteBuilder.batchDeleteRoute(
            selectedFileIDs: [file.id],
            visibleFiles: [file],
            isReadOnly: false,
            isLoading: false,
            writeLockedFileIDs: []
        )

        XCTAssertEqual(target.executionRoute, .batchDelete)
        XCTAssertTrue(target.requiresConfirmation)
        XCTAssertEqual(route.source, .commandPalette)
        XCTAssertEqual(route.fileIDs, [file.id])
        XCTAssertNil(route.disabledReason)
    }

    func testCommandPaletteCommandIndexCoreResolvesCoreSmartListTargetThroughSavedSearchRoute() {
        let saved = SavedSearchSnapshot.commandPaletteCommandPaletteFixture()
        let target = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "smart-list:77",
            action: .runSmartList,
            route: nil,
            savedSearchID: saved.id
        )
        let resolved = CommandPaletteSmartListRouting.savedSearch(savedSearchID: saved.id, in: [saved])

        XCTAssertEqual(target.executionRoute, .runSmartList(saved.id))
        XCTAssertEqual(resolved, saved)
        XCTAssertNil(CommandPaletteSmartListRouting.savedSearch(savedSearchID: 404, in: [saved]))
    }

    func testCommandPalettePageIntegrationRoutesAllPageSpecCommandTargets() {
        for routeCase in MainEmptyCommandPaletteRouteCase.pageSpecRoutes {
            let target = CommandTargetSnapshot.commandPaletteRouteFixture(
                id: routeCase.targetID,
                action: routeCase.action,
                route: routeCase.route,
                requiresConfirmation: routeCase.requiresConfirmation
            )

            XCTAssertEqual(target.executionRoute, routeCase.expectedRoute)
            XCTAssertTrue(target.isExecutable)
        }
    }

    func testCommandPaletteKeyboardSelectionSkipsDisabledTargetsAndWraps() {
        let targets = MainEmptyCommandPaletteKeyboardTargets.fixture

        XCTAssertEqual(CommandPaletteSelectionRouting.nextSelectedID(
            currentID: nil,
            targets: targets.allTargets,
            offset: 1
        ), targets.first.id)
        XCTAssertEqual(CommandPaletteSelectionRouting.nextSelectedID(
            currentID: targets.first.id,
            targets: targets.allTargets,
            offset: 1
        ), targets.last.id)
        XCTAssertEqual(CommandPaletteSelectionRouting.nextSelectedID(
            currentID: targets.first.id,
            targets: targets.allTargets,
            offset: -1
        ), targets.last.id)
    }

    @MainActor
    func testCommandPalettePageIntegrationWiresEntryCloseCommandIndexAndSmartListRun() async {
        let saved = SavedSearchSnapshot.commandPaletteCommandPaletteFixture()
        let resultFile = FileEntrySnapshot.commandPaletteCommandFileFixture(id: 88, currentName: "finance.pdf")
        let indexTarget = CommandTarget.commandPaletteFixture(
            id: "smart-list:77",
            title: "Finance",
            action: .runSmartList,
            route: nil,
            savedSearchID: saved.id
        )
        let indexer =
            CommandPaletteCommandIndexStore(results: [.success(.commandPaletteFixture(smartLists: [indexTarget]))])
        let smartListRunner = CommandPaletteSmartListRunner(results: [
            .success(.commandPaletteCommandSmartListPage(saved: saved, files: [resultFile]))
        ])
        let model = MainFileListModel(
            opening: .commandPaletteCommandFixture(repoPath: "/tmp/repo", files: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: smartListRunner,
            commandIndexer: indexer,
            errorMapper: CommandPaletteCommandErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))
        )

        model.openCommandPaletteForSearch()
        model.commandPaletteQuery = " finance "
        await model.loadCommandIndex(query: model.commandPaletteQuery, selectedFileIDs: [20, 10], currentPath: "docs")
        model.clearCommandPaletteState()
        model.commandPaletteQuery = ""
        model.clearPendingSearchDestination()
        await model.restoreSavedSearch(saved)
        let indexRequests = await indexer.recordedRequests()
        let runRequests = await smartListRunner.recordedRunRequests()
        let searchRequests = await smartListRunner.recordedSearchRequests()

        XCTAssertEqual(CommandTargetSnapshot(coreTarget: indexTarget).executionRoute, .runSmartList(saved.id))
        XCTAssertNil(model.pendingSearchDestination)
        XCTAssertEqual(indexRequests.map(\.context.selectedFileIds), [[10, 20]])
        XCTAssertEqual(indexRequests.map(\.context.currentPath), ["docs"])
        XCTAssertEqual(indexRequests.map(\.context.query), ["finance"])
        XCTAssertEqual(runRequests, [
            CommandPaletteSmartListRunRequest(repoPath: "/tmp/repo", savedSearchID: saved.id, limit: 50, offset: 0)
        ])
        XCTAssertEqual(searchRequests, [])
        XCTAssertEqual(model.files, [resultFile])
        XCTAssertEqual(model.commandPaletteState, .idle)
        XCTAssertEqual(model.commandPaletteQuery, "")
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: saved.id, name: saved.name))
    }

    @MainActor
    func testCommandPalettePageIntegrationRoutesDangerCommandsToConfirmationWithoutDirectMutation() {
        let file = FileEntrySnapshot.commandPaletteCommandFileFixture(id: 515, currentName: "delete.pdf")
        let model = MainFileListModel(
            opening: .commandPaletteCommandFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            errorMapper: CommandPaletteCommandErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))
        )
        let target = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "batch-delete",
            requiresConfirmation: true
        )
        let route = CommandPaletteBatchRouteBuilder.batchDeleteRoute(
            selectedFileIDs: [file.id],
            visibleFiles: [file],
            isReadOnly: model.isReadOnly,
            isLoading: model.isLoading,
            writeLockedFileIDs: model.writeLockedFileIDs
        )

        model.commandPaletteState = .loaded(CommandPaletteSnapshot(coreIndex: .commandPaletteFixture()))
        model.commandPaletteQuery = "delete"
        model.pendingSearchDestination = .commandPalette
        model.clearCommandPaletteState()
        model.commandPaletteQuery = ""
        model.clearPendingSearchDestination()

        XCTAssertEqual(target.executionRoute, .batchDelete)
        XCTAssertTrue(target.requiresConfirmation)
        XCTAssertEqual(route.source, .commandPalette)
        XCTAssertEqual(route.fileIDs, [file.id])
        XCTAssertNil(route.disabledReason)
        XCTAssertEqual(model.commandPaletteState, .idle)
        XCTAssertEqual(model.commandPaletteQuery, "")
        XCTAssertNil(model.pendingSearchDestination)
        XCTAssertEqual(model.files, [file])
    }

    @MainActor
    func testCommandPaletteCommandPaletteToggleRestoresPreviousSearchFocus() {
        let model = MainFileListModel(
            opening: .commandPaletteCommandFixture(repoPath: "/tmp/repo", files: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            errorMapper: CommandPaletteCommandErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))
        )

        model.openCommandPaletteForSearch()
        XCTAssertEqual(model.pendingSearchDestination, .commandPalette)
        XCTAssertEqual(model.lastSearchExitContext, .toolbar)

        model.clearCommandPaletteState()
        model.clearPendingSearchDestination()
        XCTAssertNil(model.pendingSearchDestination)
        XCTAssertEqual(model.commandPaletteState, .idle)
    }
}

final class MainEmptyCommandPaletteRedoTests: XCTestCase {
    func testRedoActionLogRedoActionLogCoreRedoCommandTargetBypassesStaticCoreDisabledAndUsesDynamicRedoStack() {
        let target = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "redo.latest",
            title: "Redo latest action",
            action: .navigate,
            route: "redo-action-log",
            disabled: true,
            disabledReason: "Redo stack is unavailable."
        )

        XCTAssertEqual(target.executionRoute, .linkedPage(.redo))
        XCTAssertTrue(target.isExecutable)
        XCTAssertNil(target.effectiveDisabledReason)
    }

    @MainActor
    func testRedoActionLogCommandPaletteRedoExecutesLatestRedoActionDirectly() async {
        let redoStore = RedoActionLogRecordingRedoStore(results: [
            .list(.success([.redoActionLogAvailableMoveRedo()])),
            .redo(.success(.redoActionLogRedoneMove())),
            .list(.success([.redoActionLogExecutedMoveRedo()]))
        ])
        let undoStore = CommandPaletteNoopUndoStore()
        let errorMapper = CommandPaletteCommandErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))

        let loaded = await UndoHistoryActionLog.load(
            repoPath: "/tmp/repo",
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        let state = await UndoHistoryActionLog.redoLatest(
            repoPath: "/tmp/repo",
            snapshot: loaded.snapshot,
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )

        guard case let .redone(result, refreshed) = state else {
            return XCTFail("expected redone state, got \(state)")
        }
        XCTAssertEqual(result, .redoActionLogRedoneMove())
        XCTAssertEqual(refreshed.redoActions, [.redoActionLogExecutedMoveRedo()])
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, ["/tmp/repo|redo-move-3"])
        let listRequests = await redoStore.listRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo", "/tmp/repo"])
    }

    @MainActor
    func testRedoActionLogShiftCommandZExecutesSameLatestRedoAction() async {
        let redoStore = RedoActionLogRecordingRedoStore(results: [
            .list(.success([.redoActionLogAvailableMoveRedo()])),
            .redo(.success(.redoActionLogRedoneMove())),
            .list(.success([.redoActionLogExecutedMoveRedo()]))
        ])
        let undoStore = CommandPaletteNoopUndoStore()
        let errorMapper = CommandPaletteCommandErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))

        let loaded = await UndoHistoryActionLog.load(
            repoPath: "/tmp/repo",
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        let state = await UndoHistoryActionLog.redoLatest(
            repoPath: "/tmp/repo",
            snapshot: loaded.snapshot,
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )

        guard case .redone = state else {
            return XCTFail("expected redone state, got \(state)")
        }
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, ["/tmp/repo|redo-move-3"])
    }

    @MainActor
    func testRedoActionLogShortcutKeepsUndoHistoryFailureEvidenceWhenRedoIsUnavailable() async {
        let redoStore = RedoActionLogRecordingRedoStore(results: [.list(.success([]))])
        let undoStore = CommandPaletteNoopUndoStore()
        let errorMapper = CommandPaletteCommandErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))

        let loaded = await UndoHistoryActionLog.load(
            repoPath: "/tmp/repo",
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        let state = await UndoHistoryActionLog.redoLatest(
            repoPath: "/tmp/repo",
            snapshot: loaded.snapshot,
            undoStore: undoStore,
            redoStore: redoStore,
            errorMapper: errorMapper
        )
        let request = UndoHistoryActionLog.redoShortcutRequest(
            state: .idle,
            failure: RedoLatestEntryPoint.noRedoMapping
        )

        XCTAssertEqual(state, .loaded(UndoHistorySnapshot(undoActions: [], redoActions: [])))
        XCTAssertEqual(request.source, .viewHistory)
        XCTAssertEqual(request.failureMapping?.rawContext, "redo-action-log redo-action-log-core redo-action-log")
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, [])
    }
}
