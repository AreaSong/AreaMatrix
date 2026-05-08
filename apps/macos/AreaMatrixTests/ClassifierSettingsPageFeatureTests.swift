import XCTest
@testable import AreaMatrix

final class ClassifierSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesC104ConfigSnapshotForVisibleClassifierSettings() async {
        let loader = ClassifierSettingsRecordingLoader(result: .success(.classifierSettingsFixture(
            repoPath: "/tmp/repo",
            enableExtensionRules: false,
            enableKeywordRules: true,
            fallbackToInbox: false
        )))
        let updater = ClassifierSettingsRecordingUpdater(result: .success)
        let model = ClassifierSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: updater,
            errorMapper: ClassifierSettingsStaticErrorMapper()
        )

        await model.load()

        let requestedPaths = await loader.requestedPaths()
        XCTAssertEqual(requestedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.classifierConfigPath, "/tmp/repo/.areamatrix/classifier.yaml")
        XCTAssertEqual(model.draft?.enableExtensionRules, false)
        XCTAssertEqual(model.draft?.enableKeywordRules, true)
        XCTAssertEqual(model.draft?.fallbackToInbox, false)
    }

    @MainActor
    func testToggleSaveThroughUpdateConfigWithoutMockState() async {
        let updater = ClassifierSettingsRecordingUpdater(result: .success)
        let model = await loadedModel(updater: updater)

        await model.requestEnableExtensionRules(false)
        await model.requestEnableKeywordRules(false)
        await model.requestFallbackToInbox(false)

        let requests = await updater.requests()
        XCTAssertEqual(requests.map(\.repoPath), ["/tmp/repo", "/tmp/repo", "/tmp/repo"])
        XCTAssertEqual(requests.map(\.config.enableExtensionRules), [false, false, false])
        XCTAssertEqual(requests.map(\.config.enableKeywordRules), [true, false, false])
        XCTAssertEqual(requests.map(\.config.fallbackToInbox), [true, true, false])
        XCTAssertEqual(model.draft?.enableExtensionRules, false)
        XCTAssertEqual(model.draft?.enableKeywordRules, false)
        XCTAssertEqual(model.draft?.fallbackToInbox, false)
    }

    @MainActor
    func testSaveFailureRollsBackToLastSavedValueAndRetryUsesSameCoreConfig() async {
        let updater = ClassifierSettingsRecordingUpdater(result: .failureThenSuccess(CoreError.Db(message: "locked")))
        let model = await loadedModel(updater: updater)

        await model.requestFallbackToInbox(false)

        XCTAssertEqual(model.draft?.fallbackToInbox, true)
        XCTAssertEqual(model.saveError?.message, "数据库错误")
        XCTAssertEqual(model.saveError?.recovery, "Retry save")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()
        let requests = await updater.requests()

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.config.fallbackToInbox), [false, false])
        XCTAssertEqual(model.draft?.fallbackToInbox, false)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testDefaultCoreBridgeUpdatesRealClassifierConfigWithoutCreatingClassifierYaml() async throws {
        let repoURL = try temporaryClassifierSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let classifierURL = repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.yaml", isDirectory: false)
        let originalClassifierYAML = try String(contentsOf: classifierURL, encoding: .utf8)
        let model = ClassifierSettingsModel(repoPath: repoURL.path, loader: bridge, updater: bridge, errorMapper: bridge)

        await model.load()
        await model.requestEnableExtensionRules(false)
        await model.requestEnableKeywordRules(false)
        await model.requestFallbackToInbox(false)

        let reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.enableExtensionRules, false)
        XCTAssertEqual(reloaded.enableKeywordRules, false)
        XCTAssertEqual(reloaded.fallbackToInbox, false)
        XCTAssertEqual(try String(contentsOf: classifierURL, encoding: .utf8), originalClassifierYAML)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    private func loadedModel(
        updater: ClassifierSettingsRecordingUpdater,
        config: RepoConfigSnapshot = .classifierSettingsFixture(repoPath: "/tmp/repo")
    ) async -> ClassifierSettingsModel {
        let model = ClassifierSettingsModel(
            repoPath: config.repoPath,
            loader: ClassifierSettingsRecordingLoader(result: .success(config)),
            updater: updater,
            errorMapper: ClassifierSettingsStaticErrorMapper()
        )
        await model.load()
        return model
    }
}

private enum ClassifierSettingsLoaderResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private actor ClassifierSettingsRecordingLoader: CoreConfigurationLoading {
    private let result: ClassifierSettingsLoaderResult
    private var paths: [String] = []

    init(result: ClassifierSettingsLoaderResult) {
        self.result = result
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        switch result {
        case .success(let config):
            return config
        case .failure(let error):
            throw error
        }
    }

    func requestedPaths() -> [String] {
        paths
    }
}

private enum ClassifierSettingsUpdateResult {
    case success
    case failureThenSuccess(Error)
}

private actor ClassifierSettingsRecordingUpdater: CoreConfigurationUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private let result: ClassifierSettingsUpdateResult
    private var requestsStorage: [Request] = []

    init(result: ClassifierSettingsUpdateResult) {
        self.result = result
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        requestsStorage.append(Request(repoPath: repoPath, config: newConfig))
        switch result {
        case .success:
            return
        case .failureThenSuccess(let error) where requestsStorage.count == 1:
            throw error
        case .failureThenSuccess:
            return
        }
    }

    func requests() -> [Request] {
        requestsStorage
    }
}

private actor ClassifierSettingsStaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Db:
            return .classifierSettingsMapping(kind: .db, userMessage: "数据库错误")
        case .Config:
            return .classifierSettingsMapping(kind: .config, userMessage: "配置错误")
        case .PermissionDenied:
            return .classifierSettingsMapping(kind: .permissionDenied, userMessage: "无访问权限")
        default:
            return .classifierSettingsMapping(kind: .internal, userMessage: "保存失败")
        }
    }
}

private extension CoreErrorMappingSnapshot {
    static func classifierSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: kind.rawValue
        )
    }
}

private extension RepoConfigSnapshot {
    static func classifierSettingsFixture(
        repoPath: String,
        enableExtensionRules: Bool = true,
        enableKeywordRules: Bool = true,
        fallbackToInbox: Bool = true
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: enableExtensionRules,
            enableKeywordRules: enableKeywordRules,
            fallbackToInbox: fallbackToInbox,
            allowReplaceDuringImport: false
        )
    }
}

private func temporaryClassifierSettingsRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixClassifierSettings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
