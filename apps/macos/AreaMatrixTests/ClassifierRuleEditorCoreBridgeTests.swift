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
