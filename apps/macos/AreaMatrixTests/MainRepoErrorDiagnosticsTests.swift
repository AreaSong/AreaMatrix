import AreaMatrixCoreBridgeContract
@testable import AreaMatrix
import XCTest

final class MainRepoErrorDiagnosticsTests: XCTestCase {
    @MainActor
    func testMainRepoErrorDiagnosticsRequirePrivacyConfirmationAndUseCoreSnapshot() async {
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(
            snapshotPath: "/tmp/repo/.areamatrix/diagnostics/main-repo.db",
            createdAt: 1_778_000_000,
            warnings: ["index.db-wal disappeared during snapshot"]
        )
        let collector = ShellRecordingDiagnosticsCollector(result: .success(snapshot))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", nil)

        await model.collectMainRepositoryDiagnostics(repoPath: "/tmp/repo")
        XCTAssertEqual(model.mainRepoDiagnostics, .idle)

        model.requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: "/tmp/repo")
        await model.collectMainRepositoryDiagnostics(repoPath: "/tmp/repo")

        await collector.assertRequestedRepoPaths(["/tmp/repo"])
        XCTAssertEqual(model.mainRepoDiagnostics, .collected(snapshot))
        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", nil))
    }

    @MainActor
    func testMainRepoErrorDiagnosticsFailureMapsCoreErrorWithoutLeavingPage() async {
        let collector = ShellRecordingDiagnosticsCollector(
            result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", nil)

        model.requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: "/tmp/repo")
        await model.collectMainRepositoryDiagnostics(repoPath: "/tmp/repo")

        guard case let .failed(mapping) = model.mainRepoDiagnostics else {
            return XCTFail("expected failed diagnostics state")
        }

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", nil))
    }

    @MainActor
    func testCancelledMainRepoDiagnosticsIgnoresLateCollectorResult() async {
        let collector = SuspendedDiagnosticsCollector(result: .success(.testFixture()))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .mainRepoError("/tmp/repo", nil)
        model.requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: "/tmp/repo")

        let collection = Task { await model.collectMainRepositoryDiagnostics(repoPath: "/tmp/repo") }
        await collector.waitUntilStarted()
        model.cancelMainRepositoryDiagnosticsPrivacyConfirmation()
        await collector.finish()
        await collection.value

        XCTAssertEqual(model.mainRepoDiagnostics, .idle)
    }
}
