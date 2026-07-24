@testable import AreaMatrix
import XCTest

final class RepositorySettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesRepositoryConfigCoreConfigForVisibleRepositorySettings() async {
        var config = AppRepoConfigSnapshot.shellFixture(repoPath: "/tmp/AreaMatrixRepo")
        config.overviewOutput = "RootAreaMatrixFile"
        let loader = RecordingConfigurationLoader(results: [.success(config)])
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
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()

        await loader.assertRequestedPaths(["/tmp/AreaMatrixRepo"])
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
        var first = AppRepoConfigSnapshot.shellFixture(repoPath: "/tmp/repo")
        first.overviewOutput = "GeneratedOnly"
        var second = AppRepoConfigSnapshot.shellFixture(repoPath: "/tmp/repo")
        second.overviewOutput = "RootAreaMatrixFile"
        let loader = RecordingConfigurationLoader(results: [.success(first), .success(second)])
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
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()
        XCTAssertEqual(model.summary?.overviewMode, "Generated only")

        await model.load()

        await loader.assertRequestedPaths(["/tmp/repo", "/tmp/repo"])
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
            errorMapper: mapper
        )

        await model.load()

        await mapper.assertMappedCoreErrors([CoreError.Config(reason: "invalid repo_config")])
        XCTAssertEqual(
            model.loadError?.message,
            L10n.message("error.unmapped.message", fallback: "配置错误", technicalDetail: "配置错误")
        )
        XCTAssertEqual(
            model.loadError?.recovery,
            L10n.message("error.unmapped.action", fallback: "Retry status", technicalDetail: "Retry status")
        )
        XCTAssertNil(model.loadedConfig)
    }

    @MainActor
    func testLoadUsesCurrentConnectionPathWithoutWritingRepositoryConfig() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let metadataPresenceChecker = RecordingRepoMetadataPresenceChecker(
            presence: RepoMetadataPresence(
                hasMetadataDirectory: true,
                hasMetadataDatabase: true
            )
        )

        var config = AppRepoConfigSnapshot.shellFixture(repoPath: "/tmp/stale-repo")
        config.overviewOutput = "RootAreaMatrixFile"
        var expected = config
        expected.repoPath = repoURL.path
        let loader = RecordingConfigurationLoader(results: [.success(config)])
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
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            metadataPresenceChecker: metadataPresenceChecker,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()

        metadataPresenceChecker.assertRepoPaths([repoURL.path])
        XCTAssertEqual(model.loadedConfig, expected)
        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.summary?.repositoryName, repoURL.lastPathComponent)
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.summary?.rootFile, "AREAMATRIX.md")
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
            errorMapper: bridge
        )

        await model.load()

        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.summary?.overviewMode, "Generated only")
        XCTAssertEqual(model.summary?.rootFile, "Off")
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.healthSummary?.databaseStatus, .ok)
        XCTAssertEqual(model.healthSummary?.schemaVersion, 3)
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
            generatedOverviewRevealer: revealer,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        model.revealGeneratedOverviewInFinder()

        revealer.assertRevealRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: "/tmp/repo",
            relativePath: RepositorySettingsSummary.generatedOverviewRelativePath
        )])
        XCTAssertEqual(
            model.overviewActionError?.message,
            L10n.message("Generated overview cannot be shown in Finder.")
        )
        XCTAssertEqual(
            model.overviewActionError?.recovery,
            L10n.message("Retry after AreaMatrix regenerates .areamatrix/generated/root.md.")
        )
    }
}
