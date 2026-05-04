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
}

private enum EmptyRepositoryOpenResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor RecordingEmptyRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: EmptyRepositoryOpenResult
    private var paths: [String] = []

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

    func requestedRepoPaths() -> [String] { paths }
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
}

private func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixInitDoneTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
