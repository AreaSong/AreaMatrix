@testable import AreaMatrix
import XCTest

final class RepositorySettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesRepositoryConfigCoreConfigForVisibleRepositorySettings() async {
        var config = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/AreaMatrixRepo")
        config.overviewOutput = "RootAreaMatrixFile"
        let loader = RecordingConfigurationLoader(results: [.success(config)])
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(.testFixture(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: "/tmp/AreaMatrixRepo"
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/AreaMatrixRepo"))
        )
        let model = RepositorySettingsModel(
            repoPath: "/tmp/AreaMatrixRepo",
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()

        await loader.assertRequestedPaths(["/tmp/AreaMatrixRepo"])
        await updater.assertNoConfigurationUpdateRequests()
        XCTAssertEqual(model.loadedConfig, config)
        XCTAssertEqual(model.summary?.repositoryName, "AreaMatrixRepo")
        XCTAssertEqual(model.summary?.location, "/tmp/AreaMatrixRepo")
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ missing")
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
        let loader = RecordingConfigurationLoader(results: [.success(first), .success(second)])
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(.testFixture(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: "/tmp/repo"
            )),
            .success(.testFixture(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: "/tmp/repo"
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo"))
        )
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()
        XCTAssertEqual(model.summary?.overviewMode, "Generated only")

        await model.load()

        await loader.assertRequestedPaths(["/tmp/repo", "/tmp/repo"])
        await updater.assertNoConfigurationUpdateRequests()
        XCTAssertEqual(model.summary?.overviewMode, "Root AREAMATRIX.md enabled")
    }

    @MainActor
    func testLoadFailureUsesCoreErrorMapping() async {
        let loader = RecordingConfigurationLoader(results: [
            .failure(CoreError.Config(reason: "invalid repo_config"))
        ])
        let mapper = RecordingCoreErrorMapper.repositorySettings()
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: RecordingConfigurationUpdater(result: .success(())),
            errorMapper: mapper
        )

        await model.load()

        await mapper.assertMappedCoreErrors([CoreError.Config(reason: "invalid repo_config")])
        XCTAssertEqual(model.loadError?.message, "配置错误")
        XCTAssertEqual(model.loadError?.recovery, "Retry status")
        XCTAssertNil(model.loadedConfig)
    }

    @MainActor
    func testLoadSynchronizesStaleRepoPathThroughUpdateConfig() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let metadataPresenceChecker = RecordingRepoMetadataPresenceChecker(
            presence: RepoMetadataPresence(
                hasMetadataDirectory: true,
                hasMetadataDatabase: true
            )
        )

        var config = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/stale-repo")
        config.overviewOutput = "RootAreaMatrixFile"
        var expected = config
        expected.repoPath = repoURL.path
        let loader = RecordingConfigurationLoader(results: [.success(config)])
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(.testFixture(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: repoURL.path
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.importSingleFileFixture(repoPath: repoURL.path))
        )
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            metadataPresenceChecker: metadataPresenceChecker,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()

        await updater.assertConfigurationUpdateRequests([RecordingConfigurationUpdater.Request(
            repoPath: repoURL.path,
            config: expected
        )])
        metadataPresenceChecker.assertRepoPaths([repoURL.path])
        XCTAssertEqual(model.loadedConfig, expected)
        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.summary?.repositoryName, repoURL.lastPathComponent)
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.summary?.rootFile, "AREAMATRIX.md")
        XCTAssertNil(model.syncError)
    }

    @MainActor
    func testUpdateConfigFailureKeepsVisibleSettingsAndMapsSyncError() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try createRepositorySettingsMetadataDatabaseMarker(in: repoURL)

        let loader = RecordingConfigurationLoader(results: [
            .success(.shellFixture(repoPath: "/tmp/stale-repo"))
        ])
        let updater = RecordingConfigurationUpdater(result: .failure(CoreError.Db(message: "locked")))
        let mapper = RecordingCoreErrorMapper.repositorySettings()
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(.testFixture(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: repoURL.path
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.importSingleFileFixture(repoPath: repoURL.path))
        )
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            errorMapper: mapper
        )

        await model.load()

        await updater.assertRequestCount(1)
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "locked")])
        XCTAssertEqual(model.loadedConfig?.repoPath, repoURL.path)
        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.syncError?.message, "数据库错误")
        XCTAssertEqual(model.syncError?.recovery, "Retry status")
    }

    @MainActor
    func testDefaultCoreBridgeLoadsRealConfigWithoutCreatingManagedRootFiles() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
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
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.healthSummary?.databaseStatus, .ok)
        XCTAssertEqual(model.healthSummary?.schemaVersion, 2)
        XCTAssertEqual(model.healthSummary?.filesIndexed, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path
        ))
    }

    @MainActor
    func testDefaultCoreBridgeRevealsGeneratedOverviewFromGeneratedRootPath() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let generatedURL = repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("root.md", isDirectory: false)
        let revealer = RecordingRepositoryFileRevealer()
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            repositoryOpener: bridge,
            scanSessionReader: bridge,
            existingRepositoryMetadataReader: SQLiteExistingRepositoryMetadataReader(),
            generatedOverviewRevealer: revealer,
            errorMapper: bridge
        )

        await model.load()
        model.revealGeneratedOverviewInFinder()

        XCTAssertTrue(FileManager.default.fileExists(atPath: generatedURL.path))
        revealer.assertRevealRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: repoURL.path,
            relativePath: RepositorySettingsSummary.generatedOverviewRelativePath
        )])
        XCTAssertNil(model.overviewActionError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path
        ))
    }

    @MainActor
    func testRevealGeneratedOverviewFailureShowsRecoverableError() {
        let revealer = RecordingRepositoryFileRevealer(
            result: .failure(RepositoryFileActionError.fileMissing(
                RepositorySettingsSummary.generatedOverviewRelativePath
            ))
        )
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: RecordingConfigurationLoader(results: []),
            updater: RecordingConfigurationUpdater(result: .success(())),
            generatedOverviewRevealer: revealer,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        model.revealGeneratedOverviewInFinder()

        revealer.assertRevealRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: "/tmp/repo",
            relativePath: RepositorySettingsSummary.generatedOverviewRelativePath
        )])
        XCTAssertEqual(model.overviewActionError?.message, "Generated overview cannot be shown in Finder.")
        XCTAssertEqual(
            model.overviewActionError?.recovery,
            "Retry after AreaMatrix regenerates .areamatrix/generated/root.md."
        )
    }
}
