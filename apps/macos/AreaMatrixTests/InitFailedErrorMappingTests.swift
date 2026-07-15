@testable import AreaMatrix
import XCTest

final class InitFailedErrorMappingTests: XCTestCase {
    @MainActor
    func testInitializationFailureMapsCoreErrorAndRetryRerunsStoredDraft() async {
        let validation = RepoPathValidationSnapshot.initFailedAdoptExistingFixture(repoPath: "/tmp/adopt")
        let mapping = CoreErrorMappingSnapshot.initFailedPermissionDeniedFixture(rawContext: "/tmp/adopt")
        let initializer = RecordingRepositoryInitializer(firstError: CoreError.PermissionDenied(path: "/tmp/adopt"))
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let writer = InitFailedRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            pathValidator: StaticRepositoryPathValidator(validation: validation),
            repositoryInitializer: initializer,
            startupRecoverer: StaticStartupRecoverer(),
            scanSessionReader: StaticScanSessionReader(),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/adopt")
        await model.continueFromChoosePath()
        await model.continueFromValidatePath()
        await model.adoptExistingRepositoryFromConfirmInit()

        let retryDraft = RepositoryInitializationDraft(
            validation: validation,
            mode: .adoptExisting,
            scanSession: nil
        )
        await initializer.assertAdoptedRepoPaths(["/tmp/adopt"])
        await errorMapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: "/tmp/adopt")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/adopt", mapping, retryDraft))

        await model.retryFailedInitialization()

