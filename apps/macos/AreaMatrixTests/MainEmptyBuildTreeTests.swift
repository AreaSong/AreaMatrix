@testable import AreaMatrix
import Foundation
import XCTest

final class MainEmptyBuildTreeTests: XCTestCase {
    func testDefaultCoreBridgeListsRealEmptyRepositoryTreeForMainEmpty() async throws {
        let repoURL = try makeBuildTreeTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")

        XCTAssertEqual(tree.slug, "__root__")
        XCTAssertEqual(tree.kind, "RepositoryRoot")
        XCTAssertEqual(tree.relativePath, "")
        XCTAssertEqual(tree.fileCount, 0)
        XCTAssertEqual(tree.totalFileCount, 0)
        XCTAssertEqual(Set(tree.children.map(\.slug)), Set(["inbox", "docs", "code", "design", "finance", "media"]))
        XCTAssertEqual(tree.sidebarNodes.map(\.slug), ["inbox", "docs", "code", "design", "finance", "media"])
        XCTAssertEqual(tree.sidebarNodes.map(\.totalFileCount), Array(repeating: 0, count: 6))
    }

    func testDefaultCoreBridgePropagatesBuildTreeRepoNotInitializedError() async throws {
        let repoURL = try makeBuildTreeTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

        do {
            _ = try await CoreBridge().listTree(repoPath: repoURL.path, locale: "zh-Hans")
            XCTFail("expected RepoNotInitialized from list_tree_json")
        } catch let error as CoreError {
            guard case .RepoNotInitialized = error else {
                return XCTFail("expected RepoNotInitialized, got \(error)")
            }
        }
    }

    @MainActor
    func testMainEmptyOpeningUsesBuildTreeCoreTreeNodesForVisibleSidebar() async {
        let tree = RepositoryTreeNodeSnapshot.mainEmptyFixtureTree()
        let opening = RepositoryOpeningResult.mainEmptyBuildTreeFixture(repoPath: "/tmp/repo", tree: tree)
        let opener = BuildTreeRecordingRepositoryOpener(opening: opening)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .mainEmpty(routedOpening) = model.route else {
            return XCTFail("expected main empty route, got \(model.route)")
        }

        XCTAssertEqual(requestedPaths, ["/tmp/repo"])
        XCTAssertEqual(routedOpening.tree.children.map(\.slug), ["inbox", "docs", "code", "design", "finance", "media"])
        XCTAssertEqual(routedOpening.tree.children.first?.displayName, "inbox")
        XCTAssertEqual(routedOpening.tree.children.first?.totalFileCount, 0)
    }

    @MainActor
    func testCommandPaletteCommandPaletteNoRepositoryShowsOnlySafeCommands() {
        let content = MainRepositoryContentView(
            opening: .commandPaletteCommandFixture(repoPath: "/tmp/repo", files: []),
            state: .empty,
            onImport: {},
            onDropImport: { _, _ in },
            onOpenSettings: {},
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            errorMapper: StaticCoreErrorMapper(mapping: .commandPaletteCommandDb(rawContext: "unused"))
        )

        XCTAssertEqual(content.visibleCommandPaletteState.snapshot?.targetTitles, [
            "Open repository...", "Settings", "Help"
        ])
    }

