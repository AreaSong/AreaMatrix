@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import XCTest

final class StartupRecoveryPageFeatureTests: XCTestCase {
    @MainActor
    func testStartupRecoveryStartupRecoveryCoreStartupRecoveryViewExposesReportRetryAndTechnicalDetails() {
        let report = RecoveryReportSnapshot.testFixture(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept active staging file"]
        )
        let completedView = StartupRecoveryErrorRecoveryView(
            state: .completed(report),
            onRetry: {}
        )
        let failedView = StartupRecoveryErrorRecoveryView(
            state: .failed(.startupRecoveryStartupRecoveryMapping(rawContext: "recovery db locked")),
            onRetry: {}
        )

        assertTestMirrorDescription(of: completedView.body, contains: [
            "Startup recovery complete",
            "Startup recovery completed",
            "startup-recovery-startup-recovery-core-startup-recovery",
            "startup-recovery-startup-recovery-core-recovery-report"
        ])
        assertTestMirrorDescription(
            of: failedView.body,
            contains: [
                "Startup recovery failed",
                "Retry startup recovery",
                "startup-recovery-startup-recovery-core-retry-startup-recovery",
                "ErrorRecoveryMappedErrorView"
            ],
            doesNotContain: [
                "Open repair",
                "Remove from index"
            ]
        )
    }

    @MainActor
    func testStartupRecoveryErrorMappingCoreMappedErrorViewShowsCoreMappingWithoutHighRiskActions() {
        let mapping = CoreErrorMappingSnapshot.startupRecoveryStartupRecoveryMapping(rawContext: "database is locked")
        let view = ErrorRecoveryMappedErrorView(
            mapping: mapping,
            retryButtonTitle: "Retry startup recovery",
            isRetrying: false,
            retryAccessibilityIdentifier: "startup-recovery-error-mapping-retry",
            onRetry: {}
        )

        assertTestMirrorDescription(
            of: view.body,
            contains: [
                "startup-recovery-error-mapping-error-mapping",
                L10n.string("error.unmapped.message"),
                "Severity: Medium",
                "Recoverability: Retryable",
                "database is locked",
                "startup-recovery-error-mapping-retry"
            ],
            doesNotContain: [
                "Open repair",
                "Remove from index",
                "Download & retry"
            ]
        )
    }

    @MainActor
    func testStartupRecoveryErrorMappingCoreMappedErrorViewFallsBackWhenCoreMappingOmitsOptionalText() {
        let mapping = CoreErrorMappingSnapshot.testFixture(
            kind: .internal,
            userMessage: "AreaMatrix hit an internal error.",
            severity: .critical,
            suggestedAction: "",
            recoverability: .fatal,
            rawContext: ""
        )
        let view = ErrorRecoveryMappedErrorView(
            mapping: mapping,
            retryButtonTitle: "Retry startup recovery",
            isRetrying: false,
            retryAccessibilityIdentifier: "startup-recovery-error-mapping-retry",
            onRetry: {}
        )

        assertTestMirrorDescription(of: view.body, contains: [
            "Internal",
            "Severity: Critical",
            "Recoverability: Fatal",
            L10n.string("error.unmapped.action"),
            "No technical context was provided by Core."
        ])
    }

    @MainActor
    func testStartupRecoveryStartupRecoveryCoreStartupRecoveryRetryShowsInFlightButtonState() {
        let failedView = StartupRecoveryErrorRecoveryView(
            state: .failed(.startupRecoveryStartupRecoveryMapping(rawContext: "recovery db locked")),
            isRetrying: true,
            onRetry: {}
        )

        XCTAssertTrue(failedView.retryButtonTitle == "Retrying...")
        XCTAssertTrue(failedView.retryButtonIsDisabled)
        assertTestMirrorDescription(of: failedView.body, contains: "Retrying...")
    }

    @MainActor
    func testStartupRecoveryStartupRecoveryCoreRecoveryFailureBlocksRepositoryOpenAndRetryRerunsCoreRecovery() async {
        let mapping = CoreErrorMappingSnapshot.startupRecoveryStartupRecoveryMapping(rawContext: "database is locked")
        let recoverer = RecordingCoreStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database is locked")),
            .success(.testFixture(cleanedStagingFiles: 1, revertedStagingDbRows: 2))
        ])
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: ShellRecordingSettingsWriter(),
            pathValidator: MainLoadingInitializedPathValidator(),
            initializedPathValidator: MainLoadingInitializedPathValidator(),
            emptyRepositoryOpener: opener,
            startupRecoverer: recoverer,
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        await model.openExistingRepository(validation)

        await opener.assertNoConfiguredRepoPaths()
        await recoverer.assertRequestedRepoPaths(["/tmp/repo"])
        guard let failedState = requireMainLoadingState(
            model,
            message: "Expected startup-recovery startup recovery to stay in main loading"
        ) else { return }
        XCTAssertEqual(failedState.recoveryErrorMapping, mapping)
        XCTAssertEqual(
            failedState.recoveryStatusText,
            "Startup recovery failed: \(L10n.string("error.unmapped.message"))"
        )

        let retryTask = Task {
            await model.retryMainRepositoryFromError(repoPath: "/tmp/repo")
        }
        await opener.waitUntilStarted()

        await recoverer.assertRequestedRepoPaths(["/tmp/repo", "/tmp/repo"])
        await opener.assertRequestedConfiguredRepoPaths(["/tmp/repo"])

        await opener.finishOpen()
        await retryTask.value
        XCTAssertEqual(model.route, .mainList(.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)))
    }

    @MainActor
    func testStartupRecoveryStartupRecoveryCoreDefaultCoreBridgeUsesGeneratedRecoverOnStartupBoundary() async throws {
        let repoURL = try startupRecoveryTemporaryDirectory()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let report = try await bridge.recoverOnStartup(repoPath: repoURL.path)

        XCTAssertFalse(report.hasVisibleDetails)
    }
}

private extension CoreErrorMappingSnapshot {
    static func startupRecoveryStartupRecoveryMapping(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "Startup recovery could not finish",
            severity: .medium,
            suggestedAction: "Retry startup recovery before opening the repository.",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

private func startupRecoveryTemporaryDirectory() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixStartupRecoveryStartupRecovery")
}
