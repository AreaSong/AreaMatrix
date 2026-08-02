@testable import AreaMatrix
import XCTest

final class RepositorySettingsHealthFeatureTests: XCTestCase {
    func testBundleAppVersionReaderBuildsCoreCompatibleVersionIdentifier() async throws {
        let appVersion = BundleAppVersionReader.versionIdentifier(
            version: " 0.1.0 ",
            build: " 202605101812 "
        )

        XCTAssertEqual(appVersion, "0.1.0+202605101812")
        let capabilities = try await CoreBridge().getPlatformCapabilities(
            platform: .macos,
            appVersion: appVersion
        )
        XCTAssertEqual(capabilities.appVersion, appVersion)
    }

    @MainActor
    func testMetadataReaderReadsSchemaVersionFromRealInitializedRepositoryWithoutWalSidecars() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        removeRepositorySettingsMetadataDatabaseSidecars(in: repoURL)
        let before = try repositorySettingsMetadataFootprint(in: repoURL)

        do {
            let metadata = try await SQLiteExistingRepositoryMetadataReader().metadata(repoPath: repoURL.path)
            XCTAssertEqual(metadata.schemaVersion, 3)
            XCTAssertEqual(metadata.configuredRepoPath, repoURL.path)
            XCTAssertEqual(try repositorySettingsMetadataFootprint(in: repoURL), before)
        } catch {
            XCTFail("metadata read failed: \(error)")
        }
    }

    @MainActor
    func testMetadataReaderReadsRepositoryWithWalSidecarsWithoutMutatingMetadataFiles() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)
        let database = try openRepositorySettingsWalFixture(in: repoURL)
        defer { sqlite3_close(database) }

        let metadataURL = repositorySettingsMetadataURL(in: repoURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.appendingPathComponent("index.db-wal").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: metadataURL.appendingPathComponent("index.db-shm").path))
        let before = try repositorySettingsMetadataFootprint(in: repoURL)

        let metadata = try await SQLiteExistingRepositoryMetadataReader().metadata(repoPath: repoURL.path)

        XCTAssertEqual(metadata.schemaVersion, 3)
        XCTAssertEqual(metadata.configuredRepoPath, repoURL.path)
        XCTAssertEqual(
            try repositorySettingsMetadataFootprint(in: repoURL).normalizingSQLiteSharedMemoryCoordination(),
            before.normalizingSQLiteSharedMemoryCoordination()
        )
    }

    func testMetadataReaderMissingDatabaseDoesNotCreateMetadataFiles() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try FileManager.default.createDirectory(
            at: repositorySettingsMetadataURL(in: repoURL),
            withIntermediateDirectories: true
        )
        let before = try repositorySettingsMetadataFootprint(in: repoURL)

        do {
            _ = try await SQLiteExistingRepositoryMetadataReader().metadata(repoPath: repoURL.path)
            XCTFail("missing metadata database must fail")
        } catch let CoreError.Db(message) {
            XCTAssertEqual(message, "missing .areamatrix/index.db")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(try repositorySettingsMetadataFootprint(in: repoURL), before)
    }

    func testMetadataReaderRejectsCorruptDatabaseWithoutMutatingMetadataFiles() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let metadataURL = repositorySettingsMetadataURL(in: repoURL)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try Data("not a sqlite database".utf8).write(to: repositorySettingsMetadataDatabaseURL(in: repoURL))
        let before = try repositorySettingsMetadataFootprint(in: repoURL)

        do {
            _ = try await SQLiteExistingRepositoryMetadataReader().metadata(repoPath: repoURL.path)
            XCTFail("corrupt metadata database must fail")
        } catch is CoreError {
            // The exact SQLite message is version-specific; the file-safety contract is the stable assertion.
        }

        XCTAssertEqual(try repositorySettingsMetadataFootprint(in: repoURL), before)
    }

    @MainActor
    func testMetadataReaderReadsReadOnlyDatabaseWithoutCreatingOrMutatingMetadataFiles() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try await CoreBridge().initializeEmptyRepository(repoPath: repoURL.path)
        removeRepositorySettingsMetadataDatabaseSidecars(in: repoURL)
        let metadataURL = repositorySettingsMetadataURL(in: repoURL)
        let dbURL = repositorySettingsMetadataDatabaseURL(in: repoURL)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: metadataURL.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dbURL.path)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: dbURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: metadataURL.path)
        let before = try repositorySettingsMetadataFootprint(in: repoURL)

        let metadata = try await SQLiteExistingRepositoryMetadataReader().metadata(repoPath: repoURL.path)

        XCTAssertEqual(metadata.schemaVersion, 3)
        XCTAssertEqual(metadata.configuredRepoPath, repoURL.path)
        XCTAssertEqual(try repositorySettingsMetadataFootprint(in: repoURL), before)
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
            repositoryOpener: bridge,
            scanSessionReader: bridge,
            diagnosticsCollector: bridge,
            coreVersionLoader: bridge,
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
            diagnosticsCollector: bridge,
            coreVersionLoader: bridge,
            errorMapper: bridge
        )

        await model.load()

        XCTAssertEqual(model.summary?.metadataStatus, ".areamatrix/ found")
        XCTAssertEqual(model.healthSummary?.databaseStatus, .ok)
        XCTAssertEqual(model.healthSummary?.schemaVersion, 3)
        XCTAssertEqual(model.healthSummary?.filesIndexed, 1)
        XCTAssertEqual(model.healthSummary?.watcherStatus, .paused)
        XCTAssertNil(model.healthError)
    }

    @MainActor
    func testHealthFailureMapsDbStatusWithoutDiscardingLoadedConfig() async {
        let loader = RecordingConfigurationLoader(results: [
            .success(.shellFixture(repoPath: "/tmp/repo"))
        ])
        let metadataReader = RepoSettingsMetadataReader(results: [
            .success(.testFixture(
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
            updater: NoopConfigurationUpdater(),
            repositoryOpener: opener,
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: metadataReader,
            diagnosticsCollector: RecordingDiagnosticsCollector(snapshot: .testFixture()),
            coreVersionLoader: StaticCoreVersionReader(version: "0.1.0"),
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()

        XCTAssertEqual(model.summary?.location, "/tmp/repo")
        XCTAssertEqual(model.healthSummary?.schemaVersion, 1)
        XCTAssertEqual(model.healthSummary?.databaseStatus, .locked)
        XCTAssertEqual(model.healthError?.databaseStatus, .locked)
        XCTAssertEqual(model.healthError?.message, L10n.message(
            "error.unmapped.message",
            fallback: "数据库错误",
            technicalDetail: "数据库错误"
        ))
        XCTAssertEqual(model.healthError?.recovery, L10n.message(
            "error.unmapped.action",
            fallback: "Retry status",
            technicalDetail: "Retry status"
        ))
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

        await loader.assertPlatformCapabilityRequests([
            RepositorySettingsCapabilityRequest(platform: .macos, appVersion: "4.3.159")
        ])
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

        await loader.assertPlatformCapabilityRequests([RepositorySettingsCapabilityRequest(
            platform: .macos,
            appVersion: "5.6.7 (89)"
        )])
    }
}
