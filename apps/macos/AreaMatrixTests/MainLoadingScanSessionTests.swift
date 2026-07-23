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
        XCTAssertEqual(state.scanStatusText, "Scanning repository: 15 processed")
        XCTAssertEqual(state.scanProgressText, "Added 12, updated 2, skipped 1")
        XCTAssertEqual(state.scanCurrentPathText, "Current path: docs/plan.md")

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
        XCTAssertEqual(state.scanStatusText, "Scan status is unavailable: 扫描状态暂不可用")

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

        await treeLister.assertRequestedRepoPaths(["/tmp/saved-repo"])
        XCTAssertEqual(state.scanStatusText, "Scanning repository: 15 processed")
        XCTAssertEqual(state.treeStatusText, "Directory loaded: 1 file")

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
        XCTAssertEqual(state.scanStatusText, "Scanning repository: 324 processed")
        XCTAssertEqual(state.scanProgressText, "Added 300, updated 20, skipped 4")
        XCTAssertEqual(state.scanCurrentPathText, "Current path: docs/contracts/customer.pdf")
        XCTAssertTrue(state.accessibilityStatusText.contains("Scanning changes"))

        state.scanSession = failedSession
        XCTAssertEqual(state.scanStatusText, "Rescan failed · 324 processed")
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

        writer.assertNoSavedRepoPaths()
        XCTAssertEqual(model.route, .validatePath)
        XCTAssertEqual(model.repositoryPathText, mainLoadingRepoPath())
        XCTAssertEqual(
            model.toastMessage,
            L10n.message("Opening was cancelled. Repository configuration and user files were not changed.")
        )
    }
}
