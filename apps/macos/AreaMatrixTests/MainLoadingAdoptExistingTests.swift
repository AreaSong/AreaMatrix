@testable import AreaMatrix
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
        let openRequestsBeforeRecoveryFinishes = await opener.requestedConfiguredRepoPaths()
        let recoveryRequests = await startupRecoverer.requestedRepoPaths()
        XCTAssertEqual(openRequestsBeforeRecoveryFinishes, [])
        XCTAssertEqual(recoveryRequests, [mainLoadingRepoPath()])

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
            "启动恢复已完成：清理 2 个临时文件，回滚 1 条 staging 记录"
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

        let openRequests = await opener.requestedConfiguredRepoPaths()
        let recoveryRequests = await startupRecoverer.requestedRepoPaths()
        XCTAssertEqual(openRequests, [])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(recoveryRequests, [mainLoadingRepoPath()])
        guard case let .mainLoading(state) = model.route else {
            return XCTFail("expected inline main loading error, got \(model.route)")
        }
        XCTAssertEqual(state.recoveryErrorMapping, mapping)
        XCTAssertEqual(state.treeLoading, .failed(mapping))
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeStatusText, "目录加载失败：扫描状态暂不可用")
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

        let openRequests = await opener.requestedConfiguredRepoPaths()
        XCTAssertEqual(openRequests, [mainLoadingRepoPath()])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
        guard case let .mainLoading(state) = model.route else {
            return XCTFail("expected inline main loading error, got \(model.route)")
        }
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

        let openRequests = await opener.requestedConfiguredRepoPaths()
        XCTAssertEqual(openRequests, [mainLoadingRepoPath()])
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
        guard case let .mainLoading(state) = model.route else {
            return XCTFail("expected inline main loading error, got \(model.route)")
        }
        XCTAssertEqual(state.repoPath, mainLoadingRepoPath())
        XCTAssertEqual(state.recoveryStatusText, "启动恢复检查完成")
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")
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

        let treeRequests = await treeLister.requestedRepoPaths()
        XCTAssertEqual(treeRequests, [mainLoadingRepoPath()])
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")
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

        XCTAssertEqual(failedState.treeStatusText, "目录加载失败：扫描状态暂不可用")

        await model.retryMainLoadingTree()

        guard case let .mainLoading(retriedState) = model.route else {
            await opener.finishOpen()
            await openTask.value
            return XCTFail("expected main loading after retry, got \(model.route)")
        }

        let treeRequests = await treeLister.requestedRepoPaths()
        XCTAssertEqual(treeRequests, [mainLoadingRepoPath(), mainLoadingRepoPath()])
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
