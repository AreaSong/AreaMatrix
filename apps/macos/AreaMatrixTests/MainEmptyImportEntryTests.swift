@testable import AreaMatrix
import Foundation
import SwiftUI
import XCTest

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
final class MainEmptyImportEntryTests: XCTestCase {
    @MainActor
    func testMainEmptyImportButtonCreatesImportEntryFromPicker() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: MainEmptyImportStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportAnnouncer(),
            helpOpener: MainEmptyImportNoopWelcomeHelpOpener(),
            importPicker: MainEmptyImportStaticImportPicker(urls: [importURL])
        )

        model.chooseImportSources(opening: opening)

        XCTAssertEqual(model.pendingImportEntry?.repoPath, "/tmp/empty-repo")
        XCTAssertEqual(model.pendingImportEntry?.source, .filePicker)
        XCTAssertEqual(model.pendingImportEntry?.destination, .autoClassify)
        XCTAssertEqual(model.pendingImportEntry?.urls, [importURL])
        XCTAssertEqual(model.pendingImportEntry?.kind, .singleFile)
    }

    @MainActor
    func testMainEmptyDropEntryKeepsSidebarDestination() {
        let importURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: MainEmptyImportStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportAnnouncer(),
            helpOpener: MainEmptyImportNoopWelcomeHelpOpener()
        )

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [importURL],
            destination: .category("finance")
        )

        XCTAssertEqual(model.pendingImportEntry?.destination, .category("finance"))
        XCTAssertEqual(model.pendingImportEntry?.destinationLabel, "finance")
    }

    @MainActor
    func testMainEmptyMultipleDropEntryCreatesBatchRequestForS118() {
        let firstURL = URL(fileURLWithPath: "/tmp/a.pdf")
        let secondURL = URL(fileURLWithPath: "/tmp/b.pdf")
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let model = OnboardingModel(
            settingsReader: MainEmptyImportStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: MainEmptyImportAnnouncer(),
            helpOpener: MainEmptyImportNoopWelcomeHelpOpener()
        )

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [firstURL, secondURL]
        )

        XCTAssertEqual(model.pendingImportEntry?.kind, .multipleItems(2))
        XCTAssertEqual(model.pendingImportEntry?.sheetTitle, "导入 2 个文件")
        XCTAssertEqual(model.pendingImportEntry?.source, .dropZone)
        XCTAssertEqual(model.pendingImportEntry?.urls, [firstURL, secondURL])
    }

    @MainActor
    func testMainEmptyDropEntryRejectsInvalidItemsWithAccessibleToast() throws {
        let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: "/tmp/empty-repo")
        let accessibilityAnnouncer = MainEmptyImportAnnouncer()
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/a"))
        let model = OnboardingModel(
            settingsReader: MainEmptyImportStaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: accessibilityAnnouncer,
            helpOpener: MainEmptyImportNoopWelcomeHelpOpener()
        )

        model.startImportEntry(opening: opening, source: .dropZone, urls: [remoteURL])

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.toastMessage, "Cannot import these items")
        XCTAssertEqual(accessibilityAnnouncer.announcements, ["Cannot import these items"])
    }

    func testDropFileURLItemDecoderAcceptsFileURLDataAndRejectsRemoteURL() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/source.pdf")
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/source.pdf"))

        let decodedFileURL = FileDropAdapter.fileURL(from: fileURL.dataRepresentation as NSData)
        let decodedRemoteURL = FileDropAdapter.fileURL(from: remoteURL.dataRepresentation as NSData)

        XCTAssertEqual(decodedFileURL, fileURL)
        XCTAssertNil(decodedRemoteURL)
    }

    func testS215CommandPaletteRendersSmartListC204Targets() {
        let saved = SavedSearchSnapshot.s215CommandPaletteFixture()
        let targets = CommandPaletteSmartListTarget.matching([saved], query: "fin")

        XCTAssertEqual(targets.map(\.savedSearch.id), [77])
        XCTAssertEqual(targets.map(\.title), ["Finance"])
        XCTAssertEqual(targets.map(\.accessibilityIdentifier), ["S2-15-C2-04-smart-list-77"])
    }

    @MainActor
    func testS215C211LoadsCommandIndexAndKeepsQuerySeparateFromFileSearch() async {
        let searcher = MainListRecordingSearchQuerying(results: [])
        let target = CommandTarget.s215Fixture(
            id: "selection.delete",
            title: "Delete selected files...",
            action: .openConfirmation,
            route: "S2-13"
        )
        let indexer = S215CommandIndexStore(results: [.success(.s215Fixture(commands: [target]))])
        let model = MainFileListModel(
            opening: .mainEmptyImportFixture(repoPath: "/tmp/repo"),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: searcher,
            commandIndexer: indexer,
            errorMapper: S215CommandErrorMapper(mapping: .s215CommandDb(rawContext: "unused"))
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
    func testS215C211MapsCommandIndexFailureForInlineError() async {
        let mapping = CoreErrorMappingSnapshot.s215CommandDb(rawContext: "command db locked")
        let mapper = S215CommandErrorMapper(mapping: mapping)
        let model = MainFileListModel(
            opening: .mainEmptyImportFixture(repoPath: "/tmp/repo"),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            commandIndexer: S215CommandIndexStore(results: [.failure(CoreError.Db(message: "command db locked"))]),
            errorMapper: mapper
        )

        await model.loadCommandIndex(query: "", selectedFileIDs: Set<Int64>(), currentPath: String?.none)
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.commandPaletteState.errorMapping, mapping)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "command db locked")])
    }

    func testS215C211CommandPaletteRowsAreExecutableAndShowDangerBoundary() {
        var query = "delete"
        let target = CommandTargetSnapshot.s215RouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "S2-13",
            requiresConfirmation: true
        )
        let snapshot = CommandPaletteSnapshot(
            sections: [.init(title: "Current Selection", targets: [target])],
            generatedAt: 1
        )
        let body = s215CommandMirrorDescription(of: CommandPaletteView(
            query: Binding(get: { query }, set: { query = $0 }),
            state: .loaded(snapshot),
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        ).body)

        XCTAssertTrue(body.contains("Button"))
        XCTAssertTrue(body.contains("Delete selected files..."))
        XCTAssertEqual(target.confirmationLabel, "Requires confirmation")
        XCTAssertEqual(target.executionRoute, .batchDelete)
    }

    func testS215C211DisabledCommandTargetsCannotExecute() {
        let target = CommandTargetSnapshot.s215RouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "S2-13",
            disabled: true,
            disabledReason: "Select files first.",
            requiresConfirmation: true
        )

        XCTAssertFalse(target.isExecutable)
        XCTAssertEqual(target.executionRoute, .batchDelete)
    }

    func testS222C218RedoCommandTargetBypassesStaticCoreDisabledAndUsesDynamicRedoStack() {
        let target = CommandTargetSnapshot.s215RouteFixture(
            id: "redo.latest",
            title: "Redo latest action",
            action: .navigate,
            route: "S2-22",
            disabled: true,
            disabledReason: "Redo stack is unavailable."
        )

        XCTAssertEqual(target.executionRoute, .linkedPage(.redo))
        XCTAssertTrue(target.isExecutable)
        XCTAssertNil(target.effectiveDisabledReason)
    }

    func testS215C211BuildsCoreDeleteTargetAsBatchDeleteConfirmationRoute() {
        let file = FileEntrySnapshot.s215CommandFileFixture(id: 515, currentName: "delete.pdf")
        let target = CommandTargetSnapshot.s215RouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "S2-13",
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

    func testS215C211ResolvesCoreSmartListTargetThroughSavedSearchRoute() {
        let saved = SavedSearchSnapshot.s215CommandPaletteFixture()
        let target = CommandTargetSnapshot.s215RouteFixture(
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

    func testS215PageIntegrationRoutesAllPageSpecCommandTargets() {
        // swiftlint:disable:next large_tuple
        let routes: [(String, CommandTargetActionSnapshot, CommandPaletteTargetRoute)] = [
            ("S2-18", .navigate, .linkedPage(.classifierImpactPreview)),
            ("S2-18", .openSheet, .linkedPage(.classifierImpactPreview)),
            ("S2-21", .openSheet, .linkedPage(.importConflictBatch)),
            ("S2-22", .navigate, .linkedPage(.redo)),
            ("S2-23", .navigate, .linkedPage(.tagSuggestions)),
            ("S2-19", .navigate, .classifierRuleEditor)
        ]

        for (route, action, expectedRoute) in routes {
            let target = CommandTargetSnapshot.s215RouteFixture(
                id: "target-\(route)-\(action.rawValue)",
                action: action,
                route: route,
                requiresConfirmation: route == "S2-21"
            )

            XCTAssertEqual(target.executionRoute, expectedRoute)
            XCTAssertTrue(target.isExecutable)
        }
    }

    func testS215KeyboardSelectionSkipsDisabledTargetsAndWraps() {
        let first = CommandTargetSnapshot.s215RouteFixture(id: "import", action: .openSheet, route: "import")
        let disabled = CommandTargetSnapshot.s215RouteFixture(
            id: "disabled",
            action: .openSheet,
            route: "S2-09",
            disabled: true
        )
        let last = CommandTargetSnapshot.s215RouteFixture(id: "settings", action: .navigate, route: "settings")
        let targets = [first, disabled, last]

        XCTAssertEqual(CommandPaletteSelectionRouting.nextSelectedID(
            currentID: nil,
            targets: targets,
            offset: 1
        ), first.id)
        XCTAssertEqual(CommandPaletteSelectionRouting.nextSelectedID(
            currentID: first.id,
            targets: targets,
            offset: 1
        ), last.id)
        XCTAssertEqual(CommandPaletteSelectionRouting.nextSelectedID(
            currentID: first.id,
            targets: targets,
            offset: -1
        ), last.id)
    }

    @MainActor
    func testS215PageIntegrationWiresEntryCloseCommandIndexAndSmartListRun() async {
        let saved = SavedSearchSnapshot.s215CommandPaletteFixture()
        let resultFile = FileEntrySnapshot.s215CommandFileFixture(id: 88, currentName: "finance.pdf")
        let indexTarget = CommandTarget.s215Fixture(
            id: "smart-list:77",
            title: "Finance",
            action: .runSmartList,
            route: nil,
            savedSearchID: saved.id
        )
        let indexer = S215CommandIndexStore(results: [.success(.s215Fixture(smartLists: [indexTarget]))])
        let smartListRunner = S215SmartListRunner(results: [
            .success(.s215CommandSmartListPage(saved: saved, files: [resultFile]))
        ])
        let model = MainFileListModel(
            opening: .s215CommandFixture(repoPath: "/tmp/repo", files: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            searchQuerying: smartListRunner,
            commandIndexer: indexer,
            errorMapper: S215CommandErrorMapper(mapping: .s215CommandDb(rawContext: "unused"))
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
            S215SmartListRunRequest(repoPath: "/tmp/repo", savedSearchID: saved.id, limit: 50, offset: 0)
        ])
        XCTAssertEqual(searchRequests, [])
        XCTAssertEqual(model.files, [resultFile])
        XCTAssertEqual(model.commandPaletteState, .idle)
        XCTAssertEqual(model.commandPaletteQuery, "")
        XCTAssertEqual(model.lastSearchExitContext, .smartList(id: saved.id, name: saved.name))
    }

    @MainActor
    func testS215PageIntegrationRoutesDangerCommandsToConfirmationWithoutDirectMutation() {
        let file = FileEntrySnapshot.s215CommandFileFixture(id: 515, currentName: "delete.pdf")
        let model = MainFileListModel(
            opening: .s215CommandFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            errorMapper: S215CommandErrorMapper(mapping: .s215CommandDb(rawContext: "unused"))
        )
        let target = CommandTargetSnapshot.s215RouteFixture(
            id: "selection.delete",
            action: .openConfirmation,
            route: "S2-13",
            requiresConfirmation: true
        )
        let route = CommandPaletteBatchRouteBuilder.batchDeleteRoute(
            selectedFileIDs: [file.id],
            visibleFiles: [file],
            isReadOnly: model.isReadOnly,
            isLoading: model.isLoading,
            writeLockedFileIDs: model.writeLockedFileIDs
        )

        model.commandPaletteState = .loaded(CommandPaletteSnapshot(coreIndex: .s215Fixture()))
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
    func testS215CommandPaletteToggleRestoresPreviousSearchFocus() {
        let model = MainFileListModel(
            opening: .s215CommandFixture(repoPath: "/tmp/repo", files: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: MainListRecordingFileDetailer(results: []),
            errorMapper: S215CommandErrorMapper(mapping: .s215CommandDb(rawContext: "unused"))
        )

        model.openCommandPaletteForSearch()
        XCTAssertEqual(model.pendingSearchDestination, .commandPalette)
        XCTAssertEqual(model.lastSearchExitContext, .toolbar)

        model.clearCommandPaletteState()
        model.clearPendingSearchDestination()
        XCTAssertNil(model.pendingSearchDestination)
        XCTAssertEqual(model.commandPaletteState, .idle)
    }

    @MainActor
    func testS222CommandPaletteRedoExecutesLatestRedoActionDirectly() async {
        let redoStore = S222RecordingRedoStore(results: [
            .list(.success([.s222AvailableMoveRedo()])),
            .redo(.success(.s222RedoneMove())),
            .list(.success([.s222ExecutedMoveRedo()]))
        ])
        let undoStore = S215NoopUndoStore()
        let errorMapper = S215CommandErrorMapper(mapping: .s215CommandDb(rawContext: "unused"))

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
        XCTAssertEqual(result, .s222RedoneMove())
        XCTAssertEqual(refreshed.redoActions, [.s222ExecutedMoveRedo()])
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, ["/tmp/repo|redo-move-3"])
        let listRequests = await redoStore.listRequests()
        XCTAssertEqual(listRequests, ["/tmp/repo", "/tmp/repo"])
    }

    @MainActor
    func testS222ShiftCommandZExecutesSameLatestRedoAction() async {
        let redoStore = S222RecordingRedoStore(results: [
            .list(.success([.s222AvailableMoveRedo()])),
            .redo(.success(.s222RedoneMove())),
            .list(.success([.s222ExecutedMoveRedo()]))
        ])
        let undoStore = S215NoopUndoStore()
        let errorMapper = S215CommandErrorMapper(mapping: .s215CommandDb(rawContext: "unused"))

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
    func testS222ShortcutKeepsUndoHistoryFailureEvidenceWhenRedoIsUnavailable() async {
        let redoStore = S222RecordingRedoStore(results: [.list(.success([]))])
        let undoStore = S215NoopUndoStore()
        let errorMapper = S215CommandErrorMapper(mapping: .s215CommandDb(rawContext: "unused"))

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
        XCTAssertEqual(request.failureMapping?.rawContext, "S2-22 C2-18 redo-action-log")
        let redoRequests = await redoStore.redoRequests()
        XCTAssertEqual(redoRequests, [])
    }
}

private actor S215NoopUndoStore: CoreUndoActionLogging {
    func listUndoActions(repoPath _: String) async throws -> [UndoActionRecordSnapshot] {
        []
    }

    func undoAction(repoPath _: String, actionID _: String) async throws -> UndoActionResultSnapshot {
        throw CoreError.Internal(message: "S2-15/S2-22 test does not execute undo actions")
    }
}

private struct MainEmptyImportStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

private struct MainEmptyImportNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private struct MainEmptyImportStaticImportPicker: RepositoryImportPicking {
    let urls: [URL]?

    @MainActor
    func chooseImportURLs() -> [URL]? {
        urls
    }
}

@MainActor
private final class MainEmptyImportAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }
}

private extension RepositoryOpeningResult {
    static func mainEmptyImportFixture(repoPath: String) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(slug: "__root__", displayName: "资料库", fileCount: 0, children: []),
            currentCategoryFiles: []
        )
    }
}