        await initializer.assertAdoptedRepoPaths(["/tmp/adopt", "/tmp/adopt"])
        writer.assertSavedRepoPaths(["/tmp/adopt"])
        XCTAssertEqual(model.route, .initializationDone(RepositoryInitializationResult(
            repoPath: "/tmp/adopt",
            mode: .adoptExisting,
            scanSession: nil,
            recoveryReport: nil
        )))
    }

    func testDefaultCoreBridgeMapsPermissionDeniedThroughCoreMappingContract() async {
        let mapping = await CoreBridge().mapCoreError(CoreError.PermissionDenied(path: "/tmp/repo"))

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(mapping.severity, .high)
        XCTAssertEqual(mapping.recoverability, .userActionRequired)
        XCTAssertFalse(mapping.userMessage.isEmpty)
        XCTAssertFalse(mapping.suggestedAction.isEmpty)
        XCTAssertEqual(mapping.rawContext, "/tmp/repo")
    }

    @MainActor
    func testAIPrivacyRulesBlocksRemoteAIWithAISettingsConfigCorePrivacyGateOnly() async {
        let updater = RecordingAISettingsUpdater(result: .success(()))
        let model = AISettingsModel(
            repoPath: "/tmp/aiPrivacyRules",
            loader: StaticAISettingsLoader(
                snapshot: .aiPrivacyRulesRemoteReady(repoPath: "/tmp/aiPrivacyRules")
            ),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.aiPrivacyRulesSettingsConfig()
        )

        await model.load()
        let result = await model.blockRemoteAIWithPrivacyGate()

        XCTAssertEqual(result, .saved)
        await updater.assertRequestCount(1)
        await updater.assertRequestedConfigValue(at: 0, \.privacyGateEnabled, false)
        await updater.assertRequestedConfigValue(at: 0, \.remoteAIAllowed, true)
        await updater.assertRequestedConfigValue(at: 0, \.providerPreference, .remoteFirst)
        await updater.assertRequestedAllowRemoteFeatureCounts([2])
    }

    @MainActor
    func testAIPrivacyRulesAllowRemoteGateRequiresRemoteProviderConfigProviderConsentBeforeSaving() async {
        let updater = RecordingAISettingsUpdater(result: .success(()))
        let model = AISettingsModel(
            repoPath: "/tmp/aiPrivacyRules",
            loader: StaticAISettingsLoader(snapshot: .aiPrivacyRulesDefault(
                repoPath: "/tmp/aiPrivacyRules",
                privacyGateEnabled: false
            )),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.aiPrivacyRulesSettingsConfig()
        )

        await model.load()
        let result = await model.allowRemoteAIAfterProviderConsent()

        XCTAssertEqual(result, .needsRemoteConfiguration)
        await updater.assertNoAISettingsUpdateRequests()
        XCTAssertEqual(model.snapshot?.config.privacyGateEnabled, false)
        XCTAssertEqual(model.actionFeedback, .failed(AISettingsError(
            message: "Remote AI requires provider consent.",
            recovery: "Configure remote AI before allowing the privacy gate.",
            detail: "Remote AI configuration manages provider setup, API key storage, "
                + "connection verification, and remote scope."
        )))
    }

    @MainActor
    func testAIPrivacyRulesPrivacyGateSaveFailureKeepsLastSuccessfulStateAndRetriesSameConfig() async {
        let updater = RecordingAISettingsUpdater(failureThenSuccess: CoreError.Io(
            message: "metadata locked"
        ))
        let model = AISettingsModel(
            repoPath: "/tmp/aiPrivacyRules",
            loader: StaticAISettingsLoader(
                snapshot: .aiPrivacyRulesRemoteReady(repoPath: "/tmp/aiPrivacyRules")
            ),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.aiPrivacyRulesSettingsConfig()
        )

        await model.load()
        let result = await model.blockRemoteAIWithPrivacyGate()

        XCTAssertEqual(result, .failed)
        XCTAssertEqual(model.snapshot?.config.privacyGateEnabled, true)
        XCTAssertEqual(model.saveError?.message, "Remote AI privacy gate could not be updated.")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()

        await updater.assertRequestedConfigValues(\.privacyGateEnabled, [false, false])
        XCTAssertEqual(model.snapshot?.config.privacyGateEnabled, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testInitializationFailureCollectsDiagnosticsWithoutSavingRepositorySelection() async {
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(
            snapshotPath: "/tmp/diagnostics/redacted.zip",
            createdAt: 1_700_000_000,
            warnings: ["paths redacted"]
        )
        let collector = InitFailedRecordingDiagnosticsCollector(result: .success(snapshot))
        let writer = InitFailedRecordingSettingsWriter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            settingsWriter: writer,
            diagnosticsCollector: collector,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationFailed("/Users/example/private-repo", nil, nil)
        await model.collectInitializationDiagnostics()

        await collector.assertRequestedRepoPaths(["/Users/example/private-repo"])
        XCTAssertEqual(model.initializationDiagnostics, .collected(snapshot))
        writer.assertNoSavedRepoPaths()
        XCTAssertEqual(model.route, .initializationFailed("/Users/example/private-repo", nil, nil))
    }

    @MainActor
    func testInitializationDiagnosticsFailureMapsErrorAndStaysOnFailedPage() async {
        let mapping = CoreErrorMappingSnapshot.initFailedPermissionDeniedFixture(rawContext: "/tmp/repo")
        let collector =
            InitFailedRecordingDiagnosticsCollector(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo")))
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .initializationFailed("/tmp/repo", nil, nil)
        await model.collectInitializationDiagnostics()

        XCTAssertEqual(model.initializationDiagnostics, .failed(mapping))
        await errorMapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/repo", nil, nil))
    }

    @MainActor
    func testCancelledInitializationDiagnosticsIgnoresLateCollectorResult() async {
        let collector = SuspendedDiagnosticsCollector(result: .success(.testFixture()))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            diagnosticsCollector: collector,
            helpOpener: NoopWelcomeHelpOpener()
        )
        model.route = .initializationFailed("/tmp/repo", nil, nil)
        model.requestInitializationDiagnosticsPrivacyConfirmation()

        let collection = Task { await model.collectInitializationDiagnostics() }
        await collector.waitUntilStarted()
        model.cancelInitializationDiagnosticsPrivacyConfirmation()
        await collector.finish()
        await collection.value

        XCTAssertEqual(model.initializationDiagnostics, .idle)
    }
}

private typealias InitFailedRecordingSettingsWriter = RecordingAppSettingsWriter

private typealias InitFailedRecordingDiagnosticsCollector = RecordingDiagnosticsCollector

private extension RepoPathValidationSnapshot {
    static func initFailedAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.testFixture(repoPath: repoPath) {
            $0.isEmpty = false
            $0.recommendedMode = .adoptExisting
            $0.issues = [.nonEmptyDirectory]
        }
    }
}

private extension AISettingsSnapshot {
    static func aiPrivacyRulesDefault(repoPath: String, privacyGateEnabled: Bool = true) -> AISettingsSnapshot {
        aiPrivacyRulesSnapshot(config: .aiSettingsConfig(
            repoPath: repoPath,
            privacyGateEnabled: privacyGateEnabled
        ))
    }

    static func aiPrivacyRulesRemoteReady(repoPath: String) -> AISettingsSnapshot {
        aiPrivacyRulesSnapshot(config: .aiSettingsConfig(
            repoPath: repoPath,
            aiEnabled: true,
            providerPreference: .remoteFirst,
            localAIEnabled: true,
            remoteAIAllowed: true,
            privacyGateEnabled: true,
            privacyPolicyRef: "strict-default",
            enabledFeatures: Array(AISettingsFeatureKind.allCases),
            remoteAllowedFeatures: [.autoSummaries, .autoTags]
        ))
    }

    static func aiPrivacyRulesSnapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        AISettingsSnapshot.aiSettingsSnapshot(
            config: config,
            updatedAt: 1_778_000_309
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func initFailedPermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}
