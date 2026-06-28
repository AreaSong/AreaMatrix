@testable import AreaMatrix
import XCTest

final class AreaMatrixShellValidatePathTests: XCTestCase {
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
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
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
            startupRecoverer: StaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(schemaVersion: 1),
            helpOpener: NoopWelcomeHelpOpener()
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
        XCTAssertEqual(writer.successfulRepoOpens.map(\.repoPath), ["/tmp/repo"])
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
            startupRecoverer: StaticStartupRecoverer(),
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(schemaVersion: 1),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        let requestedRepoPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .mainRepoError(repoPath, mapping) = model.route else {
            return XCTFail("expected main repo error, got \(model.route)")
        }

        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(mapping?.kind, .db)
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, [])
    }

    @MainActor
    func testMainListSystemActionsUseRepositoryRelativePath() {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let revealer = RecordingRepositoryFileRevealer()
        let opener = RecordingRepositoryFileOpener()
        let copier = ShellRecordingPathCopier()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            fileRevealer: revealer,
            fileOpener: opener,
            pathCopier: copier,
            accessibilityAnnouncer: announcer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.showMainListFileInFinder(opening: opening, relativePath: "docs/a.pdf")
        model.openMainListFile(opening: opening, relativePath: "docs/a.pdf.md")
        model.copyMainListPath(opening: opening, relativePath: "docs/a.pdf")
        model.copyMainListPaths(opening: opening, relativePaths: ["docs/a.pdf", "docs/b.pdf"])

        XCTAssertEqual(revealer.requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(revealer.requests.map(\.relativePath), ["docs/a.pdf"])
        XCTAssertEqual(opener.requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(opener.requests.map(\.relativePath), ["docs/a.pdf.md"])
        XCTAssertEqual(copier.requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(copier.requests.map(\.relativePath), ["docs/a.pdf"])
        XCTAssertEqual(copier.multiPathRequests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(copier.multiPathRequests.map(\.relativePaths), [["docs/a.pdf", "docs/b.pdf"]])
        XCTAssertEqual(model.toastMessage, "2 paths copied.")
        XCTAssertEqual(announcer.announcements, ["Path copied.", "2 paths copied."])
    }

    @MainActor
    func testMainRepoErrorRevealLastKnownFolderUsesFinderWithoutMutatingRepoState() {
        let finder = RecordingRepositoryFinderOpener()
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            finderOpener: finder,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", nil)

        model.revealMainRepositoryFolder(repoPath: "/tmp/repo")

        XCTAssertEqual(finder.repoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", nil))
        XCTAssertNil(model.toastMessage)
    }
}
