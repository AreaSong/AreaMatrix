import XCTest
@testable import AreaMatrix

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
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            state: .phase0
        )))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await opener.requestedConfiguredRepoPaths()

        guard case .configurationError(let failure) = model.route else {
            return XCTFail("expected configuration error")
        }

        XCTAssertEqual(failure.repoPath, "/tmp/repo")
        XCTAssertTrue(failure.message.contains("load_config"))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
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

    @MainActor
    func testWelcomeLearnMoreFailureIsNonBlockingToast() {
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            helpOpener: ShellFailingWelcomeHelpOpener()
        )

        model.openLearnMore()

        XCTAssertEqual(model.toastMessage, "Learn more is unavailable right now.")
        XCTAssertEqual(model.route, .loadingConfiguration)
    }

    @MainActor
    func testChoosePathContinueShowsValidatePathAndStoresCoreResult() async {
        let validation = RepoPathValidationSnapshot.shellFixture(repoPath: "/tmp/repo")
        let validator = ShellRecordingPathValidator(result: .success(validation))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: validator,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        let requestedRepoPaths = await validator.requestedRepoPaths()

        XCTAssertEqual(model.route, .validatePath)
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.repositoryPathValidation, validation)
        XCTAssertTrue(model.canContinueFromValidatePath)
        XCTAssertEqual(model.choosePathAction, .continueRequested(validation))
    }

    @MainActor
    func testValidatePathKeepsPermissionFailureOnValidatePage() async {
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.route, .validatePath)
        XCTAssertEqual(model.repositoryPathError, "无访问权限")
        XCTAssertFalse(model.canContinueFromValidatePath)
        XCTAssertNil(model.repositoryPathValidation)
    }

    @MainActor
    func testICloudPathRequiresRiskAcknowledgement() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/Users/me/Library/Mobile Documents/repo",
            isICloudPath: true,
            issues: [.iCloudPath]
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            settingsWriter: UserDefaultsAppSettingsReader(repoPathKey: "AreaMatrix.testRepoPath"),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath(validation.repoPath)
        await model.continueFromChoosePath()

        XCTAssertFalse(model.canContinueFromValidatePath)

        model.updateICloudRiskAccepted(true)

        XCTAssertTrue(model.canContinueFromValidatePath)
    }

    @MainActor
    func testNonWritableValidationBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            isWritable: false,
            issues: [.notWritable],
            recommendedMode: nil
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "AreaMatrix 没有写入该位置的权限")
        XCTAssertFalse(model.canContinueFromValidatePath)
        XCTAssertNil(model.choosePathAction)
    }

    @MainActor
    func testInitializedRepoUsesOpenRepositoryPrimaryAction() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let opener = ShellRecordingRepositoryOpener(result: .success(opening))
        let writer = ShellRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            emptyRepositoryOpener: opener,
            existingRepositoryMetadataReader: ShellStaticExistingRepositoryMetadataReader(schemaVersion: 1),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        let requestedRepoPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(model.existingRepositoryMetadata?.schemaVersion, 1)
        XCTAssertEqual(model.validatePathPrimaryActionTitle, "Open Repository")
        XCTAssertEqual(
            model.validatePathAction,
            OnboardingModel.ValidatePathAction.openExistingRepositoryRequested(validation)
        )
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainList(opening))
    }

    @MainActor
    func testInitializedRepoOpenFailureRoutesToMainRepoErrorWithoutSavingSelection() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let opener = ShellRecordingRepositoryOpener(result: .failure(CoreError.Db(message: "open failed")))
        let writer = ShellRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            emptyRepositoryOpener: opener,
            existingRepositoryMetadataReader: ShellStaticExistingRepositoryMetadataReader(schemaVersion: 1),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        let requestedRepoPaths = await opener.requestedConfiguredRepoPaths()

        guard case .mainRepoError(let repoPath, let mapping) = model.route else {
            return XCTFail("expected main repo error, got \(model.route)")
        }

        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(mapping?.kind, .db)
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, [])
    }
}
