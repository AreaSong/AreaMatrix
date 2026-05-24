@testable import AreaMatrix
import Foundation
import SwiftUI
import XCTest

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

        await model.loadCommandIndex(query: "", selectedFileIDs: Set<Int64>(), currentPath: Optional<String>.none)
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
}

struct S215CommandIndexRequest: Equatable {
    var repoPath: String
    var context: CommandIndexContext
}

actor S215CommandIndexStore: CoreCommandIndexing {
    enum Result { case success(CommandIndex), failure(Error) }

    private var results: [Result]
    private var requests: [S215CommandIndexRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listCommandTargets(repoPath: String, context: CommandIndexContext) async throws -> CommandIndex {
        requests.append(.init(repoPath: repoPath, context: context))
        guard !results.isEmpty else { return .s215Fixture() }
        switch results.removeFirst() {
        case let .success(index): return index
        case let .failure(error): throw error
        }
    }

    func recordedRequests() -> [S215CommandIndexRequest] {
        requests
    }
}

actor S215CommandErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
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
