@testable import AreaMatrix
import XCTest

final class RepositorySettingsRecoveryTests: XCTestCase {
    @MainActor
    func testRepositoryPathSyncRetryPersistsPendingVisiblePathWithoutReloadingConfig() async throws {
        let repoURL = try temporaryRepositorySettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try createRepositorySettingsMetadataDatabaseMarker(in: repoURL)

        let staleConfig = RepoConfigSnapshot.shellFixture(repoPath: "/tmp/stale-repo")
        var expectedConfig = staleConfig
        expectedConfig.repoPath = repoURL.path
        let loader = RecordingConfigurationLoader(results: [.success(staleConfig)])
        let updater = RecordingConfigurationUpdater(failureThenSuccess: CoreError.Db(message: "locked"))
        let model = RepositorySettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: updater,
            repositoryOpener: RepoSettingsRepositoryOpener(
                result: .success(RepositoryOpeningResult.importSingleFileFixture(repoPath: repoURL.path))
            ),
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            existingRepositoryMetadataReader: RepoSettingsMetadataReader(results: [
                .success(.testFixture(
                    schemaVersion: 1,
                    lastOpenedAt: 1_778_000_000,
                    configuredRepoPath: repoURL.path
                ))
            ]),
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        await model.load()
        XCTAssertNotNil(model.syncError)
        XCTAssertEqual(model.loadedConfig, expectedConfig)

        await model.retryRepositoryPathSync()

        await updater.assertConfigurationUpdateRequests([
            RecordingConfigurationUpdater.Request(repoPath: repoURL.path, config: expectedConfig),
            RecordingConfigurationUpdater.Request(repoPath: repoURL.path, config: expectedConfig)
        ])
        XCTAssertNil(model.syncError)
        XCTAssertEqual(model.loadedConfig, expectedConfig)
    }

    @MainActor
    func testCancelledDiagnosticsIgnoresLateCollectorResult() async {
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(snapshotPath: "/tmp/late-diagnostics")
        let collector = SuspendedDiagnosticsCollector(result: .success(snapshot))
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: RecordingConfigurationLoader(results: []),
            updater: RecordingConfigurationUpdater(result: .success(())),
            diagnosticsCollector: collector,
            errorMapper: RecordingCoreErrorMapper.repositorySettings()
        )

        model.requestDiagnosticsExport()
        let collection = Task { await model.collectDiagnostics() }
        await collector.waitUntilStarted()
        XCTAssertEqual(model.diagnosticsState, .collecting)

        model.cancelDiagnosticsExport()
        await collector.finish()
        await collection.value

        XCTAssertEqual(model.diagnosticsState, .idle)
    }
}
