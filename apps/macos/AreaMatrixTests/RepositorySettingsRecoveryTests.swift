@testable import AreaMatrix
import XCTest

final class RepositorySettingsRecoveryTests: XCTestCase {
    @MainActor
    func testCancelledDiagnosticsIgnoresLateCollectorResult() async {
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(snapshotPath: "/tmp/late-diagnostics")
        let collector = SuspendedDiagnosticsCollector(result: .success(snapshot))
        let model = RepositorySettingsModel(
            repoPath: "/tmp/repo",
            loader: RecordingConfigurationLoader(results: []),
            updater: NoopConfigurationUpdater(),
            repositoryOpener: RepoSettingsRepositoryOpener(
                result: .success(RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo"))
            ),
            scanSessionReader: RepoSettingsScanSessionReader(result: .success(nil)),
            diagnosticsCollector: collector,
            coreVersionLoader: StaticCoreVersionReader(version: "0.1.0"),
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