    @MainActor
    func testCommandPaletteCommandPaletteIndexFailureKeepsAvailableCommands() async {
        let previous = CommandPaletteSnapshot(
            sections: [.init(title: "Commands", targets: [.importFiles])],
            generatedAt: 1
        )
        let mapping = CoreErrorMappingSnapshot.commandPaletteCommandDb(rawContext: "command registry locked")
        let model = MainFileListModel(
            opening: .commandPaletteCommandFixture(repoPath: "/tmp/repo", files: []),
            fileLister: MainListRecordingFileLister(results: []),
            fileDetailer: RecordingFileDetailer(results: []),
            commandIndexer: CommandPaletteCommandIndexStore(results: [.failure(CoreError.Db(message: "locked"))]),
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        model.commandPaletteState = .loaded(previous)
        await model.loadCommandIndex(query: "import", selectedFileIDs: [], currentPath: nil)

        XCTAssertEqual(model.commandPaletteState.errorMapping, mapping)
        XCTAssertEqual(model.commandPaletteState.snapshot?.targetTitles, ["Import files..."])
    }

    @MainActor
    func testCommandPaletteCommandPaletteLinkedRoutesPreserveBlockedEvidenceOrOpenRedoHost() {
        let snapshot = CommandPaletteSnapshot.commandRegistryRecovery(query: "classifier")
        let classifierMapping = CommandPaletteLinkedPageRoute.classifierImpactPreview.blockedMapping
        let redoRequest = UndoHistoryActionLog.redoShortcutRequest(
            state: .idle,
            failure: CommandPaletteLinkedPageRoute.redo.blockedMapping
        )

        XCTAssertEqual(classifierMapping.rawContext, "classifier-impact-preview")
        XCTAssertEqual(snapshot.sections.count, 1)
        XCTAssertEqual(redoRequest.source, .viewHistory)
        XCTAssertEqual(redoRequest.failureMapping?.rawContext, "redo-action-log")
    }

    @MainActor
    func testImportConflictBatchCommandPaletteOpensImportConflictBatchWhenActiveProgressRouteExists() {
        let item = ImportBatchProgressSnapshot.Item(
            sourcePath: "/tmp/source.pdf",
            targetPath: "docs/source.pdf",
            phase: .pending,
            errorMessage: nil,
            existingRelativePath: "docs/existing.pdf",
            importConflictBatch: ImportConflictBatchProgressMetadata(
                importSessionID: "session-221",
                conflictID: "conflict-1"
            )
        )
        let route = ImportConflictBatchRoute(
            metadata: [item.importConflictBatch].compactMap { $0 },
            source: .importConflictBatch
        )

        XCTAssertEqual(route, ImportConflictBatchRoute(
            importSessionID: "session-221",
            conflictIDs: ["conflict-1"],
            source: .importConflictBatch
        ))
    }

    @MainActor
    func testImportConflictBatchCommandPaletteDoesNotFabricateImportConflictBatchWithoutActiveRoute() {
        let route = ImportConflictBatchRoute(metadata: [], source: .importConflictBatch)
        let mapping = CommandPaletteLinkedPageRoute.importConflictBatch.blockedMapping

        XCTAssertNil(route)
        XCTAssertEqual(mapping.rawContext, "import-conflict-batch")
    }

    @MainActor
    func testImportConflictBatchOnboardingStartsImportConflictBatchReviewFromRealRouteMetadata() {
        let opening = RepositoryOpeningResult.mainEmptyBuildTreeFixture(
            repoPath: "/tmp/repo",
            tree: .mainEmptyFixtureTree()
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: BuildTreeAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.startImportConflictBatchReview(
            opening: opening,
            route: ImportConflictBatchRoute(
                importSessionID: "session-221",
                conflictIDs: ["dup-1", "name-1"],
                source: .importConflictBatch
            )
        )

        XCTAssertEqual(model.pendingImportEntry?.source, .importConflictBatch(.importConflictBatch))
        XCTAssertEqual(model.pendingImportEntry?.importSessionID, "session-221")
        XCTAssertEqual(model.pendingImportEntry?.importConflictIDs, ["dup-1", "name-1"])
        XCTAssertEqual(model.pendingImportEntry?.kind, .multipleItems(2))
    }
}

private extension CommandPaletteSnapshot {
    var targetTitles: [String] {
        sections.flatMap(\.targets).map(\.title)
    }
}

private typealias BuildTreeRecordingRepositoryOpener = RecordingRepositoryOpener

@MainActor
private final class BuildTreeAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }
}

private extension RepositoryOpeningResult {
    static func mainEmptyBuildTreeFixture(
        repoPath: String,
        tree: RepositoryTreeNodeSnapshot
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainEmptyBuildTreeFixture(repoPath: repoPath),
            tree: tree,
            currentCategoryFiles: []
        )
    }
}

private extension RepoConfigSnapshot {
    static func mainEmptyBuildTreeFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func mainEmptyFixtureTree() -> RepositoryTreeNodeSnapshot {
        .testRoot(
            displayName: "资料库",
            children: ["inbox", "docs", "code", "design", "finance", "media"].map { .testCategory($0) }
        )
    }
}

private func makeBuildTreeTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixBuildTreeTests")
}
