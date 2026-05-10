@testable import AreaMatrix
import XCTest

final class MainWindowIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testMainWindowIntegrationRoutesEmptyAndPopulatedRepositoriesToMainPages() async {
        let emptyOpening = RepositoryOpeningResult.task34Fixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let empty = await openConfiguredRepository(opening: emptyOpening)

        XCTAssertEqual(empty.route, .mainEmpty(emptyOpening))
        XCTAssertEqual(empty.openedRepoPaths, ["/tmp/empty-repo"])
        XCTAssertEqual(empty.savedRepoPaths, [])
        XCTAssertEqual(empty.successfulRepoOpenPaths, ["/tmp/empty-repo"])

        let populatedOpening = RepositoryOpeningResult.task34Fixture(repoPath: "/tmp/list-repo", fileCount: 4)
        let populated = await openConfiguredRepository(opening: populatedOpening)

        XCTAssertEqual(populated.route, .mainList(populatedOpening))
        XCTAssertEqual(populated.openedRepoPaths, ["/tmp/list-repo"])
        XCTAssertEqual(populated.successfulRepoOpenPaths, ["/tmp/list-repo"])
    }

    @MainActor
    func testMainWindowIntegrationKeepsRetryableDbFailureInMainLoading() async {
        let mapping = CoreErrorMappingSnapshot.task34Mapping(
            kind: .db,
            severity: .medium,
            recoverability: .retryable,
            rawContext: "database is locked"
        )
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreError.Db(message: "database is locked")))
        let writer = ShellRecordingSettingsWriter()
        let model = task34Model(
            repoPath: "/tmp/repo",
            writer: writer,
            opener: opener,
            treeLister: MainLoadingRecordingTreeLister(result: .success(.mainLoadingTreeFixture())),
            errorMapper: MainWindowIntegrationErrorMapper(mapping: mapping)
        )

        await model.bootstrapIfNeeded()
        let openedRepoPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .mainLoading(state) = model.route else {
            return XCTFail("expected S1-10 main-loading, got \(model.route)")
        }

        XCTAssertEqual(openedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")
    }

    @MainActor
    func testMainWindowIntegrationRoutesCriticalRepoFailureToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.task34Mapping(
            kind: .permissionDenied,
            rawContext: "/tmp/repo"
        )
        let mapper = MainWindowIntegrationErrorMapper(mapping: mapping)
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let writer = ShellRecordingSettingsWriter()
        let model = task34Model(
            repoPath: "/tmp/repo",
            writer: writer,
            opener: opener,
            errorMapper: mapper
        )

        await model.bootstrapIfNeeded()
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertTrue(mappedErrors.contains(CoreError.PermissionDenied(path: "/tmp/repo")))
        XCTAssertEqual(RepositoryErrorPresentation.mainRepo(mapping: mapping).primaryAction, .reconnectFolder)
    }

    func testMainWindowIntegrationUsesRealCoreBridgeBoundariesForBoundCapabilities() {
        let requiredBoundaries: Set<CoreBridgeBoundary> = [
            .validateInitializedRepoPath,
            .recoverOnStartup,
            .getLatestScanSession,
            .resumeScanSession,
            .listFiles,
            .getFile,
            .listTreeJSON,
            .syncExternalChanges,
            .mapCoreError
        ]

        XCTAssertEqual(CoreBridge().state, .generatedBindings)
        XCTAssertTrue(requiredBoundaries.isSubset(of: Set(CoreBridgeBoundary.allCases)))
    }

    @MainActor
    private func openConfiguredRepository(
        opening: RepositoryOpeningResult
    ) async -> MainWindowIntegrationOpenResult {
        let opener = ShellRecordingRepositoryOpener(result: .success(opening))
        let writer = ShellRecordingSettingsWriter()
        let model = task34Model(
            repoPath: opening.config.repoPath,
            writer: writer,
            opener: opener
        )

        await model.bootstrapIfNeeded()
        return await MainWindowIntegrationOpenResult(
            route: model.route,
            openedRepoPaths: opener.requestedConfiguredRepoPaths(),
            savedRepoPaths: writer.savedRepoPaths,
            successfulRepoOpenPaths: writer.successfulRepoOpens.map(\.repoPath)
        )
    }

    @MainActor
    private func task34Model(
        repoPath: String,
        writer: ShellRecordingSettingsWriter,
        opener: ShellRecordingRepositoryOpener,
        treeLister: (any CoreRepositoryTreeListing)? = nil,
        errorMapper: any CoreErrorMapping = MainWindowIntegrationErrorMapper(mapping: .task34Mapping(kind: .db))
    ) -> OnboardingModel {
        OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: repoPath),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: ShellStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
    }
}

private struct MainWindowIntegrationOpenResult {
    var route: OnboardingModel.Route
    var openedRepoPaths: [String]
    var savedRepoPaths: [String]
    var successfulRepoOpenPaths: [String]
}

private actor MainWindowIntegrationErrorMapper: CoreErrorMapping {
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

private extension RepositoryOpeningResult {
    static func task34Fixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func task34Mapping(
        kind: CoreErrorKindSnapshot,
        severity: CoreErrorSeveritySnapshot = .high,
        recoverability: CoreErrorRecoverabilitySnapshot = .userActionRequired,
        rawContext: String = "task-34"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: severity,
            suggestedAction: "mapped action",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}
