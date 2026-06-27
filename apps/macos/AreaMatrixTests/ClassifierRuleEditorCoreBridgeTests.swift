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
        let updater = AISettingsRecordingAISettingsUpdater(result: .success)
        let model = AISettingsModel(
            repoPath: "/tmp/aiSettings",
            loader: AISettingsStaticAISettingsLoader(snapshot: .aiSettingsDefault(repoPath: "/tmp/aiSettings")),
            updater: updater,
            errorMapper: AISettingsStaticAIErrorMapper()
        )

        await model.load()
        await model.setAIEnabled(true)
        await model.setFeature(.autoSummaries, enabled: true)
        let requests = await updater.requests()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].config.aiEnabled, true)
        XCTAssertEqual(requests[1].config.featureToggles.first { $0.feature == .autoSummaries }?.enabled, true)
        XCTAssertEqual(model.snapshot?.capabilities.count, 4)
    }

    @MainActor
    func testAISettingsRemoteFirstRequiresRemoteProviderConfigRemoteSetupBeforeSaving() async {
        let updater = AISettingsRecordingAISettingsUpdater(result: .success)
        let model = AISettingsModel(
            repoPath: "/tmp/aiSettings",
            loader: AISettingsStaticAISettingsLoader(snapshot: .aiSettingsDefault(repoPath: "/tmp/aiSettings")),
            updater: updater,
            errorMapper: AISettingsStaticAIErrorMapper()
        )

        await model.load()
        await model.setProviderPreference(.remoteFirst)
        let requests = await updater.requests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.snapshot?.config.providerPreference, .localFirst)
        XCTAssertEqual(model.actionFeedback, .failed(AISettingsError(
            message: "Remote AI requires explicit setup.",
            recovery: "Use Configure remote AI before selecting Remote first.",
            detail: "remote-provider-config owns provider setup, API key storage, and connection verification."
        )))
    }

    @MainActor
    func testAISettingsPauseFailureRestoresSavedSnapshotAndKeepsRetry() async {
        let updater = AISettingsRecordingAISettingsUpdater(result: .failureThenSuccess(CoreError.Io(
            message: "metadata locked"
        )))
        let enabled = AISettingsSnapshot.aiSettingsDefault(repoPath: "/tmp/aiSettings", aiEnabled: true)
        let model = AISettingsModel(
            repoPath: "/tmp/aiSettings",
            loader: AISettingsStaticAISettingsLoader(snapshot: enabled),
            updater: updater,
            errorMapper: AISettingsStaticAIErrorMapper()
        )

        await model.load()
        await model.pauseAllAI()

        XCTAssertEqual(model.snapshot?.config.aiEnabled, true)
        XCTAssertTrue(model.hasRetryablePause)
        XCTAssertEqual(model.saveError?.message, "AI could not be paused.")

        await model.retryPause()
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.config.aiEnabled), [false, false])
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
            errorMapper: LocalModelStatusStaticErrorMapper()
        )

        await model.checkStatus()
        model.showDiagnostics()
        model.copyDiagnosticsSummary()
        let requests = await reader.statusRequests()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/localModelStatus"])
        XCTAssertEqual(requests.first?.request.modelID, LocalModelStatusModel.defaultModelID)
        XCTAssertEqual(requests.first?.request.storageLocation, "/tmp/localModelStatus-models")
        XCTAssertEqual(model.snapshot?.availability, .notInstalled)
        XCTAssertEqual(model.statusText, "Status: Not installed")
        XCTAssertEqual(copier.summaries, ["manifest: missing; runtime: unavailable"])
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
            errorMapper: LocalModelStatusStaticErrorMapper()
        )

        await model.checkStatus()
        await model.openModelLocation()
        let folderRequests = await reader.folderRequests()

        XCTAssertEqual(folderRequests.map(\.repoPath), ["/tmp/localModelStatus"])
        XCTAssertEqual(folderRequests.first?.request.storageLocation, "/tmp/localModelStatus-models")
        XCTAssertEqual(folderOpener.locations.map(\.folderPath), ["/tmp/localModelStatus-models"])
        XCTAssertEqual(model.feedback, .success("Model location opened."))
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

private actor AISettingsStaticAISettingsLoader: CoreAISettingsLoading {
    let snapshot: AISettingsSnapshot

    init(snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }

    func loadAISettings(repoPath _: String) async throws -> AISettingsSnapshot {
        snapshot
    }
}

private enum AISettingsUpdateResult {
    case success
    case failureThenSuccess(Error)
}

