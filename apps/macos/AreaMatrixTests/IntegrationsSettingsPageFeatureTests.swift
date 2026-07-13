@testable import AreaMatrix
import XCTest

final class IntegrationsSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesRepositoryConfigCoreConfigForVisibleICloudIntegrationState() async {
        let loader = RecordingConfigurationLoader(results: [
            .success(.integrationsFixture(repoPath: "/tmp/repo", iCloudWarn: false))
        ])
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: RecordingConfigurationUpdater(results: [.success(())]),
            errorMapper: RecordingCoreErrorMapper.integrationsSettings(),
            statusDetector: StaticICloudStatusDetector(
                snapshot: .testFixture(repositoryLocation: .iCloudDrive, iCloudStatus: .available)
            )
        )

        await model.load()

        await loader.assertRequestedPaths(["/tmp/repo"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.summary?.repositoryLocation, .iCloudDrive)
        XCTAssertEqual(model.summary?.iCloudStatus, .available)
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, false)
        XCTAssertFalse(model.summary?.canRetryStatus ?? true)
    }

    @MainActor
    func testICloudWarningsSaveThroughUpdateConfigWithoutStaticState() async {
        let updater = RecordingConfigurationUpdater(results: [.success(())])
        let model = await loadedModel(updater: updater, iCloudWarn: true)

        await model.setICloudWarningsEnabled(false)

        await updater.assertRequestedRepoPaths(["/tmp/repo"])
        await updater.assertRequestedConfigValues(\.iCloudWarn, [false])
        await updater.assertRequestedConfigValues(\.repoPath, ["/tmp/repo"])
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testSaveFailureRollsBackAndRetryUsesSameCoreConfig() async {
        let updater = RecordingConfigurationUpdater(results: [
            .failure(CoreError.Db(message: "locked")),
            .success(())
        ])
        let mapper = RecordingCoreErrorMapper.integrationsSettings()
        let model = await loadedModel(updater: updater, errorMapper: mapper, iCloudWarn: true)

        await model.setICloudWarningsEnabled(false)

        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, true)
        XCTAssertEqual(model.saveError?.message, "数据库错误")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()

        await updater.assertRequestedConfigValues(\.iCloudWarn, [false, false])
        await mapper.assertMappedCoreErrors([CoreError.Db(message: "locked")])
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testLoadFailureUsesCoreErrorMappingAndKeepsRetryAvailable() async {
        let loader = RecordingConfigurationLoader(results: [
            .failure(CoreError.Config(reason: "invalid repo_config"))
        ])
        let mapper = RecordingCoreErrorMapper.integrationsSettings()
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: RecordingConfigurationUpdater(results: [.success(())]),
            errorMapper: mapper,
            statusDetector: StaticICloudStatusDetector(
                snapshot: .testFixture(repositoryLocation: .unknown, iCloudStatus: .unknown)
            )
        )

        await model.load()

        await mapper.assertMappedCoreErrors([CoreError.Config(reason: "invalid repo_config")])
        XCTAssertEqual(model.loadState, .failed(IntegrationsSettingsError(
            message: "配置错误",
            recovery: "Retry status"
        )))
        XCTAssertNil(model.summary)
    }

    @MainActor
    func testPlatformActionsStayInMacLayerWithoutConfigWrites() async {
        let finderOpener = RecordingRepositoryFinderOpener()
        let helpOpener = RecordingICloudHelpOpener()
        let updater = RecordingConfigurationUpdater(results: [.success(())])
        let model = await loadedModel(
            updater: updater,
            finderOpener: finderOpener,
            helpOpener: helpOpener
        )

        model.openICloudHelp()
        model.revealRepositoryInFinder()

        helpOpener.assertOpenCount(1)
        finderOpener.assertRepoPaths(["/tmp/repo"])
        await updater.assertNoConfigurationUpdateRequests()
        XCTAssertEqual(model.actionFeedback, .success("Repository folder revealed in Finder."))
    }

    func testLocalICloudStatusDetectorReportsLocalFolderWithoutReadingRealTokenState() async {
        let detector = LocalICloudStatusDetector(identityTokenReader: StaticICloudIdentityTokenReader(
            hasICloudIdentityToken: true
        ), resourceValueReader: StaticICloudResourceValueReader(
            isUbiquitousItem: false
        ))

        let snapshot = await detector.snapshot(
            repoPath: "/tmp/repo",
            config: .integrationsFixture(repoPath: "/tmp/repo")
        )

        XCTAssertEqual(snapshot.repositoryLocation, .localFolder)
        XCTAssertEqual(snapshot.iCloudStatus, .unavailable)
    }

    func testLocalICloudStatusDetectorUsesInjectedIdentityTokenForICloudDriveStatus() async {
        let unavailableDetector = LocalICloudStatusDetector(
            identityTokenReader: StaticICloudIdentityTokenReader(hasICloudIdentityToken: false),
            resourceValueReader: StaticICloudResourceValueReader(isUbiquitousItem: true)
        )
        let availableDetector = LocalICloudStatusDetector(
            identityTokenReader: StaticICloudIdentityTokenReader(hasICloudIdentityToken: true),
            resourceValueReader: StaticICloudResourceValueReader(isUbiquitousItem: true)
        )

        let unavailableSnapshot = await unavailableDetector.snapshot(
            repoPath: "/tmp/repo",
            config: .integrationsFixture(repoPath: "/tmp/repo")
        )
        let availableSnapshot = await availableDetector.snapshot(
            repoPath: "/tmp/repo",
            config: .integrationsFixture(repoPath: "/tmp/repo")
        )

        XCTAssertEqual(unavailableSnapshot.repositoryLocation, .iCloudDrive)
        XCTAssertEqual(unavailableSnapshot.iCloudStatus, .unavailable)
        XCTAssertEqual(availableSnapshot.repositoryLocation, .iCloudDrive)
        XCTAssertEqual(availableSnapshot.iCloudStatus, .available)
    }

    @MainActor
    func testDefaultCoreBridgePersistsICloudWarningsWithoutCreatingUserRootFiles() async throws {
        let repoURL = try temporaryIntegrationsSettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let current = try await bridge.loadConfig(repoPath: repoURL.path)
        let targetWarningState = !current.iCloudWarn
        let model = IntegrationsSettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            errorMapper: bridge,
            statusDetector: StaticICloudStatusDetector(
                snapshot: .testFixture()
            )
        )

        await model.load()
        await model.setICloudWarningsEnabled(targetWarningState)
        let reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.iCloudWarn, targetWarningState)
        XCTAssertEqual(model.summary?.iCloudWarningsEnabled, targetWarningState)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path
        ))
    }

    @MainActor
    private func loadedModel(
        updater: RecordingConfigurationUpdater,
        errorMapper: any CoreErrorMapping = RecordingCoreErrorMapper.integrationsSettings(),
        finderOpener: (any RepositoryFinderOpening)? = nil,
        helpOpener: (any ICloudHelpOpening)? = nil,
        iCloudWarn: Bool = true
    ) async -> IntegrationsSettingsModel {
        let model = IntegrationsSettingsModel(
            repoPath: "/tmp/repo",
            loader: RecordingConfigurationLoader(results: [
                .success(.integrationsFixture(repoPath: "/tmp/stale-repo", iCloudWarn: iCloudWarn))
            ]),
            updater: updater,
            errorMapper: errorMapper,
            statusDetector: StaticICloudStatusDetector(
                snapshot: .testFixture()
            ),
            finderOpener: finderOpener ?? RecordingRepositoryFinderOpener(),
            helpOpener: helpOpener ?? RecordingICloudHelpOpener()
        )
        await model.load()
        return model
    }
}

