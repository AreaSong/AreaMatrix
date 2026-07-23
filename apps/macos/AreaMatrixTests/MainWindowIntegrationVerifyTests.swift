@testable import AreaMatrix
import XCTest

final class MainWindowIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testMainWindowIntegrationRoutesEmptyAndPopulatedRepositoriesToMainPages() async {
        let emptyOpening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/empty-repo", fileCount: 0)
        let empty = await openConfiguredRepository(opening: emptyOpening)

        XCTAssertEqual(empty.route, .mainEmpty(emptyOpening))
        empty.assertNoSavedRepoPaths()
        empty.assertSuccessfulRepoOpenPaths(["/tmp/empty-repo"])

        let populatedOpening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/list-repo", fileCount: 4)
        let populated = await openConfiguredRepository(opening: populatedOpening)

        XCTAssertEqual(populated.route, .mainList(populatedOpening))
        populated.assertSuccessfulRepoOpenPaths(["/tmp/list-repo"])
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
        writer.assertNoSavedRepoPaths()
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])
        XCTAssertEqual(
            state.treeStatusText,
            L10n.plural("onboarding.loading.treeFileCount", count: 1)
        )
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

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        writer.assertNoSavedRepoPaths()
        await mapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: "/tmp/repo")])
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
    func testMainWindowMenuCommandsRouteSettingsAndImportForOpenRepository() throws {
        let repoURL = try makeTestTemporaryDirectory(named: "AreaMatrixMenuCommandRepo")
        let importURL = repoURL.appendingPathComponent("source.pdf")
        defer { removeTestTemporaryItems(repoURL) }
        try Data("menu import".utf8).write(to: importURL)
        let opening = RepositoryOpeningResult.shellFixture(repoPath: repoURL.path, fileCount: 0)
        let model = OnboardingModel(
            emptyRepositoryOpener: ShellRecordingRepositoryOpener(result: .success(opening)),
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            helpOpener: NoopWelcomeHelpOpener(),
            importPicker: ShellStaticImportPicker(urls: [importURL])
        )
        model.route = .mainEmpty(opening)

        model.handleSettingsMenuCommand()
        XCTAssertEqual(model.route, .settingsGeneral(opening))

        model.handleImportMenuCommand()
        XCTAssertEqual(model.pendingImportEntry?.urls, [importURL])
    }

    @MainActor
    func testSettingsCommandShowsAppLanguageSettingsWithoutRepository() {
        let model = OnboardingModel(
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .welcome

        model.handleSettingsMenuCommand()

        XCTAssertEqual(model.route, .welcome)
        XCTAssertTrue(model.isAppLanguageSettingsPresented)
        XCTAssertNil(model.toastMessage)

        model.closeAppLanguageSettings()
        XCTAssertFalse(model.isAppLanguageSettingsPresented)
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
        await opener.assertRequestedConfiguredRepoPaths([opening.config.repoPath])
        return MainWindowIntegrationOpenResult(
            route: model.route,
            writer: writer
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
    let writer: ShellRecordingSettingsWriter

    func assertSavedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        writer.assertSavedRepoPaths(expectedRepoPaths, file: file, line: line)
    }

    func assertNoSavedRepoPaths(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        writer.assertNoSavedRepoPaths(file: file, line: line)
    }

    func assertSuccessfulRepoOpenPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        writer.assertSuccessfulRepoOpenPaths(expectedRepoPaths, file: file, line: line)
    }
}
