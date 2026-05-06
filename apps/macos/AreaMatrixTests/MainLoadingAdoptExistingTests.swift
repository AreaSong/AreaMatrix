import XCTest
@testable import AreaMatrix

final class MainLoadingAdoptExistingTests: XCTestCase {
    @MainActor
    func testMainLoadingRunsC116RecoveryBeforeConfiguredRepositoryOpen() async {
        let report = RecoveryReportSnapshot(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept recoverable staging file"]
        )
        let startupRecoverer = MainLoadingPausingStartupRecoverer(result: .success(report))
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: startupRecoverer,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        let openTask = Task {
            await model.openExistingRepository(validation)
        }

        await startupRecoverer.waitUntilStarted()
        let openRequestsBeforeRecoveryFinishes = await opener.requestedConfiguredRepoPaths()
        let recoveryRequests = await startupRecoverer.requestedRepoPaths()
        XCTAssertEqual(openRequestsBeforeRecoveryFinishes, [])
        XCTAssertEqual(recoveryRequests, ["/tmp/repo"])

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
        let startupRecoverer = MainLoadingRecordingStartupRecoverer(
            result: .failure(CoreError.Db(message: "recovery db locked"))
        )
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            startupRecoverer: startupRecoverer,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: MainLoadingRecordingErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        await model.openExistingRepository(validation)

        let openRequests = await opener.requestedConfiguredRepoPaths()
        let recoveryRequests = await startupRecoverer.requestedRepoPaths()
        XCTAssertEqual(openRequests, [])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(recoveryRequests, ["/tmp/repo"])
        guard case .mainLoading(let state) = model.route else {
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
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: MainLoadingRecordingErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        await model.openExistingRepository(validation)

        let openRequests = await opener.requestedConfiguredRepoPaths()
        XCTAssertEqual(openRequests, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
        guard case .mainLoading(let state) = model.route else {
            return XCTFail("expected inline main loading error, got \(model.route)")
        }
        XCTAssertEqual(state.repoPath, "/tmp/repo")
        XCTAssertEqual(state.treeLoading, .failed(mapping))
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
    }

    @MainActor
    func testSavedRepoRetryableDbOpenFailureKeepsLoadedTreeInline() async {
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "database is locked")
        let tree = RepositoryTreeNodeSnapshot.mainLoadingTreeFixture()
        let opener = MainLoadingFailingRepositoryOpener(error: CoreError.Db(message: "database is locked"))
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: MainLoadingRecordingTreeLister(result: .success(tree)),
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: MainLoadingRecordingErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()

        let openRequests = await opener.requestedConfiguredRepoPaths()
        XCTAssertEqual(openRequests, ["/tmp/repo"])
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping, mapping)
        guard case .mainLoading(let state) = model.route else {
            return XCTFail("expected inline main loading error, got \(model.route)")
        }
        XCTAssertEqual(state.repoPath, "/tmp/repo")
        XCTAssertEqual(state.recoveryStatusText, "启动恢复检查完成")
        XCTAssertEqual(state.repositoryOpeningErrorMapping, mapping)
        XCTAssertEqual(state.treeRows.map(\.id), ["docs", "docs/contracts"])
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")
    }

