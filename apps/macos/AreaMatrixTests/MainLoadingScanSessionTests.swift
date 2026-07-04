@testable import AreaMatrix
import XCTest

final class MainLoadingScanSessionTests: XCTestCase {
    @MainActor
    func testInitializedAdoptOpenShowsLatestScanSessionInMainLoading() async {
        let scanSession = ScanSessionSnapshot.mainLoadingAdoptFixture(status: .running)
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/adopted-repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(session: scanSession),
            helpOpener: NoopWelcomeHelpOpener()
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
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(result: .failure(CoreError.Db(message: "scan db locked"))),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
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
            settingsReader: StaticSettingsReader(repoPath: "/tmp/saved-repo"),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(session: scanSession),
            helpOpener: NoopWelcomeHelpOpener()
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
    func testMainLoadingShowsReindexRescanProgressAndFailureStatus() {
        let runningSession = ScanSessionSnapshot.mainLoadingReindexFixture(status: .running)
        let failedSession = ScanSessionSnapshot.mainLoadingReindexFixture(
            status: .failed,
            errors: ["docs/contracts/customer.pdf could not be indexed"]
        )

        var state = MainLoadingState(repoPath: mainLoadingRepoPath(), scanSession: runningSession)
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
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: mainLoadingRepoPath(), fileCount: 1)
        let opener = MainLoadingPausingRepositoryOpener(opening: opening)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: mainLoadingRepoPath())
        let openTask = Task {
            await model.openExistingRepository(validation)
        }
        await opener.waitUntilStarted()

        model.cancelMainOpening()
        await opener.finishOpen()
        await openTask.value

        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.route, .validatePath)
        XCTAssertEqual(model.repositoryPathText, mainLoadingRepoPath())
        XCTAssertEqual(
            model.toastMessage,
            "Opening was cancelled. Repository configuration and user files were not changed."
        )
    }
}
