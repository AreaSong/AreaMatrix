@testable import AreaMatrix
import XCTest

final class MainWindowIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testMainWindowIntegrationRoutesEmptyAndPopulatedRepositoriesToMainPages() async {
        let emptyOpening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let empty = await openConfiguredRepository(opening: emptyOpening)

        XCTAssertEqual(empty.route, .mainEmpty(emptyOpening))
        XCTAssertEqual(empty.openedRepoPaths, ["/tmp/empty-repo"])
        XCTAssertEqual(empty.savedRepoPaths, [])
        XCTAssertEqual(empty.successfulRepoOpenPaths, ["/tmp/empty-repo"])

        let populatedOpening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/list-repo", fileCount: 4)
        let populated = await openConfiguredRepository(opening: populatedOpening)

        XCTAssertEqual(populated.route, .mainList(populatedOpening))
        XCTAssertEqual(populated.openedRepoPaths, ["/tmp/list-repo"])
        XCTAssertEqual(populated.successfulRepoOpenPaths, ["/tmp/list-repo"])
    }

    @MainActor
    func testMainWindowIntegrationKeepsRetryableDbFailureInMainLoading() async {
        let mapping = CoreErrorMappingSnapshot.mainWindowMapping(
            kind: .db,
            severity: .medium,
            recoverability: .retryable,
            rawContext: "database is locked"
        )
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreError.Db(message: "database is locked")))
        let writer = ShellRecordingSettingsWriter()
        let model = mainWindowModel(
            repoPath: "/tmp/repo",
            writer: writer,
            opener: opener,
            treeLister: MainLoadingRecordingTreeLister(result: .success(.mainLoadingTreeFixture())),
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        await model.bootstrapIfNeeded()

        guard let state = requireMainLoadingState(model, message: "expected main-loading route") else { return }

        await opener.assertRequestedConfiguredRepoPaths(["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")
    }

    @MainActor
    func testMainWindowIntegrationRoutesCriticalRepoFailureToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.mainWindowMapping(
            kind: .permissionDenied,
            rawContext: "/tmp/repo"
        )
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let writer = ShellRecordingSettingsWriter()
        let model = mainWindowModel(
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
            .searchFiles,
            .listFilterFacets,
            .runSmartList,
            .getFile,
            .previewBatchDelete,
            .batchDeleteToTrash,
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
        let model = mainWindowModel(
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
    private func mainWindowModel(
        repoPath: String,
        writer: ShellRecordingSettingsWriter,
        opener: ShellRecordingRepositoryOpener,
        treeLister: (any CoreRepositoryTreeListing)? = nil,
        errorMapper: any CoreErrorMapping = StaticCoreErrorMapper(mapping: .mainWindowMapping(kind: .db))
    ) -> OnboardingModel {
        OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: repoPath),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )
    }
}

private struct MainWindowIntegrationOpenResult {
    var route: OnboardingModel.Route
    var openedRepoPaths: [String]
    var savedRepoPaths: [String]
    var successfulRepoOpenPaths: [String]
}
