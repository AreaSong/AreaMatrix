import XCTest
@testable import AreaMatrix

final class RepositorySettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesC104ConfigForVisibleRepositorySettings() async {
        var config = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/AreaMatrixRepo")
        config.overviewOutput = "RootAreaMatrixFile"
        let loader = RepositorySettingsRecordingLoader(results: [.success(config)])
        let updater = RepositorySettingsRecordingUpdater(result: .success)
        let model = RepositorySettingsModel(
            repoPath: "/tmp/AreaMatrixRepo",
            loader: loader,
            updater: updater,
            errorMapper: RepositorySettingsStaticErrorMapper()
        )

        await model.load()

        let paths = await loader.requestedPaths()
        let updateRequests = await updater.requests()
        XCTAssertEqual(paths, ["/tmp/AreaMatrixRepo"])
        XCTAssertEqual(updateRequests, [])
        XCTAssertEqual(model.loadedConfig, config)
        XCTAssertEqual(model.summary?.repositoryName, "AreaMatrixRepo")
        XCTAssertEqual(model.summary?.location, "/tmp/AreaMatrixRepo")
        XCTAssertEqual(model.summary?.overviewMode, "Root AREAMATRIX.md enabled")
        XCTAssertEqual(model.summary?.generatedPath, ".areamatrix/generated/root.md")
        XCTAssertEqual(model.summary?.rootFile, "AREAMATRIX.md")
        XCTAssertEqual(model.summary?.readmePolicy, "User file, never managed by AreaMatrix")
    }

    @MainActor
    func testRetryStatusReloadsThroughLoadConfigOnly() async {
        var first = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/repo")
        first.overviewOutput = "GeneratedOnly"
        var second = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/repo")
        second.overviewOutput = "RootAreaMatrixFile"
        let loader = RepositorySettingsRecordingLoader(results: [.success(first), .success(second)])
        let updater = RepositorySettingsRecordingUpdater(result: .success)
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: updater,
            errorMapper: RepositorySettingsStaticErrorMapper()
        )

        await model.load()
        XCTAssertEqual(model.summary?.overviewMode, "Generated only")

        await model.load()
        let paths = await loader.requestedPaths()
        let updateRequests = await updater.requests()

        XCTAssertEqual(paths, ["/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(updateRequests, [])
        XCTAssertEqual(model.summary?.overviewMode, "Root AREAMATRIX.md enabled")
    }

    @MainActor
    func testLoadFailureUsesCoreErrorMapping() async {
        let loader = RepositorySettingsRecordingLoader(results: [
            .failure(CoreError.Config(reason: "invalid repo_config")),
        ])
        let mapper = RepositorySettingsStaticErrorMapper()
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: RepositorySettingsRecordingUpdater(result: .success),
            errorMapper: mapper
        )

        await model.load()

        let mappedErrors = await mapper.mappedErrors()
        XCTAssertEqual(mappedErrors, [CoreError.Config(reason: "invalid repo_config")])
        XCTAssertEqual(model.loadError?.message, "配置错误")
        XCTAssertEqual(model.loadError?.recovery, "Retry status")
        XCTAssertNil(model.loadedConfig)
    }

    @MainActor
    func testLoadSynchronizesStaleRepoPathThroughUpdateConfig() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try createRepositorySettingsMetadataDatabaseMarker(in: repoURL)

        var config = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/stale-repo")
        config.overviewOutput = "RootAreaMatrixFile"
        var expected = config
        expected.repoPath = repoURL.path
        let loader = RepositorySettingsRecordingLoader(results: [.success(config)])
        let updater = RepositorySettingsRecordingUpdater(result: .success)
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: updater,
            errorMapper: RepositorySettingsStaticErrorMapper()
        )

        await model.load()

        let requests = await updater.requests()
        XCTAssertEqual(requests, [RepositorySettingsRecordingUpdater.Request(
            repoPath: repoURL.path,
            config: expected
        )])
        XCTAssertEqual(model.loadedConfig, expected)
        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.summary?.repositoryName, repoURL.lastPathComponent)
        XCTAssertEqual(model.summary?.rootFile, "AREAMATRIX.md")
        XCTAssertNil(model.syncError)
    }

    @MainActor
    func testUpdateConfigFailureKeepsVisibleSettingsAndMapsSyncError() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try createRepositorySettingsMetadataDatabaseMarker(in: repoURL)

        let loader = RepositorySettingsRecordingLoader(results: [
            .success(.shellFixture(repoPath: "/tmp/stale-repo")),
        ])
        let updater = RepositorySettingsRecordingUpdater(result: .failure(CoreError.Db(message: "locked")))
        let mapper = RepositorySettingsStaticErrorMapper()
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: updater,
            errorMapper: mapper
        )

        await model.load()

        let mappedErrors = await mapper.mappedErrors()
        let requests = await updater.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "locked")])
        XCTAssertEqual(model.loadedConfig?.repoPath, repoURL.path)
        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.syncError?.message, "数据库错误")
        XCTAssertEqual(model.syncError?.recovery, "Retry status")
    }

    @MainActor
    func testDefaultCoreBridgeLoadsRealConfigWithoutCreatingManagedRootFiles() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            errorMapper: bridge
        )

        await model.load()

        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.summary?.overviewMode, "Generated only")
        XCTAssertEqual(model.summary?.rootFile, "Off")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path
        ))
    }

    @MainActor
    func testDefaultCoreBridgeSynchronizesMovedRepositoryPathWithoutCreatingManagedRootFiles() async throws {
        let originalURL = try temporaryRepositorySettingsRepo()
        let movedURL = originalURL.deletingLastPathComponent()
            .appendingPathComponent("AreaMatrixRepositorySettings-Moved-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: movedURL)
        }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: originalURL.path)
        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        let staleConfig = try await bridge.loadConfig(repoPath: movedURL.path)
        XCTAssertEqual(staleConfig.repoPath, originalURL.path)

        let model = RepositorySettingsModel(
            repoPath: movedURL.path,
            loader: bridge,
            updater: bridge,
            errorMapper: bridge
        )

        await model.load()

        let reloaded = try await bridge.loadConfig(repoPath: movedURL.path)
        XCTAssertEqual(model.summary?.location, movedURL.path)
        XCTAssertEqual(model.loadedConfig?.repoPath, movedURL.path)
        XCTAssertEqual(reloaded.repoPath, movedURL.path)
        XCTAssertNil(model.syncError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: movedURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: movedURL.appendingPathComponent("AREAMATRIX.md").path
        ))
    }
}

private enum RepositorySettingsLoaderResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor RepositorySettingsRecordingLoader: CoreConfigurationLoading {
    private var results: [RepositorySettingsLoaderResult]
    private var paths: [String] = []

    init(results: [RepositorySettingsLoaderResult]) {
        self.results = results
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        let result = results.isEmpty ? .failure(CoreError.Internal(message: "missing config")) : results.removeFirst()
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func requestedPaths() -> [String] { paths }
}

private enum RepositorySettingsUpdateResult {
    case success
    case failure(Error)
}

private actor RepositorySettingsRecordingUpdater: CoreConfigurationUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private let result: RepositorySettingsUpdateResult
    private var recordedRequests: [Request] = []

    init(result: RepositorySettingsUpdateResult) {
        self.result = result
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        recordedRequests.append(Request(repoPath: repoPath, config: newConfig))
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func requests() -> [Request] { recordedRequests }
}

private actor RepositorySettingsStaticErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        let userMessage: String
        switch error {
        case .Db:
            userMessage = "数据库错误"
        default:
            userMessage = "配置错误"
        }

        return CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry status",
            recoverability: .retryable,
            rawContext: "S1-27 C1-04"
        )
    }

    func mappedErrors() -> [CoreError] { errors }
}

private func temporaryRepositorySettingsRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixRepositorySettings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func createRepositorySettingsMetadataDatabaseMarker(in repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try Data().write(to: metadataURL.appendingPathComponent("index.db"))
}
