import Foundation
import XCTest
@testable import AreaMatrix

final class InitDoneEmptyRepositoryTests: XCTestCase {
    @MainActor
    func testOpenRepositoryFromInitDoneUsesC102CoreOpenBoundary() async {
        let config = RepoConfigSnapshot.fixture(repoPath: "/tmp/empty-repo")
        let opener = RecordingEmptyRepositoryOpener(result: .success(config))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/empty-repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        ))
        await model.openInitializedRepository()

        let requestedRepoPaths = await opener.requestedRepoPaths()
        XCTAssertEqual(requestedRepoPaths, ["/tmp/empty-repo"])
        XCTAssertNil(model.initializationOpenErrorMapping)
        XCTAssertEqual(model.route, .repositoryReady(config))
    }

    @MainActor
    func testOpenRepositoryFailureReturnsToDonePageWithInlineRetryError() async {
        let error = CoreError.Config(reason: "tree json unavailable")
        let mapping = CoreErrorMappingSnapshot.configFixture(rawContext: "tree json unavailable")
        let opener = RecordingEmptyRepositoryOpener(result: .failure(error))
        let errorMapper = RecordingErrorMapper(mapping: mapping)
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/empty-repo",
            mode: .createEmpty,
            scanSession: nil,
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepository()

        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertEqual(model.initializationOpenErrorMapping, mapping)
        XCTAssertEqual(errorMapper.mappedErrors, [error])
    }

    func testDefaultCoreBridgeOpensRealEmptyRepositoryThroughLoadConfigAndTree() async throws {
        let repoURL = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let config = try await bridge.openEmptyRepository(repoPath: repoURL.path)

        XCTAssertEqual(config.repoPath, repoURL.path)
        XCTAssertEqual(config.locale, "zh-Hans")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
    }

    @MainActor
    func testOpenRepositoryFromAdoptDoneUsesC103CoreOpenBoundary() async {
        let config = RepoConfigSnapshot.fixture(repoPath: "/tmp/adopted-repo")
        let opener = RecordingEmptyRepositoryOpener(result: .success(config))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        ))
        await model.openInitializedRepository()

        let opened = await opener.requestedAdoptedRepoPaths()
        XCTAssertEqual(opened, ["/tmp/adopted-repo"])
        XCTAssertNil(model.initializationOpenErrorMapping)
        XCTAssertEqual(model.route, .repositoryReady(config))
    }

    @MainActor
    func testAdoptOpenFailureReturnsToDonePageWithInlineRetryError() async {
        let error = CoreError.Db(message: "tree unavailable")
        let mapping = CoreErrorMappingSnapshot.dbFixture(rawContext: "tree unavailable")
        let opener = RecordingEmptyRepositoryOpener(result: .failure(error))
        let errorMapper = RecordingErrorMapper(mapping: mapping)
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        await model.openInitializedRepository()

        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertEqual(model.initializationOpenErrorMapping, mapping)
        XCTAssertEqual(errorMapper.mappedErrors, [error])
    }

    @MainActor
    func testOpenInitDoneRepositoryInFinderReportsNonBlockingFailure() async {
        let finderOpener = RecordingFinderOpener(result: .failure(.openRejected("/tmp/adopted-repo")))
        let result = RepositoryInitializationResult(
            repoPath: "/tmp/adopted-repo",
            mode: .adoptExisting,
            scanSession: ScanSessionSnapshot.adoptCompletedFixture(),
            recoveryReport: nil
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            finderOpener: finderOpener,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationDone(result)
        let message = await model.openInitializedRepositoryInFinder()

        XCTAssertEqual(finderOpener.openedRepoPaths, ["/tmp/adopted-repo"])
        XCTAssertEqual(model.route, .initializationDone(result))
        XCTAssertTrue(message?.contains("无法在 Finder 中打开资料库") == true)
    }

    func testDefaultCoreBridgeOpensRealAdoptedRepositoryThroughLoadConfigAndTree() async throws {
        let repoURL = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let readmeURL = repoURL.appendingPathComponent("README.md")
        try "# User project\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.adoptExistingRepository(repoPath: repoURL.path)
        let config = try await bridge.openAdoptedRepository(repoPath: repoURL.path)

        XCTAssertEqual(config.repoPath, repoURL.path)
        XCTAssertEqual(config.locale, "zh-Hans")
        XCTAssertEqual(try String(contentsOf: readmeURL, encoding: .utf8), "# User project\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(".areamatrix").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }
}

private enum EmptyRepositoryOpenResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor RecordingEmptyRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: EmptyRepositoryOpenResult
    private var paths: [String] = []
    private var adoptedPaths: [String] = []

    init(result: EmptyRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepoConfigSnapshot {
        adoptedPaths.append(repoPath)
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] { paths }
    func requestedAdoptedRepoPaths() -> [String] { adoptedPaths }
}

private final class RecordingFinderOpener: RepositoryFinderOpening {
    private let result: Result<Void, RepositoryFinderOpenError>
    private(set) var openedRepoPaths: [String] = []

    init(result: Result<Void, RepositoryFinderOpenError>) {
        self.result = result
    }

    @MainActor
    func openRepositoryInFinder(repoPath: String) throws {
        openedRepoPaths.append(repoPath)
        try result.get()
    }
}

private struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? { repoPath }
}

private struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
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

private extension CoreErrorMappingSnapshot {
    static func configFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库配置不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }

    static func dbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "资料库树不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

private extension ScanSessionSnapshot {
    static func adoptCompletedFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: .completed,
            lastPath: "README.md",
            inserted: 1,
            updated: 0,
            skipped: 0,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_001,
            finishedAt: 1_700_000_001,
            errors: []
        )
    }
}

private func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixInitDoneTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
