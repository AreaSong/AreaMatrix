@testable import AreaMatrix
import XCTest

final class RepositorySettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesC104ConfigForVisibleRepositorySettings() async {
        var config = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/AreaMatrixRepo")
        config.overviewOutput = "RootAreaMatrixFile"
        let loader = RepositorySettingsRecordingLoader(results: [.success(config)])
        let updater = RepositorySettingsRecordingUpdater(result: .success)
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(ExistingRepositoryMetadataSnapshot(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: "/tmp/AreaMatrixRepo"
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/AreaMatrixRepo"))
        )
        let model = RepositorySettingsModel(
            repoPath: "/tmp/AreaMatrixRepo",
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
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
        let loader = RepositorySettingsRecordingLoader(results: [.success(first), .success(second)])
        let updater = RepositorySettingsRecordingUpdater(result: .success)
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(ExistingRepositoryMetadataSnapshot(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: "/tmp/repo"
            )),
            .success(ExistingRepositoryMetadataSnapshot(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: "/tmp/repo"
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo"))
        )
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
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
            .failure(CoreError.Config(reason: "invalid repo_config"))
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
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(ExistingRepositoryMetadataSnapshot(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: repoURL.path
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.s117Fixture(repoPath: repoURL.path))
        )
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
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
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.summary?.rootFile, "AREAMATRIX.md")
        XCTAssertNil(model.syncError)
    }

    @MainActor
    func testUpdateConfigFailureKeepsVisibleSettingsAndMapsSyncError() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        try createRepositorySettingsMetadataDatabaseMarker(in: repoURL)

        let loader = RepositorySettingsRecordingLoader(results: [
            .success(.shellFixture(repoPath: "/tmp/stale-repo"))
        ])
        let updater = RepositorySettingsRecordingUpdater(result: .failure(CoreError.Db(message: "locked")))
        let mapper = RepositorySettingsStaticErrorMapper()
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(ExistingRepositoryMetadataSnapshot(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: repoURL.path
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .success(RepositoryOpeningResult.s117Fixture(repoPath: repoURL.path))
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

        let mappedErrors = await mapper.mappedErrors()
        let requests = await updater.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "locked")])
        XCTAssertEqual(model.loadedConfig?.repoPath, repoURL.path)
        XCTAssertEqual(model.summary?.location, repoURL.path)
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
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
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let generatedURL = repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("root.md", isDirectory: false)
        let revealer = RepositorySettingsRecordingFileRevealer()
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
        XCTAssertEqual(revealer.requests, [RepositorySettingsRecordingFileRevealer.Request(
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
        let revealer = RepositorySettingsRecordingFileRevealer(
            result: .failure(RepositoryFileActionError.fileMissing(
                RepositorySettingsSummary.generatedOverviewRelativePath
            ))
        )
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: RepositorySettingsRecordingLoader(results: []),
            updater: RepositorySettingsRecordingUpdater(result: .success),
            generatedOverviewRevealer: revealer,
            errorMapper: RepositorySettingsStaticErrorMapper()
        )

        model.revealGeneratedOverviewInFinder()

        XCTAssertEqual(revealer.requests, [RepositorySettingsRecordingFileRevealer.Request(
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

final class RepositorySettingsHealthFeatureTests: XCTestCase {
    @MainActor
    func testMetadataReaderReadsSchemaVersionFromRealInitializedRepositoryWithoutWalSidecars() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        removeRepositorySettingsMetadataDatabaseSidecars(in: repoURL)

        do {
            let metadata = try await SQLiteExistingRepositoryMetadataReader().metadata(repoPath: repoURL.path)
            XCTAssertEqual(metadata.schemaVersion, 2)
        } catch {
            XCTFail("metadata read failed: \(error)")
        }
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
        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.healthSummary?.databaseStatus, .ok)
        XCTAssertEqual(model.healthSummary?.filesIndexed, 0)
        XCTAssertNil(model.syncError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: movedURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: movedURL.appendingPathComponent("AREAMATRIX.md").path
        ))
    }

    @MainActor
    func testDefaultCoreBridgeShowsIndexedFileCountAfterIndexedImport() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        let sourceRoot = try temporaryRepositorySettingsRepo()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
        }

        let sourceURL = sourceRoot.appendingPathComponent("indexed.pdf")
        try Data("indexed bytes".utf8).write(to: sourceURL)
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importIndexedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "indexed-display.pdf"
        )

        XCTAssertEqual(imported.storageMode, "Indexed")
        XCTAssertEqual(imported.sourcePath, sourceURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent(imported.path).path))

        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            repositoryOpener: bridge,
            scanSessionReader: bridge,
            existingRepositoryMetadataReader: SQLiteExistingRepositoryMetadataReader(),
            errorMapper: bridge
        )

        await model.load()

        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.healthSummary?.databaseStatus, .ok)
        XCTAssertEqual(model.healthSummary?.schemaVersion, 2)
        XCTAssertEqual(model.healthSummary?.filesIndexed, 1)
        XCTAssertEqual(model.healthSummary?.watcherStatus, .paused)
        XCTAssertNil(model.healthError)
    }

    @MainActor
    func testHealthFailureMapsDbStatusWithoutDiscardingLoadedConfig() async {
        let loader = RepositorySettingsRecordingLoader(results: [
            .success(.shellFixture(repoPath: "/tmp/repo"))
        ])
        let updater = RepositorySettingsRecordingUpdater(result: .success)
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(ExistingRepositoryMetadataSnapshot(
                schemaVersion: 1,
                lastOpenedAt: 1_778_000_000,
                configuredRepoPath: "/tmp/repo"
            ))
        ])
        let opener = RepoSettingsRepositoryOpener(
            result: .failure(CoreError.Db(message: "database is locked"))
        )
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: updater,
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            errorMapper: RepositorySettingsStaticErrorMapper()
        )

        await model.load()

        XCTAssertEqual(model.summary?.location, "/tmp/repo")
        XCTAssertEqual(model.healthSummary?.schemaVersion, 1)
        XCTAssertEqual(model.healthSummary?.databaseStatus, .locked)
        XCTAssertEqual(model.healthError?.databaseStatus, .locked)
        XCTAssertEqual(model.healthError?.message, "数据库错误")
        XCTAssertEqual(model.healthError?.recovery, "Retry status")
    }

    @MainActor
    func testS4X08C417LoadsPlatformCapabilitiesAndDisablesDiagnosticsWhenAccessIsLimited() async {
        let limitedAccess = repositorySettingsCapabilitySupport(
            status: .limited,
            uiEnabled: false,
            requiresPermission: true,
            reason: "Grant repository access."
        )
        let capabilities = repositorySettingsCapabilitiesFixture(securityBookmark: limitedAccess)
        let loader = RepoSettingsCapabilityLoader(result: .success(capabilities))
        let model = RepoPlatformCapabilitiesModel(
            appVersion: "4.3.159",
            capabilityLoader: loader,
            errorMapper: RepositorySettingsStaticErrorMapper()
        )

        await model.load()

        let requests = await loader.requests()
        XCTAssertEqual(requests, [RepositorySettingsCapabilityRequest(platform: .macos, appVersion: "4.3.159")])
        XCTAssertEqual(model.state, .loaded(capabilities))
        XCTAssertEqual(capabilities.repositorySettingsRows.map(\.label), [
            "Watcher",
            "Trash / Recycle Bin",
            "Cloud placeholders",
            "Repository access"
        ])
        XCTAssertFalse(model.allowsDiagnosticsExport)
        XCTAssertEqual(model.diagnosticsDisabledReason, "Grant repository access.")
    }
}
