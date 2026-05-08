import XCTest
@testable import AreaMatrix

final class ErrorRecoveryStartupRecoveryPageFeatureTests: XCTestCase {
    @MainActor
    func testS132C116StartupRecoveryViewExposesReportRetryAndTechnicalDetails() {
        let report = RecoveryReportSnapshot(
            cleanedStagingFiles: 2,
            revertedStagingDbRows: 1,
            warnings: ["Kept active staging file"]
        )
        let completedView = StartupRecoveryErrorRecoveryView(
            state: .completed(report),
            onRetry: {}
        )
        let failedView = StartupRecoveryErrorRecoveryView(
            state: .failed(.s132StartupRecoveryMapping(rawContext: "recovery db locked")),
            onRetry: {}
        )
        let completedBody = s132MirrorDescription(of: completedView.body)
        let failedBody = s132MirrorDescription(of: failedView.body)

        XCTAssertTrue(completedBody.contains("Startup recovery complete"))
        XCTAssertTrue(completedBody.contains("启动恢复已完成"))
        XCTAssertTrue(completedBody.contains("S1-32-C1-16-startup-recovery"))
        XCTAssertTrue(completedBody.contains("S1-32-C1-16-recovery-report"))
        XCTAssertTrue(failedBody.contains("Startup recovery failed"))
        XCTAssertTrue(failedBody.contains("Retry startup recovery"))
        XCTAssertTrue(failedBody.contains("S1-32-C1-16-retry-startup-recovery"))
        XCTAssertTrue(failedBody.contains("ErrorRecoveryMappedErrorView"))
        XCTAssertFalse(failedBody.contains("Open repair"))
        XCTAssertFalse(failedBody.contains("Remove from index"))
    }

    @MainActor
    func testS132C121MappedErrorViewShowsCoreMappingWithoutHighRiskActions() {
        let mapping = CoreErrorMappingSnapshot.s132StartupRecoveryMapping(rawContext: "database is locked")
        let view = ErrorRecoveryMappedErrorView(
            mapping: mapping,
            retryButtonTitle: "Retry startup recovery",
            isRetrying: false,
            retryAccessibilityIdentifier: "S1-32-C1-21-retry",
            onRetry: {}
        )
        let body = s132MirrorDescription(of: view.body)

        XCTAssertTrue(body.contains("S1-32-C1-21-error-mapping"))
        XCTAssertTrue(body.contains("Startup recovery could not finish"))
        XCTAssertTrue(body.contains("Severity: Medium"))
        XCTAssertTrue(body.contains("Recoverability: Retryable"))
        XCTAssertTrue(body.contains("database is locked"))
        XCTAssertTrue(body.contains("S1-32-C1-21-retry"))
        XCTAssertFalse(body.contains("Open repair"))
        XCTAssertFalse(body.contains("Remove from index"))
        XCTAssertFalse(body.contains("Download & retry"))
    }

    @MainActor
    func testS132C121MappedErrorViewFallsBackWhenCoreMappingOmitsOptionalText() {
        let mapping = CoreErrorMappingSnapshot(
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
            retryAccessibilityIdentifier: "S1-32-C1-21-retry",
            onRetry: {}
        )
        let body = s132MirrorDescription(of: view.body)

        XCTAssertTrue(body.contains("Internal"))
        XCTAssertTrue(body.contains("Severity: Critical"))
        XCTAssertTrue(body.contains("Recoverability: Fatal"))
        XCTAssertTrue(body.contains("Retry the failed action or collect diagnostics from the source page."))
        XCTAssertTrue(body.contains("No technical context was provided by Core."))
    }

    @MainActor
    func testS132C116StartupRecoveryRetryShowsInFlightButtonState() {
        let failedView = StartupRecoveryErrorRecoveryView(
            state: .failed(.s132StartupRecoveryMapping(rawContext: "recovery db locked")),
            isRetrying: true,
            onRetry: {}
        )
        let failedBody = s132MirrorDescription(of: failedView.body)

        XCTAssertTrue(failedView.retryButtonTitle == "Retrying...")
        XCTAssertTrue(failedView.retryButtonIsDisabled)
        XCTAssertTrue(failedBody.contains("Retrying..."))
    }

