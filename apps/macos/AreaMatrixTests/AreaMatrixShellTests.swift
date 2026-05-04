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
        let loader = RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
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
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(.fixture(repoPath: "/tmp/repo"))),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.continueFromWelcome()

        XCTAssertEqual(model.route, .choosePath)
    }

    @MainActor
    func testChoosePathRejectsEmptyPathBeforeCallingCore() async {
        let validator = RecordingPathValidator(result: .success(.fixture(repoPath: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
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
        let validator = RecordingPathValidator(result: .success(.fixture(repoPath: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
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
        let validation = RepoPathValidationSnapshot.fixture(repoPath: expandedPath)
        let validator = RecordingPathValidator(result: .success(validation))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
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
        let validator = RecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
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
        let opening = RepositoryOpeningResult.fixture(repoPath: "/tmp/repo", fileCount: 0)
        let opener = RecordingRepositoryOpener(result: .success(opening))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.bootstrapIfNeeded()
        let requestedRepoPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
    }

    @MainActor
    func testOnboardingMapsConfigLoadFailureWithoutShowingWelcomeAsSuccess() async {
        let opener = RecordingRepositoryOpener(result: .failure(CoreBridgeError.generatedBindingsUnavailable(
            boundary: .loadConfig,
            state: .phase0
        )))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: "/tmp/repo"),
            emptyRepositoryOpener: opener,
            helpOpener: NoopWelcomeHelpOpener()
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
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            helpOpener: FailingWelcomeHelpOpener()
        )

        model.openLearnMore()

        XCTAssertEqual(model.toastMessage, "Learn more is unavailable right now.")
        XCTAssertEqual(model.route, .loadingConfiguration)
    }

    @MainActor
    func testChoosePathContinueShowsValidatePathAndStoresCoreResult() async {
        let validation = RepoPathValidationSnapshot.fixture(repoPath: "/tmp/repo")
        let validator = RecordingPathValidator(result: .success(validation))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: validator,
            helpOpener: NoopWelcomeHelpOpener()
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
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
            helpOpener: NoopWelcomeHelpOpener()
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
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/Users/me/Library/Mobile Documents/repo",
            isICloudPath: true,
            issues: [.iCloudPath]
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: UserDefaultsAppSettingsReader(repoPathKey: "AreaMatrix.testRepoPath"),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath(validation.repoPath)
        await model.continueFromChoosePath()

        XCTAssertFalse(model.canContinueFromValidatePath)

        model.updateICloudRiskAccepted(true)

        XCTAssertTrue(model.canContinueFromValidatePath)
    }

    @MainActor
    func testNonWritableValidationBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isWritable: false,
            issues: [.notWritable],
            recommendedMode: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "AreaMatrix 没有写入该位置的权限")
        XCTAssertFalse(model.canContinueFromValidatePath)
        XCTAssertNil(model.choosePathAction)
    }

    @MainActor
    func testInitializedRepoUsesOpenRepositoryPrimaryAction() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            existingRepositoryMetadataReader: StaticExistingRepositoryMetadataReader(schemaVersion: 1),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()

        XCTAssertEqual(model.existingRepositoryMetadata?.schemaVersion, 1)
        XCTAssertEqual(model.validatePathPrimaryActionTitle, "Open Repository")
        XCTAssertEqual(
            model.validatePathAction,
            OnboardingModel.ValidatePathAction.openExistingRepositoryRequested(validation)
        )
        XCTAssertEqual(model.route, .mainLoading("/tmp/repo"))
    }
}

private struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private enum RecordingResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private enum RecordingRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

private actor RecordingConfigLoader: CoreConfigurationLoading {
    private let result: RecordingResult
    private var paths: [String] = []
    init(result: RecordingResult) {
        self.result = result
    }
    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }
    func requestedRepoPaths() -> [String] { paths }
}

private actor RecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: RecordingRepositoryOpenResult
    private var configuredPaths: [String] = []

    init(result: RecordingRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        switch result {
        case .success(let opening):
            return opening
        case .failure(let error):
            throw error
        }
    }

    func requestedConfiguredRepoPaths() -> [String] { configuredPaths }
}

private enum RecordingPathValidationResult {
    case success(RepoPathValidationSnapshot)
    case failure(Error)
}

private actor RecordingPathValidator: CoreRepositoryPathValidating {
    private let result: RecordingPathValidationResult
    private var paths: [String] = []
    init(result: RecordingPathValidationResult) {
        self.result = result
    }
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let validation):
            return validation
        case .failure(let error):
            throw error
        }
    }
    func requestedRepoPaths() -> [String] { paths }
}

private struct NoopWelcomeHelpOpener: WelcomeHelpOpening { func openWelcomeHelp() throws {} }
private struct FailingWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        throw WelcomeHelpError.helpDocumentUnavailable
    }
}

private struct StaticExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

private extension RepoConfigSnapshot {
    static func fixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "zh-Hans",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private extension RepositoryOpeningResult {
    static func fixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .fixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            )
        )
    }
}

private extension RepoPathValidationSnapshot {
    static func fixture(
        repoPath: String,
        exists: Bool = true,
        isDirectory: Bool = true,
        isReadable: Bool = true,
        isWritable: Bool = true,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        isICloudPath: Bool = false,
        hasUnfinishedScanSession: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: exists,
            isDirectory: isDirectory,
            isReadable: isReadable,
            isWritable: isWritable,
            isEmpty: isEmpty,
            isInitialized: isInitialized,
            isInsideAreaMatrix: false,
            isICloudPath: isICloudPath,
            hasUnfinishedScanSession: hasUnfinishedScanSession,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}
