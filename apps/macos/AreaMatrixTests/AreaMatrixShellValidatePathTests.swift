@testable import AreaMatrix
import XCTest

final class AreaMatrixShellValidatePathTests: XCTestCase {
    @MainActor
    func testWelcomeLearnMoreFailureIsNonBlockingToast() {
        let model = makeShellOnboardingModel(helpOpener: ShellFailingWelcomeHelpOpener())

        model.openLearnMore()

        XCTAssertEqual(model.toastMessage, "Learn more is unavailable right now.")
        XCTAssertEqual(model.route, .loadingConfiguration)
    }

    @MainActor
    func testChoosePathContinueShowsValidatePathAndStoresCoreResult() async {
        let validation = RepoPathValidationSnapshot.shellFixture(repoPath: "/tmp/repo")
        let validator = ShellRecordingPathValidator(result: .success(validation))
        let model = makeShellOnboardingModel(pathValidator: validator)

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.route, .validatePath)
        await validator.assertRequestedRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.repositoryPathValidation, validation)
        XCTAssertTrue(model.canContinueFromValidatePath)
        XCTAssertEqual(model.choosePathAction, .continueRequested(validation))
    }

    @MainActor
    func testValidatePathKeepsPermissionFailureOnValidatePage() async {
        let model = makeShellOnboardingModel(
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
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
        let model = makeShellOnboardingModel(
            settingsWriter: UserDefaultsAppSettingsReader(repoPathKey: "AreaMatrix.testRepoPath"),
            pathValidator: ShellRecordingPathValidator(result: .success(validation))
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
        let model = makeShellOnboardingModel(pathValidator: ShellRecordingPathValidator(result: .success(validation)))

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
        let model = makeShellOnboardingModel(
            settingsWriter: writer,
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            emptyRepositoryOpener: opener,
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(schemaVersion: 1)
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        XCTAssertEqual(model.existingRepositoryMetadata?.schemaVersion, 1)
        XCTAssertEqual(model.validatePathPrimaryActionTitle, "Open Repository")
        XCTAssertEqual(
            model.validatePathAction,
            OnboardingModel.ValidatePathAction.openExistingRepositoryRequested(validation)
        )
        await opener.assertRequestedConfiguredRepoPaths(["/tmp/repo"])
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
        let model = makeShellOnboardingModel(
            settingsWriter: writer,
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            emptyRepositoryOpener: opener,
            existingRepositoryMetadataReader: ShellExistingRepoMetadataReader(schemaVersion: 1)
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        guard let route = requireMainRepoErrorRoute(model, message: "expected main repo error") else { return }

        XCTAssertEqual(route.repoPath, "/tmp/repo")
        XCTAssertEqual(route.mapping?.kind, .db)
        await opener.assertRequestedConfiguredRepoPaths(["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, [])
    }

    @MainActor
    func testMainListSystemActionsUseRepositoryRelativePath() {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let revealer = RecordingRepositoryFileRevealer()
        let opener = RecordingRepositoryFileOpener()
        let copier = ShellRecordingPathCopier()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = makeShellOnboardingModel(
            fileRevealer: revealer,
            fileOpener: opener,
            pathCopier: copier,
            accessibilityAnnouncer: announcer
        )

        model.showMainListFileInFinder(opening: opening, relativePath: "docs/a.pdf")
        model.openMainListFile(opening: opening, relativePath: "docs/a.pdf.md")
        model.copyMainListPath(opening: opening, relativePath: "docs/a.pdf")
        model.copyMainListPaths(opening: opening, relativePaths: ["docs/a.pdf", "docs/b.pdf"])

        revealer.assertRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: "/tmp/repo",
            relativePath: "docs/a.pdf"
        )])
        opener.assertRequests([RecordingRepositoryFileOpener.Request(
            repoPath: "/tmp/repo",
            relativePath: "docs/a.pdf.md"
        )])
        copier.assertRequests([ShellRecordingPathCopier.Request(repoPath: "/tmp/repo", relativePath: "docs/a.pdf")])
        copier.assertMultiPathRequests([ShellRecordingPathCopier.MultiPathRequest(
            repoPath: "/tmp/repo",
            relativePaths: ["docs/a.pdf", "docs/b.pdf"]
        )])
        XCTAssertEqual(model.toastMessage, "2 paths copied.")
        XCTAssertEqual(announcer.announcements, ["Path copied.", "2 paths copied."])
    }

    @MainActor
    func testMainRepoErrorRevealLastKnownFolderUsesFinderWithoutMutatingRepoState() {
        let finder = RecordingRepositoryFinderOpener()
        let model = makeShellOnboardingModel(finderOpener: finder)
        model.route = .mainRepoError("/tmp/repo", nil)

        model.revealMainRepositoryFolder(repoPath: "/tmp/repo")

        finder.assertRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", nil))
        XCTAssertNil(model.toastMessage)
    }
}
