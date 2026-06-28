@testable import AreaMatrix
import XCTest

final class ErrorRecoveryPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testStartupRecoveryPageIntegrationConnectsStartupRecoveryMappingEntryExitAndTreeState() async throws {
        let mapping = CoreErrorMappingSnapshot.startupRecoveryIntegrationMapping(
            userMessage: "Startup recovery could not finish",
            severity: .medium,
            recoverability: .retryable,
            rawContext: "database is locked"
        )
        let recoverer = MainLoadingRecordingStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database is locked")),
            .success(RecoveryReportSnapshot(cleanedStagingFiles: 1, revertedStagingDbRows: 1, warnings: []))
        ])
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/startupRecovery-repo", fileCount: 1)
        )
        let treeLister = MainLoadingRecordingTreeLister(result: .success(.mainLoadingTreeFixture()))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: MainLoadingRecordingSettingsWriter(),
            pathValidator: MainLoadingInitializedPathValidator(),
            initializedPathValidator: MainLoadingInitializedPathValidator(),
            emptyRepositoryOpener: opener,
            mainLoadingTreeLister: treeLister,
            startupRecoverer: recoverer,
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: StartupRecoveryIntegrationErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.openExistingRepository(
            RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/startupRecovery-repo")
        )
        let failedState = try requireStartupRecoveryMainLoadingState(model)

        let initialRecoveryRequests = await recoverer.requestedRepoPaths()
        let initialOpenRequests = await opener.requestedConfiguredRepoPaths()
        XCTAssertEqual(initialRecoveryRequests, ["/tmp/startupRecovery-repo"])
        XCTAssertEqual(initialOpenRequests, [])
        assertStartupRecoveryStartupRecoveryFailureState(failedState, mapping: mapping)

        let retryTask = await assertStartupRecoveryRetryingState(model: model, opener: opener, recoverer: recoverer)

        await opener.finishOpen()
        await retryTask.value

        let treeRequests = await treeLister.requestedRepoPaths()
        XCTAssertEqual(treeRequests, ["/tmp/startupRecovery-repo"])
        XCTAssertEqual(
            model.route,
            OnboardingModel.Route.mainList(.mainLoadingFixture(repoPath: "/tmp/startupRecovery-repo", fileCount: 1))
        )
    }

    @MainActor
    func testStartupRecoveryPageIntegrationRoutesFatalDbMappingToRepairWithoutRunningRepair() async {
        let mapping = CoreErrorMappingSnapshot.startupRecoveryIntegrationMapping(
            userMessage: "Repository metadata needs repair",
            severity: .critical,
            recoverability: .fatal,
            rawContext: "database corrupted"
        )
        let recoverer = MainLoadingRecordingStartupRecoverer(
            result: .failure(CoreError.Db(message: "database corrupted"))
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            pathValidator: MainLoadingInitializedPathValidator(),
            initializedPathValidator: MainLoadingInitializedPathValidator(),
            emptyRepositoryOpener: MainLoadingFailingRepositoryOpener(
                error: CoreError.Internal(message: "should not open")
            ),
            startupRecoverer: recoverer,
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: StartupRecoveryIntegrationErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        await model.openExistingRepository(
            RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/startupRecovery-corrupt")
        )

        let recoveryRequests = await recoverer.requestedRepoPaths()
        XCTAssertEqual(recoveryRequests, ["/tmp/startupRecovery-corrupt"])
        XCTAssertEqual(model.route, OnboardingModel.Route.mainRepoError("/tmp/startupRecovery-corrupt", mapping))
        model.openMainRepositoryRepair(repoPath: "/tmp/startupRecovery-corrupt")
        XCTAssertEqual(
            model.route,
            OnboardingModel.Route.dbRepairConfirm(DatabaseRepairRouteState(
                repoPath: "/tmp/startupRecovery-corrupt",
                scanSession: nil,
                mapping: mapping,
                returnRoute: .mainRepoError(mapping)
            ))
        )
    }
}

