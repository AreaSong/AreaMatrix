@testable import AreaMatrix
import Foundation
import XCTest

final class MainEmptyBuildTreeTests: XCTestCase {
    func testDefaultCoreBridgeListsRealEmptyRepositoryTreeForMainEmpty() async throws {
        let repoURL = try makeBuildTreeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

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
        defer { try? FileManager.default.removeItem(at: repoURL) }

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
    func testMainEmptyOpeningUsesC115TreeNodesForVisibleSidebar() async {
        let tree = RepositoryTreeNodeSnapshot.mainEmptyFixtureTree()
        let opening = RepositoryOpeningResult.mainEmptyBuildTreeFixture(repoPath: "/tmp/repo", tree: tree)
        let opener = BuildTreeRecordingRepositoryOpener(opening: opening)
        let model = OnboardingModel(
            settingsReader: BuildTreeStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            helpOpener: BuildTreeNoopWelcomeHelpOpener()
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
}

private actor BuildTreeRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let opening: RepositoryOpeningResult
    private var configuredPaths: [String] = []

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        return opening
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredPaths
    }
}

private struct BuildTreeStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

private struct BuildTreeNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
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
        RepoConfigSnapshot(
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
        )
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func mainEmptyFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "资料库",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: ["inbox", "docs", "code", "design", "finance", "media"].map { slug in
                RepositoryTreeNodeSnapshot(
                    slug: slug,
                    displayName: slug,
                    kind: "SystemCategory",
                    relativePath: slug,
                    fileCount: 0,
                    depth: 1,
                    children: []
                )
            }
        )
    }
}

private func makeBuildTreeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixBuildTreeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
