import XCTest
@testable import AreaMatrix

final class ValidatePathRepairRegressionTests: XCTestCase {
    @MainActor
    func testInitializedRepoWithNonEmptyIssueDoesNotShowAdoptNotice() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized, .nonEmptyDirectory],
            recommendedMode: nil
        )
        let writer = RecordingSettingsWriter()
        let model = makeModel(validation: validation, writer: writer)

        XCTAssertFalse(ValidatePathNoticeRules.shouldShowAdoptExistingNotice(for: validation))

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()

        XCTAssertEqual(model.validatePathPrimaryActionTitle, "Open Repository")
        XCTAssertEqual(model.validatePathAction, .openExistingRepositoryRequested(validation))
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainLoading("/tmp/repo"))
    }

    @MainActor
    func testSettingsOpenExistingRepositoryDoesNotSaveCandidateBeforeMainLoading() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/new-repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized, .nonEmptyDirectory],
            recommendedMode: nil
        )
        let writer = RecordingSettingsWriter()
        let model = makeModel(
            validation: validation,
            settingsRepoPath: "/tmp/current-repo",
            writer: writer
        )

        await model.beginSettingsRepositoryPathValidation("/tmp/new-repo")
        model.continueFromValidatePath()

        XCTAssertEqual(model.validatePathAction, .openExistingRepositoryRequested(validation))
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.route, .mainLoading("/tmp/new-repo"))
    }

    @MainActor
    func testSettingsChangePathKeepsSourceWhenOpeningExistingRepository() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/second-repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized, .nonEmptyDirectory],
            recommendedMode: nil
        )
        let writer = RecordingSettingsWriter()
        let model = makeModel(
            validation: validation,
            settingsRepoPath: "/tmp/current-repo",
            writer: writer
        )

        await model.beginSettingsRepositoryPathValidation("/tmp/new-repo")
        model.showChoosePath()
        model.updateRepositoryPath("/tmp/second-repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()

        XCTAssertTrue(model.validatePathReturnRouteIsSettings)
        XCTAssertEqual(model.validatePathAction, .openExistingRepositoryRequested(validation))
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.route, .mainLoading("/tmp/second-repo"))
    }

    @MainActor
    func testSettingsQuitConfirmationReturnsToSettingsWithoutSavingCandidate() async {
        let validation = RepoPathValidationSnapshot.fixture(repoPath: "/tmp/new-repo")
        let writer = RecordingSettingsWriter()
        let model = makeModel(
            validation: validation,
            settingsRepoPath: "/tmp/current-repo",
            writer: writer
        )

        await model.beginSettingsRepositoryPathValidation("/tmp/new-repo")
        model.requestSetupQuit()
        let shouldCloseWindow = model.confirmSetupQuit()

        XCTAssertFalse(shouldCloseWindow)
        XCTAssertEqual(model.route, .settingsRepository)
        XCTAssertEqual(writer.savedRepoPaths, [])
    }

    @MainActor
    func testMissingCapacityResultBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            availableCapacityBytes: nil
        )
        let writer = RecordingSettingsWriter()
        let model = makeModel(validation: validation, writer: writer)

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "路径环境检查缺失，请重试或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
        XCTAssertNil(model.validatePathAction)
    }

    @MainActor
    func testMissingExternalVolumeResultBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isExternalVolume: nil
        )
        let writer = RecordingSettingsWriter()
        let model = makeModel(validation: validation, writer: writer)

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "路径环境检查缺失，请重试或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
        XCTAssertNil(model.validatePathAction)
    }

    @MainActor
    private func makeModel(
        validation: RepoPathValidationSnapshot,
        settingsRepoPath: String? = nil,
        writer: RecordingSettingsWriter
    ) -> OnboardingModel {
        OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: settingsRepoPath),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: settingsRepoPath ?? "/tmp/repo")),
            pathValidator: RecordingPathValidator(validation: validation),
            existingRepositoryMetadataReader: StaticExistingRepositoryMetadataReader(schemaVersion: 1),
            helpOpener: NoopWelcomeHelpOpener()
        )
    }
}

private struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private final class RecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

private actor RecordingConfigLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor RecordingPathValidator: CoreRepositoryPathValidating {
    private let validation: RepoPathValidationSnapshot

    init(validation: RepoPathValidationSnapshot) {
        self.validation = validation
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        validation
    }
}

private struct StaticExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

private struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
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

private extension RepoPathValidationSnapshot {
    static func fixture(
        repoPath: String,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: isEmpty,
            isInitialized: isInitialized,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}
