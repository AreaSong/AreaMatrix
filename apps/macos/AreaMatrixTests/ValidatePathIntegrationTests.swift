import Foundation
import XCTest
@testable import AreaMatrix

final class ValidatePathRepairRegressionTests: XCTestCase {
    @MainActor
    func testInitializedRepoWithNonEmptyIssueDoesNotShowAdoptNotice() async {
        let validation = RepoPathValidationSnapshot.repairFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized, .nonEmptyDirectory],
            recommendedMode: nil
        )
        let writer = RepairRecordingSettingsWriter()
        let opening = RepositoryOpeningResult.repairFixture(repoPath: "/tmp/repo", fileCount: 1)
        let opener = RepairRecordingRepositoryOpener(result: .success(opening))
        let model = makeModel(validation: validation, writer: writer, opener: opener)

        XCTAssertFalse(ValidatePathNoticeRules.shouldShowAdoptExistingNotice(for: validation))

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        let requestedRepoPaths = await opener.requestedRepoPaths()

        XCTAssertEqual(model.validatePathPrimaryActionTitle, "Open Repository")
        XCTAssertEqual(model.validatePathAction, .openExistingRepositoryRequested(validation))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainList(opening))
    }

    @MainActor
    func testSettingsOpenExistingRepositorySavesCandidateAfterSuccessfulOpen() async {
        let validation = RepoPathValidationSnapshot.repairFixture(
            repoPath: "/tmp/new-repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized, .nonEmptyDirectory],
            recommendedMode: nil
        )
        let writer = RepairRecordingSettingsWriter()
        let opening = RepositoryOpeningResult.repairFixture(repoPath: "/tmp/new-repo", fileCount: 1)
        let opener = RepairRecordingRepositoryOpener(result: .success(opening))
        let model = makeModel(
            validation: validation,
            settingsRepoPath: "/tmp/current-repo",
            writer: writer,
            opener: opener
        )

        await model.beginSettingsRepositoryPathValidation("/tmp/new-repo")
        await model.continueFromValidatePath()
        let requestedRepoPaths = await opener.requestedRepoPaths()

        XCTAssertEqual(model.validatePathAction, .openExistingRepositoryRequested(validation))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/new-repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/new-repo"])
        XCTAssertEqual(model.route, .mainList(opening))
    }

    @MainActor
    func testSettingsChangePathKeepsSourceWhenOpeningExistingRepository() async {
        let validation = RepoPathValidationSnapshot.repairFixture(
            repoPath: "/tmp/second-repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized, .nonEmptyDirectory],
            recommendedMode: nil
        )
        let writer = RepairRecordingSettingsWriter()
        let opening = RepositoryOpeningResult.repairFixture(repoPath: "/tmp/second-repo", fileCount: 1)
        let opener = RepairRecordingRepositoryOpener(result: .success(opening))
        let model = makeModel(
            validation: validation,
            settingsRepoPath: "/tmp/current-repo",
            writer: writer,
            opener: opener
        )

        await model.beginSettingsRepositoryPathValidation("/tmp/new-repo")
        model.showChoosePath()
        model.updateRepositoryPath("/tmp/second-repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        let requestedRepoPaths = await opener.requestedRepoPaths()

        XCTAssertTrue(model.validatePathReturnRouteIsSettings)
        XCTAssertEqual(model.validatePathAction, .openExistingRepositoryRequested(validation))
        XCTAssertEqual(requestedRepoPaths, ["/tmp/second-repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/second-repo"])
        XCTAssertEqual(model.route, .mainList(opening))
    }

    @MainActor
    func testSettingsQuitConfirmationReturnsToSettingsWithoutSavingCandidate() async {
        let validation = RepoPathValidationSnapshot.repairFixture(repoPath: "/tmp/new-repo")
        let writer = RepairRecordingSettingsWriter()
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
        let validation = RepoPathValidationSnapshot.repairFixture(
            repoPath: "/tmp/repo",
            availableCapacityBytes: nil
        )
        let writer = RepairRecordingSettingsWriter()
        let model = makeModel(validation: validation, writer: writer)

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "路径环境检查缺失，请重试或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
        XCTAssertNil(model.validatePathAction)
    }

    @MainActor
    func testMissingExternalVolumeResultBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.repairFixture(
            repoPath: "/tmp/repo",
            isExternalVolume: nil
        )
        let writer = RepairRecordingSettingsWriter()
        let model = makeModel(validation: validation, writer: writer)

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "路径环境检查缺失，请重试或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
        XCTAssertNil(model.validatePathAction)
    }

    @MainActor
    func testAdoptExistingConfirmCallsRepositoryInitializerAndSavesPath() async {
        let validation = RepoPathValidationSnapshot.repairFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
        let writer = RepairRecordingSettingsWriter()
        let initializer = RepairRecordingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: RepairStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RepairRecordingConfigLoader(config: .repairFixture(repoPath: "/tmp/repo")),
            pathValidator: RepairRecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: RepairStaticStartupRecoverer(),
            helpOpener: RepairNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()
        let createdPaths = await initializer.createdRepoPaths()
        let adoptedPaths = await initializer.adoptedRepoPaths()

        XCTAssertEqual(createdPaths, [])
        XCTAssertEqual(adoptedPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/repo",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        )))
    }

    func testConfirmInitRulesRequireMatchingSafeDraftState() {
        let createDraft = RepositoryInitializationDraft(
            validation: .repairFixture(repoPath: "/tmp/create"),
            mode: .createEmpty,
            scanSession: nil
        )
        let adoptDraft = RepositoryInitializationDraft(
            validation: .repairFixture(
                repoPath: "/tmp/adopt",
                isEmpty: false,
                issues: [.nonEmptyDirectory],
                recommendedMode: .adoptExisting
            ),
            mode: .adoptExisting,
            scanSession: nil
        )
        let staleCreateDraft = RepositoryInitializationDraft(
            validation: .repairFixture(repoPath: "/tmp/stale", isEmpty: false),
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
        let validation = RepoPathValidationSnapshot.repairFixture(repoPath: "/tmp/repo")
        let writer = RepairRecordingSettingsWriter()
        let initializer = RepairPausingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: RepairStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RepairRecordingConfigLoader(config: .repairFixture(repoPath: "/tmp/repo")),
            pathValidator: RepairRecordingPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: RepairStaticStartupRecoverer(),
            helpOpener: RepairNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
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
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        )))
    }

    @MainActor
    func testConfirmInitRevalidatesBeforeWritingAndBlocksChangedPathState() async {
        let initialValidation = RepoPathValidationSnapshot.repairFixture(repoPath: "/tmp/repo")
        let changedValidation = RepoPathValidationSnapshot.repairFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
        let validator = RepairSequencePathValidator(validations: [initialValidation, changedValidation])
        let writer = RepairRecordingSettingsWriter()
        let initializer = RepairRecordingRepositoryInitializer()
        let model = OnboardingModel(
            settingsReader: RepairStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RepairRecordingConfigLoader(config: .repairFixture(repoPath: "/tmp/repo")),
            pathValidator: validator,
            repositoryInitializer: initializer,
            startupRecoverer: RepairStaticStartupRecoverer(),
            helpOpener: RepairNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
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
        let repoURL = try makeRepairTemporaryAdoptRepoURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let readmeURL = repoURL.appendingPathComponent("README.md")
        try "# User project\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        try await CoreBridge().adoptExistingRepository(repoPath: repoURL.path)

        let areaMatrixURL = repoURL.appendingPathComponent(".areamatrix")
        XCTAssertTrue(FileManager.default.fileExists(atPath: areaMatrixURL.appendingPathComponent("index.db").path))
        XCTAssertEqual(try String(contentsOf: readmeURL, encoding: .utf8), "# User project\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("docs").path))
    }

    func testDefaultCoreCreateEmptyWritesRecoverableMetadataOnly() async throws {
        let repoURL = try makeRepairTemporaryAdoptRepoURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)

        let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
        let expectedMetadataPaths = [
            "index.db", "classifier.yaml", "ignore.yaml", "staging",
            "archives", "generated", "generated/root.md",
        ]

        for relativePath in expectedMetadataPaths {
            let path = metadataURL.appendingPathComponent(relativePath).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "missing \(relativePath)")
        }

        do {
            try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)
            XCTFail("expected repeat initialization to fail")
        } catch let error as CoreError {
            guard case .Config = error else {
                return XCTFail("expected Config, got \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.appendingPathComponent("index.db").path))
    }

    @MainActor
    private func makeModel(
        validation: RepoPathValidationSnapshot,
        settingsRepoPath: String? = nil,
        writer: RepairRecordingSettingsWriter,
        opener: (any CoreEmptyRepositoryOpening)? = nil
    ) -> OnboardingModel {
        let repositoryOpener: any CoreEmptyRepositoryOpening = opener ??
            RepairRecordingRepositoryOpener(result: .success(.repairFixture(repoPath: validation.repoPath, fileCount: 1)))
        return OnboardingModel(
            settingsReader: RepairStaticSettingsReader(repoPath: settingsRepoPath),
            settingsWriter: writer,
            configLoader: RepairRecordingConfigLoader(config: .repairFixture(repoPath: settingsRepoPath ?? "/tmp/repo")),
            pathValidator: RepairRecordingPathValidator(validation: validation),
            emptyRepositoryOpener: repositoryOpener,
            startupRecoverer: RepairStaticStartupRecoverer(),
            existingRepositoryMetadataReader: RepairStaticExistingRepositoryMetadataReader(schemaVersion: 1),
            helpOpener: RepairNoopWelcomeHelpOpener()
        )
    }
}