private actor AISettingsRecordingAISettingsUpdater: CoreAISettingsUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: AISettingsConfigSnapshot
    }

    private let result: AISettingsUpdateResult
    private var recordedRequests: [Request] = []

    init(result: AISettingsUpdateResult) {
        self.result = result
    }

    func updateAISettings(repoPath: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recordedRequests.append(Request(repoPath: repoPath, config: normalized))
        switch result {
        case .success:
            return AISettingsSnapshot.aiSettingsSnapshot(config: normalized)
        case let .failureThenSuccess(error) where recordedRequests.count == 1:
            throw error
        case .failureThenSuccess:
            return AISettingsSnapshot.aiSettingsSnapshot(config: normalized)
        }
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private actor AISettingsStaticAIErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: String(describing: error),
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: "ai-settings"
        )
    }
}

private actor RecordingLocalModelReader: CoreLocalModelStatusReading {
    struct StatusRequest: Equatable {
        var repoPath: String
        var request: LocalModelStatusRequestState
    }

    struct FolderRequest: Equatable {
        var repoPath: String
        var request: LocalModelFolderRequestState
    }

    private let status: LocalModelStatusState
    private let location: LocalModelFolderLocationState
    private var recordedStatusRequests: [StatusRequest] = []
    private var recordedFolderRequests: [FolderRequest] = []

    init(status: LocalModelStatusState, location: LocalModelFolderLocationState) {
        self.status = status
        self.location = location
    }

    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        recordedStatusRequests.append(StatusRequest(repoPath: repoPath, request: request))
        return status
    }

    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        recordedFolderRequests.append(FolderRequest(repoPath: repoPath, request: request))
        return location
    }

    func statusRequests() -> [StatusRequest] {
        recordedStatusRequests
    }

    func folderRequests() -> [FolderRequest] {
        recordedFolderRequests
    }
}

private struct LocalModelStatusStaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: String(describing: error),
            severity: .medium,
            suggestedAction: "Retry status check",
            recoverability: .retryable,
            rawContext: "local-model-status"
        )
    }
}

@MainActor
private final class RecordingInstallHelpOpener: LocalModelInstallHelpOpening {
    private(set) var openCount = 0

    func openLocalModelInstallHelp() throws {
        openCount += 1
    }
}

@MainActor
private final class LocalModelStatusRecordingFolderOpener: LocalModelFolderOpening {
    private(set) var locations: [LocalModelFolderLocationState] = []

    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws {
        locations.append(location)
    }
}

@MainActor
private final class RecordingDiagnosticsCopier: LocalModelDiagnosticsCopying {
    private(set) var summaries: [String] = []

    func copyLocalModelDiagnostics(_ summary: String) throws {
        summaries.append(summary)
    }
}

private extension AISettingsSnapshot {
    static func aiSettingsDefault(repoPath: String, aiEnabled: Bool = false) -> AISettingsSnapshot {
        aiSettingsSnapshot(config: AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: aiEnabled,
            providerPreference: .localFirst,
            localAIEnabled: false,
            remoteAIAllowed: false,
            privacyGateEnabled: true,
            privacyPolicyRef: nil,
            featureToggles: AISettingsFeatureKind.allCases.map {
                AISettingsFeatureConfigSnapshot(feature: $0, enabled: false, allowRemote: false)
            }
        ))
    }

    static func aiSettingsSnapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 1_778_000_000
        )
    }
}

private extension LocalModelStatusState {
    static func localModelStatusSnapshot(
        storageLocation: String,
        availability: LocalModelAvailabilityState,
        recommendedAction: LocalModelRecommendedActionState
    ) -> LocalModelStatusState {
        LocalModelStatusState(
            modelID: LocalModelStatusModel.defaultModelID,
            storageLocation: storageLocation,
            availability: availability,
            version: nil,
            sizeBytes: nil,
            lastError: availability == .ready ? nil : "Model is not installed",
            recommendedAction: recommendedAction,
            lastCheckedAt: 1_778_000_052,
            diagnosticsSummary: "manifest: missing; runtime: unavailable",
            featureStatuses: [
                LocalModelFeatureStatusState(
                    feature: .classificationSuggestions,
                    available: availability == .ready,
                    unavailableReason: availability == .ready ? nil : "Local model unavailable"
                )
            ]
        )
    }
}

private extension LocalModelFolderLocationState {
    static func localModelStatusLocation(folderPath: String, openable: Bool) -> LocalModelFolderLocationState {
        LocalModelFolderLocationState(
            modelID: LocalModelStatusModel.defaultModelID,
            folderPath: folderPath,
            exists: openable,
            readable: openable,
            openable: openable,
            unavailableReason: openable ? nil : "The folder is not available."
        )
    }
}

private func temporaryClassifierRuleEditorRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixClassifierRuleEditor")
}

private func classifierYaml(_ repoURL: URL) throws -> String {
    let url = repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
    return try String(contentsOf: url, encoding: .utf8)
}
