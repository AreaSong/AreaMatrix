@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import XCTest

final class MainLoadingAdoptExistingTests: XCTestCase {
    @MainActor
    func testMainLoadingRunsStartupRecoveryCoreRecoveryBeforeConfiguredRepositoryOpen() async {
        let report = RecoveryReportSnapshot.testFixture(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept recoverable staging file"]
        )
        let startupRecoverer = MainLoadingPausingStartupRecoverer(result: .success(report))
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: mainLoadingRepoPath(), fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: startupRecoverer,
            scanSessionReader: StaticScanSessionReader(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: mainLoadingRepoPath())
        let openTask = Task {
            await model.openExistingRepository(validation)
        }

        await startupRecoverer.waitUntilStarted()
        await opener.assertNoConfiguredRepoPaths()
        await startupRecoverer.assertRequestedRepoPaths([mainLoadingRepoPath()])

        await startupRecoverer.finishRecovery()
        guard let recoveredState = await waitForMainLoadingState(model, matching: {
            $0.recoveryVisibleReport == report
        }) else {
            await opener.finishOpen()
            await openTask.value
            return
        }

        XCTAssertEqual(
            recoveredState.recoveryStatusText,
            "Startup recovery completed: Temporary files cleaned: 2; staging records reverted: 1"
        )

        await opener.finishOpen()
        await openTask.value
    }

    @MainActor
    func testMainLoadingRecoveryFailureMapsRetryableDbErrorInlineAndDoesNotOpenOrSaveRepository() async {
        let writer = MainLoadingRecordingSettingsWriter()
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "recovery db locked")
        let startupRecoverer = RecordingCoreStartupRecoverer(
            result: .failure(CoreError.Db(message: "recovery db locked"))
        )
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: mainLoadingRepoPath(), fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            startupRecoverer: startupRecoverer,
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: mainLoadingRepoPath())
        await model.openExistingRepository(validation)

        await opener.assertNoConfiguredRepoPaths()
        writer.assertNoSavedRepoPaths()
        await startupRecoverer.assertRequestedRepoPaths([mainLoadingRepoPath()])
        guard let state = requireMainLoadingState(model, message: "expected inline main loading error") else { return }
        XCTAssertEqual(state.recoveryErrorMapping, mapping)
        XCTAssertEqual(state.treeLoading, .failed(mapping))
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(
            state.treeStatusText,
            "Repository tree failed to load: \(L10n.string("error.unmapped.message"))"
        )
    }

    @MainActor
    func testConfiguredRepoOpenRetryableDbFailureStaysInlineInsteadOfMainRepoError() async {
        let writer = MainLoadingRecordingSettingsWriter()
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "database is locked")
        let opener = MainLoadingFailingRepositoryOpener(error: CoreError.Db(message: "database is locked"))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: mainLoadingRepoPath())
        await model.openExistingRepository(validation)

        await opener.assertRequestedConfiguredRepoPaths([mainLoadingRepoPath()])
        writer.assertNoSavedRepoPaths()
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
        guard let state = requireMainLoadingState(model, message: "expected inline main loading error") else { return }
        XCTAssertEqual(state.repoPath, mainLoadingRepoPath())
        XCTAssertEqual(state.treeLoading, .failed(mapping))
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
    }

    @MainActor
    func testSavedRepoRetryableDbOpenFailureKeepsLoadedTreeInline() async {
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "database is locked")
        let tree = RepositoryTreeNodeSnapshot.mainLoadingTreeFixture()
        let opener = MainLoadingFailingRepositoryOpener(error: CoreError.Db(message: "database is locked"))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: mainLoadingRepoPath()),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: MainLoadingRecordingTreeLister(result: .success(tree)),
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        await opener.assertRequestedConfiguredRepoPaths([mainLoadingRepoPath()])
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
        guard let state = requireMainLoadingState(model, message: "expected inline main loading error") else { return }
        XCTAssertEqual(state.repoPath, mainLoadingRepoPath())
        XCTAssertEqual(state.recoveryStatusText, "Startup recovery check completed.")
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])
        XCTAssertEqual(state.treeStatusText, "Directory loaded: 1 file")
    }

    @MainActor
    func testMainLoadingUsesBuildTreeCoreTreeWhileRepositoryOpenIsStillRunning() async {
        let tree = RepositoryTreeNodeSnapshot.mainLoadingTreeFixture()
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: mainLoadingRepoPath(), fileCount: 2)
        )
        let treeLister = MainLoadingRecordingTreeLister(result: .success(tree))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: mainLoadingRepoPath())
        let openTask = Task {
            await model.openExistingRepository(validation)
        }

        await opener.waitUntilStarted()
        guard let state = await waitForMainLoadingState(model, matching: { $0.treeRows.count == 2 }) else {
            await opener.finishOpen()
            await openTask.value
            return
        }

        await treeLister.assertRequestedRepoPaths([mainLoadingRepoPath()])
        XCTAssertEqual(state.treeStatusText, "Directory loaded: 1 file")
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])

        await opener.finishOpen()
        await openTask.value
    }

    @MainActor
    func testMainLoadingMapsBuildTreeCoreTreeFailureAndRetryReloadsTree() async {
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "tree db locked")
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: mainLoadingRepoPath(), fileCount: 2)
        )
        let treeLister = MainLoadingRecordingTreeLister(results: [
            .failure(CoreError.Db(message: "tree db locked")),
            .success(.mainLoadingTreeFixture())
        ])
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: mainLoadingRepoPath())
        let openTask = Task {
            await model.openExistingRepository(validation)
        }

        await opener.waitUntilStarted()
        guard let failedState = await waitForMainLoadingState(model, matching: {
            if case .failed = $0.treeLoading { return true }
            return false
        }) else {
            await opener.finishOpen()
            await openTask.value
            return
        }

        XCTAssertEqual(
            failedState.treeStatusText,
            "Repository tree failed to load: \(L10n.string("error.unmapped.message"))"
        )

        await model.retryMainLoadingTree()

        guard let retriedState = requireMainLoadingState(model, message: "expected main loading after retry") else {
            await opener.finishOpen()
            await openTask.value
            return
        }

        await treeLister.assertRequestedRepoPaths([mainLoadingRepoPath(), mainLoadingRepoPath()])
        XCTAssertEqual(retriedState.treeRows.map(\.id), ["docs", "docs/contracts"])

        await opener.finishOpen()
        await openTask.value
    }

    func testDefaultCoreBridgeListsRealRepositoryTreeForMainLoading() async throws {
        let repoURL = try makeMainLoadingTemporaryRepositoryURL()
        defer { removeTestTemporaryItems(repoURL) }

        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "hello".write(to: docsURL.appendingPathComponent("plan.txt"), atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")

        XCTAssertGreaterThan(tree.totalFileCount, 0)
        XCTAssertTrue(tree.sidebarRows.contains { $0.id == "docs" })
    }
}
