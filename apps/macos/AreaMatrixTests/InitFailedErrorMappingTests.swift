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
        let firstAdoptRequests = await initializer.adoptRequests()
        XCTAssertEqual(firstAdoptRequests, ["/tmp/adopt"])
        let mappedErrors = await errorMapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/adopt")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/adopt", mapping, retryDraft))

        await model.retryFailedInitialization()

        let retriedAdoptRequests = await initializer.adoptRequests()
        XCTAssertEqual(retriedAdoptRequests, ["/tmp/adopt", "/tmp/adopt"])
        XCTAssertEqual(writer.savedRepoPaths, ["/tmp/adopt"])
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
        let requests = await updater.requests()

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].config.privacyGateEnabled, false)
        XCTAssertEqual(requests[0].config.remoteAIAllowed, true)
        XCTAssertEqual(requests[0].config.providerPreference, .remoteFirst)
        XCTAssertEqual(requests[0].config.featureToggles.filter(\.allowRemote).count, 2)
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
        let requests = await updater.requests()

        XCTAssertEqual(result, .needsRemoteConfiguration)
        XCTAssertEqual(requests, [])
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
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.config.privacyGateEnabled), [false, false])
        XCTAssertEqual(model.snapshot?.config.privacyGateEnabled, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testInitializationFailureCollectsDiagnosticsWithoutSavingRepositorySelection() async {
        let snapshot = DiagnosticsSnapshotSnapshot(
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

        let requestedRepoPaths = await collector.requestedRepoPaths()
        XCTAssertEqual(requestedRepoPaths, ["/Users/example/private-repo"])
        XCTAssertEqual(model.initializationDiagnostics, .collected(snapshot))
        XCTAssertEqual(writer.savedRepoPaths, [])
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
        let mappedErrors = await errorMapper.recordedErrors()
        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.route, .initializationFailed("/tmp/repo", nil, nil))
    }
}

private typealias InitFailedRecordingSettingsWriter = RecordingAppSettingsWriter

private typealias InitFailedRecordingDiagnosticsCollector = RecordingDiagnosticsCollector

private extension RepoPathValidationSnapshot {
    static func initFailedAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: false,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 1_073_741_824,
            isExternalVolume: false,
            recommendedMode: .adoptExisting,
            issues: [.nonEmptyDirectory]
        )
    }
}

private extension AISettingsSnapshot {
    static func aiPrivacyRulesDefault(repoPath: String, privacyGateEnabled: Bool = true) -> AISettingsSnapshot {
        aiPrivacyRulesSnapshot(config: AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: false,
            providerPreference: .localFirst,
            localAIEnabled: false,
            remoteAIAllowed: false,
            privacyGateEnabled: privacyGateEnabled,
            privacyPolicyRef: nil,
            featureToggles: AISettingsFeatureKind.allCases.map {
                AISettingsFeatureConfigSnapshot(feature: $0, enabled: false, allowRemote: false)
            }
        ))
    }

    static func aiPrivacyRulesRemoteReady(repoPath: String) -> AISettingsSnapshot {
        aiPrivacyRulesSnapshot(config: AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: true,
            providerPreference: .remoteFirst,
            localAIEnabled: true,
            remoteAIAllowed: true,
            privacyGateEnabled: true,
            privacyPolicyRef: "strict-default",
            featureToggles: AISettingsFeatureKind.allCases.map {
                AISettingsFeatureConfigSnapshot(
                    feature: $0,
                    enabled: true,
                    allowRemote: $0 == .autoSummaries || $0 == .autoTags
                )
            }
        ))
    }

    static func aiPrivacyRulesSnapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 1_778_000_309
        )
    }
}

private extension CoreErrorMappingSnapshot {
    static func initFailedPermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}