    @MainActor
    func testMainLoadingUsesC115TreeWhileRepositoryOpenIsStillRunning() async {
        let tree = RepositoryTreeNodeSnapshot.mainLoadingTreeFixture()
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 2)
        )
        let treeLister = MainLoadingRecordingTreeLister(result: .success(tree))
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
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
        XCTAssertEqual(treeRequests, ["/tmp/repo"])
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")
        XCTAssertEqual(state.treeRows.map { $0.id }, ["docs", "docs/contracts"])

        await opener.finishOpen()
        await openTask.value
    }

    @MainActor
    func testMainLoadingMapsC115TreeFailureAndRetryReloadsTree() async {
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "tree db locked")
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 2)
        )
        let treeLister = MainLoadingRecordingTreeLister(results: [
            .failure(CoreError.Db(message: "tree db locked")),
            .success(.mainLoadingTreeFixture()),
        ])
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: MainLoadingRecordingErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
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

        guard case .mainLoading(let retriedState) = model.route else {
            await opener.finishOpen()
            await openTask.value
            return XCTFail("expected main loading after retry, got \(model.route)")
        }

        let treeRequests = await treeLister.requestedRepoPaths()
        XCTAssertEqual(treeRequests, ["/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(retriedState.treeRows.map { $0.id }, ["docs", "docs/contracts"])

        await opener.finishOpen()
        await openTask.value
    }

    func testDefaultCoreBridgeListsRealRepositoryTreeForMainLoading() async throws {
        let repoURL = try makeMainLoadingTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        try "hello".write(to: docsURL.appendingPathComponent("plan.txt"), atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let tree = try await bridge.listTree(repoPath: repoURL.path, locale: "zh-Hans")

        XCTAssertGreaterThan(tree.totalFileCount, 0)
        XCTAssertTrue(tree.sidebarRows.contains { $0.id == "docs" })
    }

    @MainActor
    func testInitializedAdoptOpenShowsLatestScanSessionInMainLoading() async {
        let scanSession = ScanSessionSnapshot.mainLoadingAdoptFixture(status: .running)
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/adopted-repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(scanSession)),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        ))
        let openTask = Task {
            await model.openInitializedRepository()
        }

        await opener.waitUntilStarted()
        guard let state = await waitForMainLoadingState(model, matching: {
            $0.scanSession == scanSession
        }) else {
            await opener.finishOpen()
            await openTask.value
            return
        }

        XCTAssertEqual(state.repoPath, "/tmp/adopted-repo")
        XCTAssertEqual(state.scanSession, scanSession)
        XCTAssertEqual(state.scanStatusText, "正在扫描资料库 15")
        XCTAssertEqual(state.scanProgressText, "新增 12，更新 2，跳过 1")
        XCTAssertEqual(state.scanCurrentPathText, "当前路径：docs/plan.md")

        await opener.finishOpen()
        await openTask.value
    }

    @MainActor
    func testMainLoadingMapsLatestScanSessionFailureWithoutBlockingRepositoryOpen() async {
        let mapping = CoreErrorMappingSnapshot.mainLoadingDbFixture(rawContext: "scan db locked")
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/adopted-repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .failure(CoreError.Db(message: "scan db locked"))),
            errorMapper: MainLoadingRecordingErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        ))
        let openTask = Task {
            await model.openInitializedRepository()
        }

        await opener.waitUntilStarted()
        guard let state = await waitForMainLoadingState(model, matching: { $0.scanSessionErrorMapping != nil }) else {
            await opener.finishOpen()
            await openTask.value
            return
        }

        XCTAssertEqual(state.scanSessionErrorMapping, mapping)
        XCTAssertEqual(state.scanStatusText, "扫描状态不可用：扫描状态暂不可用")

        await opener.finishOpen()
        await openTask.value
    }

    @MainActor
    func testConfiguredRepositoryMainLoadingRefreshesTreeAndScanSessionBeforeOpenCompletes() async {
        let scanSession = ScanSessionSnapshot.mainLoadingAdoptFixture(status: .running)
        let tree = RepositoryTreeNodeSnapshot.mainLoadingTreeFixture()
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/saved-repo", fileCount: 1)
        )
        let treeLister = MainLoadingRecordingTreeLister(result: .success(tree))
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: "/tmp/saved-repo"),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(scanSession)),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let bootstrapTask = Task {
            await model.bootstrapIfNeeded()
        }

        await opener.waitUntilStarted()
        guard let state = await waitForMainLoadingState(model, matching: {
            $0.scanSession == scanSession && $0.treeRows.count == 2
        }) else {
            await opener.finishOpen()
            await bootstrapTask.value
            return
        }

        let treeRequests = await treeLister.requestedRepoPaths()
        XCTAssertEqual(treeRequests, ["/tmp/saved-repo"])
        XCTAssertEqual(state.scanStatusText, "正在扫描资料库 15")
        XCTAssertEqual(state.treeStatusText, "目录已加载：1 个文件")

        await opener.finishOpen()
        await bootstrapTask.value
    }

    @MainActor
    func testMainLoadingShowsReindexRescanProgressAndFailureStatus() async {
        let runningSession = ScanSessionSnapshot.mainLoadingReindexFixture(status: .running)
        let failedSession = ScanSessionSnapshot.mainLoadingReindexFixture(
            status: .failed,
            errors: ["docs/contracts/customer.pdf could not be indexed"]
        )

        var state = MainLoadingState(repoPath: "/tmp/repo", scanSession: runningSession)
        XCTAssertEqual(state.scanStatusText, "正在扫描资料库 324")
        XCTAssertEqual(state.scanProgressText, "新增 300，更新 20，跳过 4")
        XCTAssertEqual(state.scanCurrentPathText, "当前路径：docs/contracts/customer.pdf")
        XCTAssertTrue(state.accessibilityStatusText.contains("Scanning changes"))

        state.scanSession = failedSession
        XCTAssertEqual(state.scanStatusText, "重新扫描失败 324")
        XCTAssertEqual(state.scanWarningText, "docs/contracts/customer.pdf could not be indexed")
    }

    @MainActor
    func testCancelMainOpeningDoesNotSaveConfiguredRepoOrApplyLateOpenResult() async {
        let writer = MainLoadingRecordingSettingsWriter()
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        let opener = MainLoadingPausingRepositoryOpener(opening: opening)
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            startupRecoverer: MainLoadingStaticStartupRecoverer(),
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        let openTask = Task {
            await model.openExistingRepository(validation)
        }
        await opener.waitUntilStarted()

        model.cancelMainOpening()
        await opener.finishOpen()
        await openTask.value

        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.route, .validatePath)
        XCTAssertEqual(model.repositoryPathText, "/tmp/repo")
        XCTAssertEqual(
            model.toastMessage,
            "Opening was cancelled. Repository configuration and user files were not changed."
        )
    }
}
