@testable import AreaMatrix
import XCTest

final class RepositorySettingsHealthFeatureTests: XCTestCase {
    @MainActor
    func testMetadataReaderReadsSchemaVersionFromRealInitializedRepositoryWithoutWalSidecars() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
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
        defer { removeTestTemporaryItems(originalURL, movedURL) }
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
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }

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
        let loader = RecordingConfigurationLoader(results: [
            .success(.shellFixture(repoPath: "/tmp/repo"))
        ])
        let updater = RecordingConfigurationUpdater(result: .success(()))
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
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
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
    func testRepositorySettingsLoadsPlatformCapabilitiesAndDisablesDiagnosticsWhenAccessIsLimited(
    ) async {
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
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
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

    @MainActor
    func testRepositorySettingsPlatformCapabilitiesUsesInjectedAppVersionReaderWhenNoOverrideIsPassed() async {
        let loader = RepoSettingsCapabilityLoader(result: .success(repositorySettingsCapabilitiesFixture()))
        let model = RepoPlatformCapabilitiesModel(
            appVersionReader: StaticAppVersionReader(version: "5.6.7 (89)"),
            capabilityLoader: loader,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()

        let requests = await loader.requests()
        XCTAssertEqual(requests, [RepositorySettingsCapabilityRequest(
            platform: .macos,
            appVersion: "5.6.7 (89)"
        )])
    }
}
