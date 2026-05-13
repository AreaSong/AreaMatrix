@testable import AreaMatrix
import XCTest

final class MainRepoExternalRemovalTests: XCTestCase {
    @MainActor
    func testMainRepoErrorExternalRemovalSyncsMissingFileThroughCoreBridge() async {
        let result = SyncResultSnapshot.shellDeletedFixture()
        let syncer = ShellRecordingExternalChangesSyncer(result: .success(result))
        let opener = ShellRecordingRepositoryOpener(result: .success(
            .shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        ))
        let initializedValidator = ShellRecordingInitializedPathValidator(
            result: .success(.shellFixture(
                repoPath: "/tmp/repo",
                isInitialized: true,
                recommendedMode: nil
            ))
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            initializedPathValidator: initializedValidator,
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/repo/docs/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRequests()
        let validatedPaths = await initializedValidator.requestedRepoPaths()
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(requests.map(\.relativePath), ["docs/gone.pdf"])
        XCTAssertEqual(validatedPaths, ["/tmp/repo"])
        XCTAssertEqual(openedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.mainRepoExternalRemoval, .synced(result))
        XCTAssertEqual(model.route, .mainEmpty(.shellFixture(repoPath: "/tmp/repo", fileCount: 0)))
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    @MainActor
    func testMainRepoErrorExternalRemovalIgnoresPathOutsideRepository() async {
        let syncer = ShellRecordingExternalChangesSyncer(result: .success(.shellDeletedFixture()))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/other/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let requests = await syncer.recordedRequests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.mainRepoExternalRemoval, .unavailable)
        XCTAssertFalse(model.isRetryingMainRepository)
    }

    @MainActor
    func testMainRepoErrorExternalRemovalKeepsErrorStateWhenCoreSyncFails() async {
        let syncer = ShellRecordingExternalChangesSyncer(result: .failure(CoreError.Db(message: "db locked")))
        let opener = ShellRecordingRepositoryOpener(result: .success(
            .shellFixture(repoPath: "/tmp/repo", fileCount: 0)
        ))
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            startupRecoverer: ShellStaticStartupRecoverer(),
            externalChangesSyncer: syncer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        await model.updateMainRepoExternalRemoval(
            from: CoreError.FileNotFound(path: "/tmp/repo/docs/gone.pdf"),
            repoPath: "/tmp/repo"
        )
        await model.confirmMainRepositoryExternalRemoval(repoPath: "/tmp/repo")
        let openedPaths = await opener.requestedConfiguredRepoPaths()

        guard case let .failed(failureMapping) = model.mainRepoExternalRemoval else {
            return XCTFail("expected failed external removal state")
        }
        guard case let .mainRepoError(repoPath, routeMapping) = model.route else {
            return XCTFail("expected main repo error, got \(model.route)")
        }

        XCTAssertEqual(openedPaths, [])
        XCTAssertEqual(repoPath, "/tmp/repo")
        XCTAssertEqual(failureMapping.kind, .db)
        XCTAssertEqual(routeMapping?.kind, .db)
        XCTAssertEqual(model.mainRepoRecoveryErrorMapping?.kind, .db)
        XCTAssertFalse(model.isRetryingMainRepository)
    }
}