@MainActor
private func assertStartupRecoveryRetryingState(
    model: OnboardingModel,
    opener: MainLoadingPausingRepositoryOpener,
    recoverer: MainLoadingRecordingStartupRecoverer
) async -> Task<Void, Never> {
    let retryTask = Task {
        await model.retryMainRepositoryFromError(repoPath: "/tmp/startupRecovery-repo")
    }
    await opener.waitUntilStarted()
    let expectedRecoveryReport = RecoveryReportSnapshot(
        cleanedStagingFiles: 1,
        revertedStagingDbRows: 1,
        warnings: []
    )
    let retryingState = await waitForStartupRecoveryIntegrationMainLoadingState(model) { state in
        state.startupRecovery == .completed(expectedRecoveryReport) &&
            state.treeLoading?.loadedTree != nil
    }
    let retryingRecoveryView = StartupRecoveryErrorRecoveryView(
        state: retryingState.startupRecovery ?? .checking,
        isRetrying: true,
        onRetry: {}
    )

    let retryRecoveryRequests = await recoverer.requestedRepoPaths()
    let retryOpenRequests = await opener.requestedConfiguredRepoPaths()
    XCTAssertEqual(retryRecoveryRequests, ["/tmp/startupRecovery-repo", "/tmp/startupRecovery-repo"])
    XCTAssertEqual(retryOpenRequests, ["/tmp/startupRecovery-repo"])
    XCTAssertEqual(retryingState.recoveryVisibleReport?.cleanedStagingFiles, 1)
    XCTAssertEqual(retryingRecoveryView.retryButtonTitle, "Retrying...")
    XCTAssertTrue(retryingRecoveryView.retryButtonIsDisabled)
    return retryTask
}

@MainActor
private func requireStartupRecoveryMainLoadingState(
    _ model: OnboardingModel,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> MainLoadingState {
    guard case let .mainLoading(state) = model.route else {
        XCTFail(
            "Expected startup recovery failure to remain on startup-recovery main loading error recovery",
            file: file,
            line: line
        )
        throw CoreError.Internal(message: "expected main loading")
    }
    return state
}

private func assertStartupRecoveryStartupRecoveryFailureState(
    _ state: MainLoadingState,
    mapping: CoreErrorMappingSnapshot
) {
    let recoveryView = StartupRecoveryErrorRecoveryView(
        state: state.startupRecovery ?? .checking,
        isRetrying: false,
        onRetry: {}
    )
    XCTAssertEqual(state.recoveryErrorMapping, mapping)
    XCTAssertTrue(state.recoveryStatusText?.contains("Startup recovery could not finish") == true)
    XCTAssertEqual(recoveryView.retryButtonTitle, "Retry startup recovery")
    XCTAssertFalse(recoveryView.retryButtonIsDisabled)
    assertTestMirrorDescription(of: MainLoadingView(
        state: state,
        isRetryingStartupRecovery: false,
        onCancelOpening: {},
        onRetryStartupRecovery: {},
        onRetryTree: {},
        onRetryOpening: {}
    ).body, contains: "Cancel opening")
    XCTAssertFalse(RepositoryErrorPresentation.mainRepo(mapping: mapping).primaryAction == .openRepair)
}

private actor StartupRecoveryIntegrationErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private extension CoreErrorMappingSnapshot {
    static func startupRecoveryIntegrationMapping(
        userMessage: String,
        severity: CoreErrorSeveritySnapshot,
        recoverability: CoreErrorRecoverabilitySnapshot,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: userMessage,
            severity: severity,
            suggestedAction: "Retry startup recovery before opening the repository.",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}

@MainActor
private func waitForStartupRecoveryIntegrationMainLoadingState(
    _ model: OnboardingModel,
    matching predicate: (MainLoadingState) -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainLoadingState {
    if let state = await waitForMainLoadingState(model, matching: predicate, file: file, line: line) {
        return state
    }

    return MainLoadingState(repoPath: "")
}
