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

    func testCoreBridgeAdoptsTemporaryNonEmptyDirectoryWithoutTouchingUserFiles() async throws {
        let repoURL = try makeTemporaryRepositoryURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
        }

        let docsURL = repoURL.appendingPathComponent("docs", isDirectory: true)
        try FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
        let readmeURL = repoURL.appendingPathComponent("README.md")
        let specURL = docsURL.appendingPathComponent("spec.txt")
        try "# User project\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try "Spec body\n".write(to: specURL, atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        let initialValidation = try await bridge.validateRepoPath(repoPath: repoURL.path)
        let scanSession = try await bridge.adoptExistingRepo(repoPath: repoURL.path)
        let latestScanSession = try await bridge.latestScanSession(repoPath: repoURL.path)

        XCTAssertEqual(initialValidation.recommendedMode, .adoptExisting)
        XCTAssertEqual(initialValidation.issues, [.nonEmptyDirectory])
        XCTAssertEqual(scanSession?.kind, .adopt)
        XCTAssertEqual(latestScanSession?.kind, .adopt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
        XCTAssertEqual(try String(contentsOf: readmeURL, encoding: .utf8), "# User project\n")
        XCTAssertEqual(try String(contentsOf: specURL, encoding: .utf8), "Spec body\n")
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
        XCTAssertEqual(model.repositoryPathError, "该资料库存在未完成的扫描记录，请先进入修复流程")
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
        XCTAssertEqual(model.repositoryPathError, "无法读取接管扫描状态，请进入修复流程")
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
        }
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
