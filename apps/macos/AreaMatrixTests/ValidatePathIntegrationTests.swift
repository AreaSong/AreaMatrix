import Foundation
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
    func testAdoptExistingConfirmCallsRepositoryInitializerAndSavesPath() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
        let writer = RecordingSettingsWriter()
        let initializer = RecordingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/repo")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()
        let createdPaths = await initializer.createdRepoPaths()
        let adoptedPaths = await initializer.adoptedRepoPaths()

        XCTAssertEqual(createdPaths, [])
        XCTAssertEqual(adoptedPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainLoading("/tmp/repo"))
    }

    func testConfirmInitRulesRequireMatchingSafeDraftState() {
        let createDraft = RepositoryInitializationDraft(
            validation: .fixture(repoPath: "/tmp/create"),
            mode: .createEmpty,
            scanSession: nil
        )
        let adoptDraft = RepositoryInitializationDraft(
            validation: .fixture(
                repoPath: "/tmp/adopt",
                isEmpty: false,
                issues: [.nonEmptyDirectory],
                recommendedMode: .adoptExisting
            ),
            mode: .adoptExisting,
            scanSession: nil
        )
        let staleCreateDraft = RepositoryInitializationDraft(
            validation: .fixture(repoPath: "/tmp/stale", isEmpty: false),
            mode: .createEmpty,
            scanSession: nil
        )

        XCTAssertTrue(ConfirmInitStepRules.canRunPrimaryAction(for: createDraft))
        XCTAssertTrue(ConfirmInitStepRules.canRunPrimaryAction(for: adoptDraft))
        XCTAssertFalse(ConfirmInitStepRules.canRunPrimaryAction(for: staleCreateDraft))
        XCTAssertEqual(ConfirmInitStepRules.footerActions(for: createDraft), [
            .back, .cancelSetup, .changePath, .primary,
        ])
        XCTAssertEqual(ConfirmInitStepRules.footerActions(for: staleCreateDraft), [.back, .cancelSetup])
        XCTAssertEqual(
            ConfirmInitStepRules.blockingMessage(for: staleCreateDraft),
            "路径已不是空目录，请返回校验页。"
        )
    }

    @MainActor
    func testConfirmInitPrimaryActionShowsInitializingRouteBeforeCoreWriteCompletes() async {
        let validation = RepoPathValidationSnapshot.fixture(repoPath: "/tmp/repo")
        let writer = RecordingSettingsWriter()
        let initializer = PausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/repo")),
            pathValidator: RecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        let draft = RepositoryInitializationDraft(validation: validation, mode: .createEmpty, scanSession: nil)
        let initializationTask = Task {
            await model.createEmptyRepositoryFromConfirmInit()
        }

        await initializer.waitUntilStarted()

        XCTAssertEqual(model.route, .initializing(draft))

        await initializationTask.value
        let createdPaths = await initializer.createdRepoPaths()

        XCTAssertEqual(createdPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainLoading("/tmp/repo"))
    }

    @MainActor
    func testConfirmInitRevalidatesBeforeWritingAndBlocksChangedPathState() async {
        let initialValidation = RepoPathValidationSnapshot.fixture(repoPath: "/tmp/repo")
        let changedValidation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
        let validator = SequencePathValidator(validations: [initialValidation, changedValidation])
        let writer = RecordingSettingsWriter()
        let initializer = RecordingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(config: .fixture(repoPath: "/tmp/repo")),
            pathValidator: validator,
            repositoryInitializer: initializer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
        await model.createEmptyRepositoryFromConfirmInit()
        let createdPaths = await initializer.createdRepoPaths()
        let adoptedPaths = await initializer.adoptedRepoPaths()

        XCTAssertEqual(createdPaths, [])
        XCTAssertEqual(adoptedPaths, [])
        XCTAssertEqual(writer.savedRepoPaths, [])
        XCTAssertEqual(model.repositoryPathValidation, changedValidation)
        XCTAssertEqual(model.repositoryPathError, "路径状态已变化，请返回重新校验")
        XCTAssertEqual(model.route, .validatePath)
    }

    func testDefaultCoreAdoptExistingPreservesUserFiles() async throws {
        let repoURL = try makeTemporaryAdoptRepoURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let readmeURL = repoURL.appendingPathComponent("README.md")
        try "# User project\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        try await CoreBridge().adoptExistingRepository(repoPath: repoURL.path)

        let areaMatrixURL = repoURL.appendingPathComponent(".areamatrix")
        XCTAssertTrue(FileManager.default.fileExists(atPath: areaMatrixURL.appendingPathComponent("index.db").path))
        XCTAssertEqual(try String(contentsOf: readmeURL, encoding: .utf8), "# User project\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("docs").path))
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

private func makeTemporaryAdoptRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixAdoptExisting-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
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

private actor SequencePathValidator: CoreRepositoryPathValidating {
    private var validations: [RepoPathValidationSnapshot]

    init(validations: [RepoPathValidationSnapshot]) {
        self.validations = validations
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        guard !validations.isEmpty else {
            throw CoreError.Config(reason: "missing validation fixture")
        }

        return validations.removeFirst()
    }
}

private actor RecordingRepositoryInitializer: CoreRepositoryInitializing {
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
    }

    func createdRepoPaths() -> [String] { createdPaths }
    func adoptedRepoPaths() -> [String] { adoptedPaths }
}

private actor PausingRepositoryInitializer: CoreRepositoryInitializing {
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []
    private var didStart = false

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func waitUntilStarted() async {
        while !didStart {
            await Task.yield()
        }
    }

    func createdRepoPaths() -> [String] { createdPaths }
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