    @MainActor
    func testS132C116RecoveryFailureBlocksRepositoryOpenAndRetryRerunsCoreRecovery() async {
        let mapping = CoreErrorMappingSnapshot.s132StartupRecoveryMapping(rawContext: "database is locked")
        let recoverer = MainLoadingRecordingStartupRecoverer(results: [
            .failure(CoreError.Db(message: "database is locked")),
            .success(RecoveryReportSnapshot(cleanedStagingFiles: 1, revertedStagingDbRows: 2, warnings: [])),
        ])
        let opener = MainLoadingPausingRepositoryOpener(
            opening: .mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)
        )
        let model = OnboardingModel(
            settingsReader: MainLoadingStaticSettingsReader(repoPath: nil),
            settingsWriter: ShellRecordingSettingsWriter(),
            pathValidator: MainLoadingStaticPathValidator(),
            initializedPathValidator: MainLoadingStaticInitializedPathValidator(),
            emptyRepositoryOpener: opener,
            startupRecoverer: recoverer,
            scanSessionReader: MainLoadingStaticScanSessionReader(result: .success(nil)),
            errorMapper: S132StartupRecoveryErrorMapper(mapping: mapping),
            helpOpener: MainLoadingNoopWelcomeHelpOpener()
        )

        let validation = RepoPathValidationSnapshot.mainLoadingInitializedFixture(repoPath: "/tmp/repo")
        await model.openExistingRepository(validation)
        let openedBeforeRetry = await opener.requestedConfiguredRepoPaths()
        let requestsBeforeRetry = await recoverer.requestedRepoPaths()

        XCTAssertEqual(openedBeforeRetry, [])
        XCTAssertEqual(requestsBeforeRetry, ["/tmp/repo"])
        guard case .mainLoading(let failedState) = model.route else {
            return XCTFail("Expected S1-32 startup recovery to stay in main loading")
        }
        XCTAssertEqual(failedState.recoveryErrorMapping, mapping)
        XCTAssertEqual(failedState.recoveryStatusText, "启动恢复失败：Startup recovery could not finish")

        let retryTask = Task {
            await model.retryMainRepositoryFromError(repoPath: "/tmp/repo")
        }
        await opener.waitUntilStarted()
        let requestsAfterRetryStarted = await recoverer.requestedRepoPaths()
        let openedAfterRetryStarted = await opener.requestedConfiguredRepoPaths()

        XCTAssertEqual(requestsAfterRetryStarted, ["/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(openedAfterRetryStarted, ["/tmp/repo"])

        await opener.finishOpen()
        await retryTask.value
        XCTAssertEqual(model.route, .mainList(.mainLoadingFixture(repoPath: "/tmp/repo", fileCount: 1)))
    }

    @MainActor
    func testS132C116DefaultCoreBridgeUsesGeneratedRecoverOnStartupBoundary() async throws {
        let repoURL = try s132TemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let report = try await bridge.recoverOnStartup(repoPath: repoURL.path)

        XCTAssertFalse(report.hasVisibleDetails)
    }
}

private actor S132StartupRecoveryErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mapping
    }
}

private actor MainLoadingStaticInitializedPathValidator: CoreInitializedRepositoryPathValidating {
    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }
}

private actor MainLoadingStaticPathValidator: CoreRepositoryPathValidating {
    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        .mainLoadingInitializedFixture(repoPath: repoPath)
    }
}

private extension CoreErrorMappingSnapshot {
    static func s132StartupRecoveryMapping(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Startup recovery could not finish",
            severity: .medium,
            suggestedAction: "Retry startup recovery before opening the repository.",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

private func s132TemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS132StartupRecovery-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func s132MirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS132MirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS132MirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS132MirrorDescription(of: child.value, to: &lines)
    }
}
