@testable import AreaMatrix
import XCTest

final class ClassifierRuleEditorCoreBridgeTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testS219DefaultCoreBridgePersistsClassifierRuleCrudToClassifierYaml() async throws {
        let repoURL = try temporaryS219Repo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

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
    func testS301AISettingsModelPersistsC301ConfigThroughInjectedCoreBridge() async {
        let updater = S301RecordingAISettingsUpdater(result: .success)
        let model = AISettingsModel(
            repoPath: "/tmp/s301",
            loader: S301StaticAISettingsLoader(snapshot: .s301Default(repoPath: "/tmp/s301")),
            updater: updater,
            errorMapper: S301StaticAIErrorMapper()
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
    func testS301RemoteFirstRequiresS303RemoteSetupBeforeSaving() async {
        let updater = S301RecordingAISettingsUpdater(result: .success)
        let model = AISettingsModel(
            repoPath: "/tmp/s301",
            loader: S301StaticAISettingsLoader(snapshot: .s301Default(repoPath: "/tmp/s301")),
            updater: updater,
            errorMapper: S301StaticAIErrorMapper()
        )

        await model.load()
        await model.setProviderPreference(.remoteFirst)
        let requests = await updater.requests()

        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.snapshot?.config.providerPreference, .localFirst)
        XCTAssertEqual(model.actionFeedback, .failed(AISettingsError(
            message: "Remote AI requires explicit setup.",
            recovery: "Use Configure remote AI before selecting Remote first.",
            detail: "S3-03 owns provider setup, API key storage, and connection verification."
        )))
    }

    @MainActor
    func testS301PauseFailureRestoresSavedSnapshotAndKeepsRetry() async {
        let updater = S301RecordingAISettingsUpdater(result: .failureThenSuccess(CoreError.Io(
            message: "metadata locked"
        )))
        let enabled = AISettingsSnapshot.s301Default(repoPath: "/tmp/s301", aiEnabled: true)
        let model = AISettingsModel(
            repoPath: "/tmp/s301",
            loader: S301StaticAISettingsLoader(snapshot: enabled),
            updater: updater,
            errorMapper: S301StaticAIErrorMapper()
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
    func testS301DefaultCoreBridgePersistsAIConfigWithoutCreatingRootFiles() async throws {
        let repoURL = try temporaryS219Repo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
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
    func testS302LocalModelStatusModelRefreshesThroughInjectedCoreBridgeReader() async {
        let reader = S302RecordingLocalModelStatusReader(
            status: .s302Snapshot(
                storageLocation: "/tmp/s302-models",
                availability: .notInstalled,
                recommendedAction: .openInstallHelp
            ),
            location: .s302Location(folderPath: "/tmp/s302-models", openable: false)
        )
        let copier = S302RecordingDiagnosticsCopier()
        let model = LocalModelStatusModel(
            repoPath: "/tmp/s302",
            storageLocation: "/tmp/s302-models",
            statusReader: reader,
            installHelpOpener: S302RecordingInstallHelpOpener(),
            folderOpener: S302RecordingFolderOpener(),
            diagnosticsCopier: copier,
            errorMapper: S302StaticErrorMapper()
        )

        await model.checkStatus()
        model.showDiagnostics()
        model.copyDiagnosticsSummary()
        let requests = await reader.statusRequests()

        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/s302"])
        XCTAssertEqual(requests.first?.request.modelID, LocalModelStatusModel.defaultModelID)
        XCTAssertEqual(requests.first?.request.storageLocation, "/tmp/s302-models")
        XCTAssertEqual(model.snapshot?.availability, .notInstalled)
        XCTAssertEqual(model.statusText, "Status: Not installed")
        XCTAssertEqual(copier.summaries, ["manifest: missing; runtime: unavailable"])
    }

    @MainActor
    func testS302OpenModelLocationUsesC302LocationResultWithoutCreatingFallbackPath() async {
        let reader = S302RecordingLocalModelStatusReader(
            status: .s302Snapshot(
                storageLocation: "/tmp/s302-models",
                availability: .ready,
                recommendedAction: .openModelLocation
            ),
            location: .s302Location(folderPath: "/tmp/s302-models", openable: true)
        )
        let folderOpener = S302RecordingFolderOpener()
        let model = LocalModelStatusModel(
            repoPath: "/tmp/s302",
            storageLocation: "/tmp/s302-models",
            statusReader: reader,
            installHelpOpener: S302RecordingInstallHelpOpener(),
            folderOpener: folderOpener,
            diagnosticsCopier: S302RecordingDiagnosticsCopier(),
            errorMapper: S302StaticErrorMapper()
        )

        await model.checkStatus()
        await model.openModelLocation()
        let folderRequests = await reader.folderRequests()

        XCTAssertEqual(folderRequests.map(\.repoPath), ["/tmp/s302"])
        XCTAssertEqual(folderRequests.first?.request.storageLocation, "/tmp/s302-models")
        XCTAssertEqual(folderOpener.locations.map(\.folderPath), ["/tmp/s302-models"])
        XCTAssertEqual(model.feedback, .success("Model location opened."))
    }

    @MainActor
    func testS302DefaultCoreBridgeReadsLocalModelStatusWithoutCreatingModelFolder() async throws {
        let repoURL = try temporaryS219Repo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
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

private actor S301StaticAISettingsLoader: CoreAISettingsLoading {
    let snapshot: AISettingsSnapshot

    init(snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }

    func loadAISettings(repoPath _: String) async throws -> AISettingsSnapshot {
        snapshot
    }
}

private enum S301UpdateResult {
    case success
    case failureThenSuccess(Error)
}

private actor S301RecordingAISettingsUpdater: CoreAISettingsUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: AISettingsConfigSnapshot
    }

    private let result: S301UpdateResult
    private var recordedRequests: [Request] = []

    init(result: S301UpdateResult) {
        self.result = result
    }

    func updateAISettings(repoPath: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recordedRequests.append(Request(repoPath: repoPath, config: normalized))
        switch result {
        case .success:
            return AISettingsSnapshot.s301Snapshot(config: normalized)
        case let .failureThenSuccess(error) where recordedRequests.count == 1:
            throw error
        case .failureThenSuccess:
            return AISettingsSnapshot.s301Snapshot(config: normalized)
        }
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private actor S301StaticAIErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: String(describing: error),
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: "S3-01"
        )
    }
}

private actor S302RecordingLocalModelStatusReader: CoreLocalModelStatusReading {
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

private struct S302StaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: String(describing: error),
            severity: .medium,
            suggestedAction: "Retry status check",
            recoverability: .retryable,
            rawContext: "S3-02"
        )
    }
}

@MainActor
private final class S302RecordingInstallHelpOpener: LocalModelInstallHelpOpening {
    private(set) var openCount = 0

    func openLocalModelInstallHelp() throws {
        openCount += 1
    }
}

@MainActor
private final class S302RecordingFolderOpener: LocalModelFolderOpening {
    private(set) var locations: [LocalModelFolderLocationState] = []

    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws {
        locations.append(location)
    }
}

@MainActor
private final class S302RecordingDiagnosticsCopier: LocalModelDiagnosticsCopying {
    private(set) var summaries: [String] = []

    func copyLocalModelDiagnostics(_ summary: String) throws {
        summaries.append(summary)
    }
}

private extension AISettingsSnapshot {
    static func s301Default(repoPath: String, aiEnabled: Bool = false) -> AISettingsSnapshot {
        s301Snapshot(config: AISettingsConfigSnapshot(
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

    static func s301Snapshot(config: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = config.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 1_778_000_000
        )
    }
}

private extension LocalModelStatusState {
    static func s302Snapshot(
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
    static func s302Location(folderPath: String, openable: Bool) -> LocalModelFolderLocationState {
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

private func temporaryS219Repo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS219-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func classifierYaml(_ repoURL: URL) throws -> String {
    let url = repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
    return try String(contentsOf: url, encoding: .utf8)
}
