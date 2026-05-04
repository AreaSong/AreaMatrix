import Foundation
import XCTest
@testable import AreaMatrix

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
        let validation = RepoPathValidationSnapshot.fixture(repoPath: repoURL.path)
        let writer = RecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath(repoURL.path)
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
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
        let validation = RepoPathValidationSnapshot.adoptExistingFixture(repoPath: "/tmp/repo")
        let scanReader = RecordingScanSessionReader(result: .success(nil))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            scanSessionReader: scanReader,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()
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
    func testOpenExistingRepositorySavesSelectionAndEntersMainLoading() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            issues: [.alreadyInitialized],
            recommendedMode: nil
        )
        let writer = RecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            existingRepositoryMetadataReader: StaticExistingRepositoryMetadataReader(schemaVersion: 1),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        model.continueFromValidatePath()

        XCTAssertEqual(model.existingRepositoryMetadata?.schemaVersion, 1)
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainLoading("/tmp/repo"))
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
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            isEmpty: false,
            isInitialized: true,
            hasUnfinishedScanSession: true,
            issues: [.unfinishedScanSession],
            recommendedMode: nil
        )
        let scanSession = ScanSessionSnapshot.adoptFixture()
        let scanReader = RecordingScanSessionReader(result: .success(scanSession))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            scanSessionReader: scanReader,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()
        let requestedScanPaths = await scanReader.requestedRepoPaths()

        XCTAssertEqual(requestedScanPaths, ["/tmp/repo"])
        XCTAssertEqual(model.latestScanSession, scanSession)
        XCTAssertEqual(model.route, .dbRepairConfirm("/tmp/repo", scanSession, nil))
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    @MainActor
    func testScanSessionFailurePreservesPathValidationAndBlocksContinue() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            hasUnfinishedScanSession: true,
            issues: [.unfinishedScanSession],
            recommendedMode: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            scanSessionReader: RecordingScanSessionReader(result: .failure(CoreError.Db(message: "db"))),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathValidation, validation)
        XCTAssertNil(model.latestScanSession)
        XCTAssertEqual(model.repositoryPathError, "数据库错误")
        guard case .dbRepairConfirm(let repoPath, nil, let mapping) = model.route, repoPath == "/tmp/repo" else {
            return XCTFail("expected db repair route, got \(model.route)")
        }
        XCTAssertEqual(mapping?.kind, .db)
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    @MainActor
    func testSettingsOriginBackReturnsRepositorySettingsWithoutSavingNewPath() async {
        let validation = RepoPathValidationSnapshot.fixture(repoPath: "/tmp/new-repo")
        let writer = RecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: "/tmp/current-repo"),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/current-repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            helpOpener: NoopWelcomeHelpOpener()
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
        let validation = RepoPathValidationSnapshot.fixture(repoPath: "/tmp/repo")
        let writer = RecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            helpOpener: NoopWelcomeHelpOpener()
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

final class ValidatePathErrorMappingTests: XCTestCase {
    @MainActor
    func testValidatePathMapsCoreFailureThroughC121ErrorMapper() async {
        let mapping = CoreErrorMappingSnapshot.permissionDeniedFixture(rawContext: "/tmp/repo")
        let errorMapper = RecordingErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.repositoryPathError, "无访问权限")
        XCTAssertEqual(model.repositoryPathErrorMapping, mapping)
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    func testCoreBridgeMapsCoreErrorThroughGeneratedBindings() async {
        let mapping = await CoreBridge().mapCoreError(CoreError.PermissionDenied(path: "/restricted/repo"))

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(mapping.userMessage, "无访问权限")
        XCTAssertEqual(mapping.severity, .high)
        XCTAssertEqual(mapping.recoverability, .userActionRequired)
        XCTAssertEqual(mapping.rawContext, "/restricted/repo")
        XCTAssertFalse(mapping.suggestedAction.isEmpty)
    }

    @MainActor
    func testConfigValidationFailureRoutesToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.configFixture(rawContext: "schema mismatch")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .failure(CoreError.Config(reason: "schema mismatch"))),
            errorMapper: RecordingErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

final class ValidatePathIntegrationTests: XCTestCase {
    @MainActor
    func testInsufficientCapacityBlocksValidatePathContinue() async {
        let validation = RepoPathValidationSnapshot.fixture(
            repoPath: "/tmp/repo",
            availableCapacityBytes: 128 * 1024 * 1024
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            configLoader: RecordingConfigLoader(result: .success(.fixture(repoPath: "/tmp/repo"))),
            pathValidator: RecordingPathValidator(result: .success(validation)),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "可用空间不足，请释放空间或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

private func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixAdoptExistingTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private enum RecordingConfigResult {
    case success(RepoConfigSnapshot)
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
    private let result: RecordingConfigResult
    init(result: RecordingConfigResult) {
        self.result = result
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        switch result {
        case .success(let config):
            return config
        }
    }
}

private enum RecordingPathValidationResult {
    case success(RepoPathValidationSnapshot)
    case failure(Error)
}

private actor RecordingPathValidator: CoreRepositoryPathValidating {
    private let result: RecordingPathValidationResult
    init(result: RecordingPathValidationResult) {
        self.result = result
    }
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        switch result {
        case .success(let validation):
            return validation
        case .failure(let error):
            throw error
        }
    }
}

private final class RecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private(set) var mappedErrors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mappedErrors.append(error)
        return mapping
    }
}

private enum RecordingScanSessionResult {
    case success(ScanSessionSnapshot?)
    case failure(Error)
}

private actor RecordingScanSessionReader: CoreScanSessionReading {
    private let result: RecordingScanSessionResult
    private var paths: [String] = []
    init(result: RecordingScanSessionResult) {
        self.result = result
    }
    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        paths.append(repoPath)
        switch result {
        case .success(let session):
            return session
        case .failure(let error):
            throw error
        }
    }
    func requestedRepoPaths() -> [String] { paths }
}

private struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
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

private extension RepoPathValidationSnapshot {
    static func adoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        fixture(
            repoPath: repoPath,
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
    }

    static func fixture(
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

private extension ScanSessionSnapshot {
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

private extension CoreErrorMappingSnapshot {
    static func permissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func configFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库 schema 不兼容",
            severity: .critical,
            suggestedAction: "请选择其他资料库，或导出诊断信息",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}