extension AiFallbackStatus {
    static func aiCategorySuggestionAiDisabled() -> AiFallbackStatus {
        aiCategorySuggestionRecoveryStatus(
            kind: .aiDisabled,
            category: .disabled,
            title: "AI classification suggestions are off",
            message: "AI category suggestions are disabled for this repository.",
            retryDisabledReason: "Open AI settings before asking for another suggestion.",
            primaryAction: .openAiSettings
        )
    }

    static func aiCategorySuggestionLocalModelNotReady() -> AiFallbackStatus {
        aiCategorySuggestionRecoveryStatus(
            kind: .localModelNotReady,
            category: .unavailable,
            title: "Local model is not ready",
            message: "The local model cannot create a category suggestion yet.",
            retryDisabledReason: "View local model status before retrying.",
            primaryAction: .openLocalModelStatus
        )
    }

    static func aiCategorySuggestionRemoteNotConfigured() -> AiFallbackStatus {
        aiCategorySuggestionRecoveryStatus(
            kind: .remoteNotConfigured,
            category: .disabled,
            title: "Remote AI is not configured",
            message: "Remote AI must be configured before it can suggest a category.",
            retryDisabledReason: "Configure remote AI before retrying.",
            primaryAction: .configureRemoteAi
        )
    }

    // swiftlint:disable:next function_parameter_count
    static func aiCategorySuggestionRecoveryStatus(
        kind: AiFallbackKind,
        category: AiFallbackCategory,
        title: String,
        message: String,
        retryDisabledReason: String,
        primaryAction: AiFallbackAction
    ) -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: kind,
            category: category,
            title: title,
            message: message,
            retryable: false,
            retryDisabledReason: retryDisabledReason,
            primaryAction: primaryAction,
            secondaryAction: nil,
            nonAiFallbackAction: .classifyManually,
            route: nil,
            callLogId: nil,
            privacyRuleId: nil,
            retryAfter: nil
        )
    }
}

private func temporaryIntegrationsSettingsRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixIntegrationsSettings")
}
