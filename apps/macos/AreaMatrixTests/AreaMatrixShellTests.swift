@testable import AreaMatrix
import XCTest

final class AreaMatrixShellTests: XCTestCase {
    func testBridgeUsesGeneratedBindings() {
        XCTAssertEqual(CoreBridge().state, .generatedBindings)
        XCTAssertEqual(CoreBridge().coreAvailability(), "generated-bindings")
    }

    func testAppShellModelUsesPhaseZeroStatus() {
        XCTAssertEqual(AppShellModel().statusText, "Onboarding configuration router")
    }

    @MainActor
    func testOnboardingShowsWelcomeWhenNoRepoPathIsConfigured() async {
        let loader = ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo")))
        let model = makeShellOnboardingModel(configLoader: loader)

        await model.bootstrapIfNeeded()

        XCTAssertEqual(model.route, .welcome)
        await loader.assertRequestedPaths([])
    }

    @MainActor
    func testWelcomeContinueShowsChoosePathStep() {
        let model = makeShellOnboardingModel()

        model.continueFromWelcome()

        XCTAssertEqual(model.route, .choosePath)
    }

    @MainActor
    func testChoosePathRejectsEmptyPathBeforeCallingCore() async {
        let validator = ShellRecordingPathValidator(result: .success(.shellFixture(repoPath: "/tmp/repo")))
        let model = makeShellOnboardingModel(pathValidator: validator)

        model.updateRepositoryPath("  ")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "请输入资料库路径")
        XCTAssertFalse(model.canContinueFromChoosePath)
        await validator.assertNoRequests()
    }

    @MainActor
    func testChoosePathRejectsAreaMatrixInternalPathBeforeCallingCore() async {
        let validator = ShellRecordingPathValidator(result: .success(.shellFixture(repoPath: "/tmp/repo")))
        let model = makeShellOnboardingModel(pathValidator: validator)

        model.updateRepositoryPath("/tmp/repo/.areamatrix")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "请选择资料库根目录，而不是 .areamatrix 内部目录")
        XCTAssertFalse(model.canContinueFromChoosePath)
        await validator.assertNoRequests()
    }

    @MainActor
    func testChoosePathValidatesCandidateThroughCoreBoundary() async {
        let expandedPath = ("~/AreaMatrix/" as NSString).expandingTildeInPath
        let validation = RepoPathValidationSnapshot.shellFixture(repoPath: expandedPath)
        let validator = ShellRecordingPathValidator(result: .success(validation))
        let model = makeShellOnboardingModel(pathValidator: validator)

        await model.continueFromChoosePath()

        await validator.assertRequestedRepoPaths([expandedPath])
        XCTAssertNil(model.repositoryPathError)
        XCTAssertEqual(model.repositoryPathValidation, validation)
        XCTAssertEqual(model.choosePathAction, .continueRequested(validation))
    }

    @MainActor
    func testChoosePathMapsCoreValidationFailure() async {
        let validator = ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let model = makeShellOnboardingModel(pathValidator: validator)

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "无访问权限")
        XCTAssertNil(model.choosePathAction)
    }

    @MainActor
    func testOnboardingLoadsConfiguredRepoThroughCoreBridgeBoundary() async {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        let opener = ShellRecordingRepositoryOpener(result: .success(opening))
        let model = makeShellOnboardingModel(repoPath: "/tmp/repo", emptyRepositoryOpener: opener)

        await model.bootstrapIfNeeded()

        XCTAssertEqual(model.route, .mainEmpty(opening))
        await opener.assertRequestedConfiguredRepoPaths(["/tmp/repo"])
    }

    @MainActor
    func testOnboardingMapsConfigLoadFailureWithoutShowingWelcomeAsSuccess() async {
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreBridgeError.generatedBindingsUnavailable(
            boundary: .loadConfig,
            state: .generatedBindingsUnavailable
        )))
        let model = makeShellOnboardingModel(repoPath: "/tmp/repo", emptyRepositoryOpener: opener)

        await model.bootstrapIfNeeded()

        guard let route = requireMainRepoErrorRoute(model, message: "expected main repo error") else { return }

        XCTAssertEqual(route.repoPath, "/tmp/repo")
        XCTAssertEqual(route.mapping?.kind, .internal)
        XCTAssertTrue(route.mapping?.rawContext.contains("load_config") == true)
        await opener.assertRequestedConfiguredRepoPaths(["/tmp/repo"])
    }

    @MainActor
    func testMainRepoErrorRetryValidatesInitializedPathBeforeOpeningRepository() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let initializedValidator = ShellRecordingInitializedPathValidator(result: .success(validation))
        let opener = ShellRecordingRepositoryOpener(result: .success(opening))
        let writer = ShellRecordingSettingsWriter()
        let model = makeShellOnboardingModel(
            settingsWriter: writer,
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener
        )

        await model.retryMainRepositoryFromError(repoPath: "/tmp/repo")

        await initializedValidator.assertRequestedRepoPaths(["/tmp/repo"])
        await opener.assertRequestedConfiguredRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.mainRepoRecoveryValidation, validation)
        XCTAssertNil(model.mainRepoRecoveryErrorMapping)
        XCTAssertFalse(model.isRetryingMainRepository)
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.successfulRepoOpens.map(\.repoPath), ["/tmp/repo"])
        XCTAssertNotNil(model.mainRepoLastOpenedAt)
        XCTAssertEqual(model.route, .mainList(opening))
    }

    @MainActor
    func testMainRepoErrorRetryMapsInitializedValidationFailureWithoutOpeningRepository() async {
        let initializedValidator = ShellRecordingInitializedPathValidator(
            result: .failure(CoreError.RepoNotInitialized(path: "/tmp/repo"))
        )
        let opener = ShellRecordingRepositoryOpener(result: .success(.shellFixture(
            repoPath: "/tmp/repo",
            fileCount: 1
        )))
        let model = makeShellOnboardingModel(
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener
        )

        await model.retryMainRepositoryFromError(repoPath: "/tmp/repo")

        guard let route = requireMainRepoErrorRoute(model, message: "expected main repo error") else { return }

        await initializedValidator.assertRequestedRepoPaths(["/tmp/repo"])
        await opener.assertNoConfiguredRepoPaths()
        XCTAssertEqual(route.repoPath, "/tmp/repo")
        XCTAssertEqual(route.mapping?.kind, .repoNotInitialized)
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping?.kind, .repoNotInitialized)
        XCTAssertNil(model.mainRepoRecoveryValidation)
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    func testConfigLoadFailureMapsCoreErrors() {
        let config = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.Config(reason: "configuration error")
        )
        let permission = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.PermissionDenied(path: "/tmp/repo/.areamatrix/index.db")
        )
        let io = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.Io(message: "io error")
        )
        let db = ConfigLoadFailure.map(
            repoPath: "/tmp/repo",
            error: CoreError.Db(message: "database error")
        )

        XCTAssertEqual(config.title, "Repository settings are invalid")
        XCTAssertEqual(permission.title, "Repository settings need permission")
        XCTAssertEqual(io.title, "Repository settings are unavailable")
        XCTAssertEqual(db.title, "Repository metadata cannot be opened")
    }
}
