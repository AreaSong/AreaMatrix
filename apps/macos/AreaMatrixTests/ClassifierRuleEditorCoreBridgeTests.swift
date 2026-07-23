@testable import AreaMatrix
import XCTest

final class ClassifierRuleEditorCoreBridgeTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testClassifierRuleEditorDefaultCoreBridgePersistsClassifierRuleCrudToClassifierYaml() async throws {
        let repoURL = try temporaryClassifierRuleEditorRepo()
        defer { removeTestTemporaryItems(repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let initial = try await bridge.listClassifierRules(repoPath: repoURL.path)
        XCTAssertTrue(initial.rules.contains { $0.ruleID == "finance" })

        let created = try await bridge.createClassifierRule(
            repoPath: repoURL.path,
            request: ClassifierRuleCreateRequestSnapshot(
                slug: "tax",
                displayName: "Tax",
                description: "Tax documents",
                extensions: ["pdf"],
                keywords: ["tax"],
                priority: 20,
                namingTemplate: "{stem}"
            )
        )
        XCTAssertEqual(created.updatedRuleID, "tax")
        XCTAssertTrue(try classifierYaml(repoURL).contains("slug: tax"))

        let updated = try await bridge.updateClassifierRule(
            repoPath: repoURL.path,
            request: ClassifierRuleUpdateSnapshot(
                ruleID: "tax",
                slug: "tax",
                displayName: "Tax Records",
                description: "Tax documents",
                extensions: ["pdf", "csv"],
                keywords: ["tax", "irs"],
                priority: 30,
                namingTemplate: "{stem}-{date}",
                previewConfirmed: true
            )
        )
        XCTAssertEqual(updated.updatedRuleID, "tax")
        let updatedYaml = try classifierYaml(repoURL)
        XCTAssertTrue(updatedYaml.contains("display_name"))
        XCTAssertTrue(updatedYaml.contains("Tax Records"))
        XCTAssertTrue(updatedYaml.contains("csv"))

        let deleted = try await bridge.deleteClassifierRule(
            repoPath: repoURL.path,
            request: ClassifierRuleDeleteRequestSnapshot(
                ruleID: "tax",
                replacementCategory: "inbox",
                previewConfirmed: true
            )
        )
        XCTAssertEqual(deleted.updatedRuleID, "inbox")
        XCTAssertFalse(try classifierYaml(repoURL).contains("slug: tax"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    func testAISettingsAISettingsModelPersistsAISettingsConfigCoreConfigThroughInjectedCoreBridge() async {
        let updater = RecordingAISettingsUpdater(result: .success(()))
        let model = AISettingsModel(
            repoPath: "/tmp/aiSettings",
            loader: StaticAISettingsLoader(snapshot: .aiSettingsDefault(repoPath: "/tmp/aiSettings")),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.aiSettings()
        )

        await model.load()
        await model.setAIEnabled(true)
        await model.setFeature(.autoSummaries, enabled: true)

        XCTAssertEqual(model.loadState, .loaded)
        await updater.assertRequestCount(2)
        await updater.assertRequestedConfigValue(at: 0, \.aiEnabled, true)
        await updater.assertRequestedFeatureValue(at: 1, feature: .autoSummaries, \.enabled, true)
        XCTAssertEqual(model.snapshot?.capabilities.count, 4)
    }

    @MainActor
    func testAISettingsRemoteFirstRequiresRemoteProviderConfigRemoteSetupBeforeSaving() async {
        let updater = RecordingAISettingsUpdater(result: .success(()))
        let model = AISettingsModel(
            repoPath: "/tmp/aiSettings",
            loader: StaticAISettingsLoader(snapshot: .aiSettingsDefault(repoPath: "/tmp/aiSettings")),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.aiSettings()
        )

        await model.load()
        await model.setProviderPreference(.remoteFirst)

        await updater.assertNoAISettingsUpdateRequests()
        XCTAssertEqual(model.snapshot?.config.providerPreference, .localFirst)
        XCTAssertEqual(model.actionFeedback, .failed(AISettingsError(
            message: L10n.message("Remote AI requires explicit setup."),
            recovery: L10n.message("Use Configure remote AI before selecting Remote first."),
            detail: "Remote AI configuration manages provider setup, API key storage, and connection verification."
        )))
    }

    @MainActor
    func testAISettingsPauseFailureRestoresSavedSnapshotAndKeepsRetry() async {
        let updater = RecordingAISettingsUpdater(failureThenSuccess: CoreError.Io(
            message: "metadata locked"
        ))
        let enabled = AISettingsSnapshot.aiSettingsDefault(repoPath: "/tmp/aiSettings", aiEnabled: true)
        let model = AISettingsModel(
            repoPath: "/tmp/aiSettings",
            loader: StaticAISettingsLoader(snapshot: enabled),
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.aiSettings()
        )

        await model.load()
        await model.pauseAllAI()

        XCTAssertEqual(model.snapshot?.config.aiEnabled, true)
        XCTAssertTrue(model.hasRetryablePause)
        XCTAssertEqual(model.saveError?.message, L10n.message("AI could not be paused."))

        await model.retryPause()

        await updater.assertRequestedConfigValues(\.aiEnabled, [false, false])
        XCTAssertEqual(model.snapshot?.config.aiEnabled, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testAISettingsDefaultCoreBridgePersistsAIConfigWithoutCreatingRootFiles() async throws {
        let repoURL = try temporaryClassifierRuleEditorRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)

        let initial = try await bridge.loadAISettings(repoPath: repoURL.path)
        XCTAssertEqual(initial.config.aiEnabled, false)
        XCTAssertEqual(initial.config.featureToggles.count, 4)

        var config = initial.config
        config.aiEnabled = true
        config.localAIEnabled = true
        config.setFeature(.classificationSuggestions, enabled: true)
        let updated = try await bridge.updateAISettings(repoPath: repoURL.path, newConfig: config)
        let reloaded = try await bridge.loadAISettings(repoPath: repoURL.path)

        XCTAssertEqual(updated.config.aiEnabled, true)
        XCTAssertEqual(reloaded.config.featureToggles.first { $0.feature == .classificationSuggestions }?.enabled, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    func testLocalModelStatusLocalModelStatusModelRefreshesThroughInjectedCoreBridgeReader() async {
        let reader = RecordingLocalModelReader(
            status: .localModelStatusSnapshot(
                storageLocation: "/tmp/localModelStatus-models",
                availability: .notInstalled,
                recommendedAction: .openInstallHelp
            ),
            location: .localModelStatusLocation(folderPath: "/tmp/localModelStatus-models", openable: false)
        )
        let copier = RecordingDiagnosticsCopier()
        let model = LocalModelStatusModel(
            repoPath: "/tmp/localModelStatus",
            storageLocation: "/tmp/localModelStatus-models",
            statusReader: reader,
            installHelpOpener: RecordingInstallHelpOpener(),
            folderOpener: LocalModelStatusRecordingFolderOpener(),
            diagnosticsCopier: copier,
            errorMapper: RecordingCoreErrorMapper.localModelStatus()
        )

        await model.checkStatus()
        model.showDiagnostics()
        model.copyDiagnosticsSummary()

        await reader.assertStatusRequests([RecordingLocalModelReader.StatusRequest(
            repoPath: "/tmp/localModelStatus",
            request: LocalModelStatusRequestState(
                modelID: LocalModelStatusModel.defaultModelID,
                storageLocation: "/tmp/localModelStatus-models"
            )
        )])
        XCTAssertEqual(model.snapshot?.availability, .notInstalled)
        XCTAssertEqual(model.statusText, "Status: Not installed")
        copier.assertCopiedSummaries(["manifest: missing; runtime: unavailable"])
    }

    @MainActor
    func testLocalModelStatusOpenModelLocationUsesCoreLocationWithoutFallbackPath() async {
        let reader = RecordingLocalModelReader(
            status: .localModelStatusSnapshot(
                storageLocation: "/tmp/localModelStatus-models",
                availability: .ready,
                recommendedAction: .openModelLocation
            ),
            location: .localModelStatusLocation(folderPath: "/tmp/localModelStatus-models", openable: true)
        )
        let folderOpener = LocalModelStatusRecordingFolderOpener()
        let model = LocalModelStatusModel(
            repoPath: "/tmp/localModelStatus",
            storageLocation: "/tmp/localModelStatus-models",
            statusReader: reader,
            installHelpOpener: RecordingInstallHelpOpener(),
            folderOpener: folderOpener,
            diagnosticsCopier: RecordingDiagnosticsCopier(),
            errorMapper: RecordingCoreErrorMapper.localModelStatus()
        )

        await model.checkStatus()
        await model.openModelLocation()

        await reader.assertFolderRequests([RecordingLocalModelReader.FolderRequest(
            repoPath: "/tmp/localModelStatus",
            request: LocalModelFolderRequestState(
                modelID: LocalModelStatusModel.defaultModelID,
                storageLocation: "/tmp/localModelStatus-models"
            )
        )])
        folderOpener.assertOpenedFolderPaths(["/tmp/localModelStatus-models"])
        XCTAssertEqual(model.feedback, .success(L10n.message("Model location opened.")))
    }

    @MainActor
    func testLocalModelStatusUsesInjectedStorageLocationProviderWhenNoOverrideIsPassed() {
        let provider = RecordingLocalModelStorageProvider(defaultLocation: "/tmp/localModelStatus-provider")
        let explicitModel = LocalModelStatusModel(
            repoPath: "/tmp/localModelStatus",
            storageLocation: "/tmp/localModelStatus-explicit",
            storageLocationProvider: provider,
            statusReader: RecordingLocalModelReader(
                status: .localModelStatusSnapshot(
                    storageLocation: "/tmp/localModelStatus-explicit",
                    availability: .ready,
                    recommendedAction: .none
                ),
                location: .localModelStatusLocation(folderPath: "/tmp/localModelStatus-explicit", openable: true)
            ),
            installHelpOpener: RecordingInstallHelpOpener(),
            folderOpener: LocalModelStatusRecordingFolderOpener(),
            diagnosticsCopier: RecordingDiagnosticsCopier(),
            errorMapper: RecordingCoreErrorMapper.localModelStatus()
        )
        let defaultedModel = LocalModelStatusModel(
            repoPath: "/tmp/localModelStatus",
            storageLocationProvider: provider,
            statusReader: RecordingLocalModelReader(
                status: .localModelStatusSnapshot(
                    storageLocation: "/tmp/localModelStatus-provider",
                    availability: .ready,
                    recommendedAction: .none
                ),
                location: .localModelStatusLocation(folderPath: "/tmp/localModelStatus-provider", openable: true)
            ),
            installHelpOpener: RecordingInstallHelpOpener(),
            folderOpener: LocalModelStatusRecordingFolderOpener(),
            diagnosticsCopier: RecordingDiagnosticsCopier(),
            errorMapper: RecordingCoreErrorMapper.localModelStatus()
        )

        XCTAssertEqual(explicitModel.storageLocation, "/tmp/localModelStatus-explicit")
        XCTAssertEqual(defaultedModel.storageLocation, "/tmp/localModelStatus-provider")
        provider.assertRequestCount(1)
    }

    @MainActor
    func testLocalModelStatusDefaultCoreBridgeReadsLocalModelStatusWithoutCreatingModelFolder() async throws {
        let repoURL = try temporaryClassifierRuleEditorRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let modelURL = repoURL.appendingPathComponent("Models/areamatrix-local-classifier", isDirectory: true)
        let request = LocalModelStatusRequestState(
            modelID: LocalModelStatusModel.defaultModelID,
            storageLocation: modelURL.path,
            cachedStatus: nil
        )

        let status = try await bridge.getLocalModelStatus(repoPath: repoURL.path, request: request)
        let location = try await bridge.locateLocalModelFolder(
            repoPath: repoURL.path,
            request: LocalModelFolderRequestState(
                modelID: LocalModelStatusModel.defaultModelID,
                storageLocation: modelURL.path
            )
        )

        XCTAssertEqual(status.modelID, LocalModelStatusModel.defaultModelID)
        XCTAssertEqual(status.storageLocation, modelURL.path)
        XCTAssertEqual(status.availability, .notInstalled)
        XCTAssertEqual(status.recommendedAction, .openInstallHelp)
        XCTAssertFalse(location.exists)
        XCTAssertFalse(location.openable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
    }
}
