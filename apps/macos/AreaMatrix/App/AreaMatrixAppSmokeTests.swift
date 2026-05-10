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
        XCTAssertEqual(writer.savedRepoPaths, [repoURL.path])
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
        let requestedScanPaths = await scanReader.requestedRepoPaths()

        XCTAssertTrue(model.canContinueFromValidatePath)
        XCTAssertEqual(requestedScanPaths, [])
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
            startupRecoverer: ShellStaticStartupRecoverer(),
            existingRepositoryMetadataReader: SmokeExistingRepoMetadataReader(schemaVersion: 1),
            helpOpener: SmokeNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        let requestedRepoPaths = await opener.requestedRepoPaths()

        XCTAssertEqual(model.existingRepositoryMetadata?.schemaVersion, 1)
        XCTAssertEqual(requestedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
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
        let requestedScanPaths = await scanReader.requestedRepoPaths()

        XCTAssertEqual(requestedScanPaths, ["/tmp/repo"])
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
            scanSessionReader: SmokeRecordingScanSessionReader(result: .failure(CoreError.Db(message: "db"))),
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
        XCTAssertEqual(writer.savedRepoPaths, [])
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
        XCTAssertEqual(writer.savedRepoPaths, [])
    }
}

private func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixAdoptExistingTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

enum SmokeRecordingConfigResult {
    case success(RepoConfigSnapshot)
}

struct SmokeStaticSettingsReader: AppSettingsReading {
    let repoPath: String?
    func configuredRepoPath() -> String? {
        repoPath
    }
}

final class SmokeRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []
    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }
}

actor SmokeRecordingConfigLoader: CoreConfigurationLoading {
    private let result: SmokeRecordingConfigResult
    init(result: SmokeRecordingConfigResult) {
        self.result = result
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        switch result {
        case let .success(config):
            config
        }
    }
}

enum SmokeRecordingPathValidationResult {
    case success(RepoPathValidationSnapshot)
    case failure(Error)
}

actor SmokeRecordingPathValidator: CoreRepositoryPathValidating {
    private let result: SmokeRecordingPathValidationResult
    init(result: SmokeRecordingPathValidationResult) {
        self.result = result
    }

    func validateRepoPath(repoPath _: String) async throws -> RepoPathValidationSnapshot {
        switch result {
        case let .success(validation):
            return validation
        case let .failure(error):
            throw error
        }
    }
}

enum SmokeRecordingRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

actor SmokeRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: SmokeRecordingRepositoryOpenResult
    private var paths: [String] = []

    init(result: SmokeRecordingRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        paths.append(repoPath)
        switch result {
        case let .success(opening):
            return opening
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

enum SmokeRecordingScanSessionResult {
    case success(ScanSessionSnapshot?)
    case failure(Error)
}

actor SmokeRecordingScanSessionReader: CoreScanSessionReading {
    private let result: SmokeRecordingScanSessionResult
    private var paths: [String] = []
    init(result: SmokeRecordingScanSessionResult) {
        self.result = result
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        paths.append(repoPath)
        switch result {
        case let .success(session):
            return session
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

struct SmokeNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

struct SmokeExistingRepoMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

extension RepoConfigSnapshot {
    static func smokeFixture(repoPath: String) -> RepoConfigSnapshot {
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

extension RepositoryOpeningResult {
    static func smokeFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .smokeFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
            currentCategoryFiles: []
        )
    }
}

extension RepoPathValidationSnapshot {
    static func smokeAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        smokeFixture(
            repoPath: repoPath,
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
    }

    static func smokeFixture(
        repoPath: String,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        hasUnfinishedScanSession: Bool = false,
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
            hasUnfinishedScanSession: hasUnfinishedScanSession,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}

extension ScanSessionSnapshot {
    static func adoptFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 7,
            kind: .adopt,
            status: .interrupted,
            lastPath: "docs/report.pdf",
            inserted: 12,
            updated: 1,
            skipped: 3,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_120,
            finishedAt: nil,
            errors: []
        )
    }
}
