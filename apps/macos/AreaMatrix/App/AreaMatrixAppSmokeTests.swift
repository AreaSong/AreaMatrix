@testable import AreaMatrix
import Foundation
import XCTest

final class AreaMatrixAppSmokeTests: XCTestCase {
    func testMainWindowShellCanBeCreated() {
        let view = MainWindow()

        XCTAssertEqual(String(describing: type(of: view)), "MainWindow")
    }
}

final class AreaMatrixAdoptExistingTests: XCTestCase {
    @MainActor
    func testCreateEmptyConfirmInitializesRepositoryThroughCoreBridge() async throws {
        let repoURL = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let validation = RepoPathValidationSnapshot.smokeFixture(repoPath: repoURL.path)
        let writer = SmokeRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath(repoURL.path)
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        await model.createEmptyRepositoryFromConfirmInit()

        let indexDatabasePath = repoURL.appendingPathComponent(".areamatrix/index.db").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexDatabasePath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        await writer.assertSavedRepoPaths([repoURL.path])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: repoURL.path,
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        )))
    }

    @MainActor
    func testAdoptExistingContinueShowsConfirmInitializationHandoff() async {
        let validation = RepoPathValidationSnapshot.smokeAdoptExistingFixture(repoPath: "/tmp/repo")
        let scanReader = SmokeRecordingScanSessionReader(result: .success(nil))
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: nil),
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            scanSessionReader: scanReader,
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        XCTAssertTrue(model.canContinueFromValidatePath)
        await scanReader.assertRequestedRepoPaths([])
        XCTAssertEqual(model.validatePathAction, .adoptExistingRequested(validation, scanSession: nil))
        XCTAssertEqual(model.route, .confirmRepositoryInitialization(RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: nil
        )))
    }

    @MainActor
    func testOpenExistingRepositorySavesSelectionAndOpensMainList() async {
        let validation = RepoPathValidationSnapshot.smokeFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let writer = SmokeRecordingSettingsWriter()
        let opening = RepositoryOpeningResult.smokeFixture(repoPath: "/tmp/repo", fileCount: 1)
        let opener = SmokeRecordingRepositoryOpener(result: .success(opening))
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            emptyRepositoryOpener: opener,
            startupRecoverer: StaticStartupRecoverer(),
            existingRepositoryMetadataReader: SmokeExistingRepoMetadataReader(schemaVersion: 1),
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()

        XCTAssertEqual(model.existingRepositoryMetadata?.schemaVersion, 1)
        await opener.assertRequestedRepoPaths(["/tmp/repo"])
        await writer.assertSavedRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.route, .mainList(opening))
    }

    func testDefaultCoreValidationDetectsTemporaryNonEmptyDirectoryAsAdoptExisting() async throws {
        let repoURL = try makeTemporaryRepositoryURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }

        let readmeURL = repoURL.appendingPathComponent("README.md")
        try "# User project\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        let validation = try await CoreBridge().validateRepoPath(repoPath: repoURL.path)

        XCTAssertEqual(validation.repoPath, repoURL.path)
        XCTAssertEqual(validation.recommendedMode, .adoptExisting)
        XCTAssertTrue(validation.issues.contains(.nonEmptyDirectory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
        XCTAssertEqual(try String(contentsOf: readmeURL, encoding: .utf8), "# User project\n")
    }

    @MainActor
    func testUnfinishedAdoptScanLoadsLatestSessionAndBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.smokeFixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            hasUnfinishedScanSession: true,
            issues: [.unfinishedScanSession],
            recommendedMode: nil
        )
        let scanSession = ScanSessionSnapshot.adoptFixture()
        let scanReader = SmokeRecordingScanSessionReader(result: .success(scanSession))
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: nil),
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            scanSessionReader: scanReader,
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        await scanReader.assertRequestedRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.latestScanSession, scanSession)
        XCTAssertEqual(
            model.route,
            .dbRepairConfirm(DatabaseRepairRouteState(
                repoPath: "/tmp/repo",
                scanSession: scanSession,
                mapping: nil,
                returnRoute: .validatePath
            ))
        )
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    @MainActor
    func testCancelRepairFromValidatePathReturnsToSourceValidationPage() async {
        let validation = RepoPathValidationSnapshot.smokeFixture(
            repoPath: "/tmp/repo",
            hasUnfinishedScanSession: true,
            issues: [.unfinishedScanSession],
            recommendedMode: nil
        )
        let scanSession = ScanSessionSnapshot.adoptFixture()
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: nil),
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            scanSessionReader: SmokeRecordingScanSessionReader(result: .success(scanSession)),
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )
        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        guard case let .dbRepairConfirm(repairRoute) = model.route else {
            return XCTFail("expected db repair route")
        }

        model.returnFromDatabaseRepair(repairRoute)

        XCTAssertEqual(model.route, .validatePath)
        XCTAssertEqual(model.repositoryPathValidation, validation)
        XCTAssertEqual(model.latestScanSession, scanSession)
    }

    @MainActor
    func testScanSessionFailurePreservesPathValidationAndBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.smokeFixture(
            repoPath: "/tmp/repo",
            hasUnfinishedScanSession: true,
            issues: [.unfinishedScanSession],
            recommendedMode: nil
        )
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: nil),
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            scanSessionReader: SmokeRecordingScanSessionReader(
                result: .failure(AppSemanticError.database(rawContext: "db"))
            ),
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathValidation, validation)
        XCTAssertNil(model.latestScanSession)
        XCTAssertEqual(model.repositoryPathError, "数据库错误")
        guard case let .dbRepairConfirm(repairRoute) = model.route, repairRoute.repoPath == "/tmp/repo",
              repairRoute.scanSession == nil
        else {
            return XCTFail("expected db repair route, got \(model.route)")
        }
        XCTAssertEqual(repairRoute.mapping?.kind, .db)
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    @MainActor
    func testSettingsOriginBackReturnsRepositorySettingsWithoutSavingNewPath() async {
        let validation = RepoPathValidationSnapshot.smokeFixture(repoPath: "/tmp/new-repo")
        let writer = SmokeRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: "/tmp/current-repo"),
            settingsWriter: writer,
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/current-repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        await model.beginSettingsRepositoryPathValidation("/tmp/new-repo")

        XCTAssertEqual(model.route, .validatePath)
        XCTAssertTrue(model.validatePathReturnRouteIsSettings)

        model.returnFromValidatePath()

        XCTAssertEqual(model.route, .settingsRepository)
        await writer.assertNoSavedRepoPaths()
    }

    @MainActor
    func testValidatePathQuitConfirmationDoesNotSaveCandidateRepository() async {
        let validation = RepoPathValidationSnapshot.smokeFixture(repoPath: "/tmp/repo")
        let writer = SmokeRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: SmokeStaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: SmokeRecordingConfigLoader(result: .success(.smokeFixture(repoPath: "/tmp/repo"))),
            pathValidator: SmokeRecordingPathValidator(result: .success(validation)),
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.requestSetupQuit()

        XCTAssertTrue(model.isSetupQuitConfirmationPresented)

        model.confirmSetupQuit()

        XCTAssertEqual(model.route, .welcome)
        XCTAssertNil(model.repositoryPathValidation)
        await writer.assertNoSavedRepoPaths()
    }
}

private func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixAdoptExistingTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
