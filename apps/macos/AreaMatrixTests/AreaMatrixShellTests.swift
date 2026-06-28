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
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: loader,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await loader.requestedRepoPaths()

        XCTAssertEqual(model.route, .welcome)
        XCTAssertEqual(requestedRepoPaths, [])
    }

    @MainActor
    func testWelcomeContinueShowsChoosePathStep() {
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.continueFromWelcome()

        XCTAssertEqual(model.route, .choosePath)
    }

    @MainActor
    func testChoosePathRejectsEmptyPathBeforeCallingCore() async {
        let validator = ShellRecordingPathValidator(result: .success(.shellFixture(repoPath: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: validator,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("  ")
        await model.continueFromChoosePath()
        let requestedRepoPaths = await validator.requestedRepoPaths()

        XCTAssertEqual(model.repositoryPathError, "请输入资料库路径")
        XCTAssertFalse(model.canContinueFromChoosePath)
        XCTAssertEqual(requestedRepoPaths, [])
    }

    @MainActor
    func testChoosePathRejectsAreaMatrixInternalPathBeforeCallingCore() async {
        let validator = ShellRecordingPathValidator(result: .success(.shellFixture(repoPath: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: validator,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo/.areamatrix")
        await model.continueFromChoosePath()
        let requestedRepoPaths = await validator.requestedRepoPaths()

        XCTAssertEqual(model.repositoryPathError, "请选择资料库根目录，而不是 .areamatrix 内部目录")
        XCTAssertFalse(model.canContinueFromChoosePath)
        XCTAssertEqual(requestedRepoPaths, [])
    }

    @MainActor
    func testChoosePathValidatesCandidateThroughCoreBoundary() async {
        let expandedPath = ("~/AreaMatrix/" as NSString).expandingTildeInPath
        let validation = RepoPathValidationSnapshot.shellFixture(repoPath: expandedPath)
        let validator = ShellRecordingPathValidator(result: .success(validation))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: validator,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.continueFromChoosePath()
        let requestedRepoPaths = await validator.requestedRepoPaths()

        XCTAssertEqual(requestedRepoPaths, [expandedPath])
        XCTAssertNil(model.repositoryPathError)
        XCTAssertEqual(model.repositoryPathValidation, validation)
        XCTAssertEqual(model.choosePathAction, .continueRequested(validation))
    }

    @MainActor
    func testChoosePathMapsCoreValidationFailure() async {
        let validator = ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: validator,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "无访问权限")
        XCTAssertNil(model.choosePathAction)
    }

    @MainActor
    func testOnboardingLoadsConfiguredRepoThroughCoreBridgeBoundary() async {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        let opener = ShellRecordingRepositoryOpener(result: .success(opening))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
    }

    @MainActor
    func testOnboardingMapsConfigLoadFailureWithoutShowingWelcomeAsSuccess() async {
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreBridgeError.generatedBindingsUnavailable(
            boundary: .loadConfig,
            state: .generatedBindingsUnavailable
        )))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .mainRepoError(repoPath, mapping) = model.route else {
            return XCTFail("expected main repo error")
        }

        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(mapping?.kind, .internal)
        XCTAssertTrue(mapping?.rawContext.contains("load_config") == true)
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
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
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.retryMainRepositoryFromError(repoPath: "/tmp/repo")
        let validatedPaths = await initializedValidator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(validatedPaths, ["/tmp/repo"])
        XCTAssertEqual(openedPaths, ["/tmp/repo"])
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
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.retryMainRepositoryFromError(repoPath: "/tmp/repo")
        let validatedPaths = await initializedValidator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .mainRepoError(repoPath, mapping) = model.route else {
            return XCTFail("expected main repo error, got \(model.route)")
        }

        XCTAssertEqual(validatedPaths, ["/tmp/repo"])
        XCTAssertEqual(openedPaths, [])
        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(mapping?.kind, .repoNotInitialized)
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
