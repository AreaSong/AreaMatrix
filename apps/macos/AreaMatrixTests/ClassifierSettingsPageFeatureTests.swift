@testable import AreaMatrix
import XCTest

private struct ClassifierNoopAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_: String) {}
}

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
    func testPreviewCallsInjectedCoreCategoryPredictorAndClearsStaleResultWhenFilenameChanges() async {
        let predictor = ClassifierSettingsRecordingPredictor(result: .success(ClassifyResultSnapshot(
            category: "finance",
            suggestedName: "Invoice_2026Q1.pdf",
            reason: .keyword,
            confidence: 0.9
        )))
        let model = await loadedModel(
            updater: ClassifierSettingsRecordingUpdater(result: .success),
            predictor: predictor
        )

        model.updatePreviewFilename("Invoice_2026Q1.pdf")
        await model.previewClassification()

        let requests = await predictor.requests()
        XCTAssertEqual(requests, [
            ClassifierSettingsRecordingPredictor.Request(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf")
        ])
        XCTAssertEqual(model.previewResult?.category, "finance")
        XCTAssertEqual(model.previewResult?.suggestedName, "Invoice_2026Q1.pdf")
        XCTAssertEqual(model.previewResult?.reason, .keyword)
        XCTAssertEqual(model.previewResult?.confidencePercent, 90)
        XCTAssertNil(model.previewError)
        XCTAssertFalse(model.isPreviewing)

        model.updatePreviewFilename("Invoice_2026Q2.pdf")

        XCTAssertNil(model.previewResult)
        XCTAssertNil(model.previewError)
        XCTAssertEqual(model.previewFilename, "Invoice_2026Q2.pdf")
    }

    @MainActor
    func testPreviewFailureMapsCoreErrorWithoutStaticSuccessState() async {
        let predictor = ClassifierSettingsRecordingPredictor(
            result: .failure(CoreError.Classify(reason: "classifier unavailable"))
        )
        let model = await loadedModel(
            updater: ClassifierSettingsRecordingUpdater(result: .success),
            predictor: predictor
        )

        model.updatePreviewFilename("Bad.pdf")
        await model.previewClassification()

        let requests = await predictor.requests()
        XCTAssertEqual(requests, [
            ClassifierSettingsRecordingPredictor.Request(repoPath: "/tmp/repo", filename: "Bad.pdf")
        ])
        XCTAssertNil(model.previewResult)
        XCTAssertEqual(model.previewError?.message, "无法预览分类：classifier unavailable")
        XCTAssertEqual(model.previewError?.recovery, "Retry preview")
        XCTAssertFalse(model.isPreviewing)
    }

    @MainActor
    func testOpenClassifierYamlUsesRepositoryFileOpener() async {
        let opener = ClassifierSettingsRecordingFileOpener()
        let model = await loadedModel(
            updater: ClassifierSettingsRecordingUpdater(result: .success),
            fileOpener: opener
        )

        model.openClassifierYaml()

        let expected = ClassifierSettingsRecordingFileOpener.Request(
            repoPath: "/tmp/repo",
            relativePath: ".areamatrix/classifier.yaml"
        )
        XCTAssertEqual(opener.requests(), [expected])
        XCTAssertNil(model.fileActionError)
    }

    @MainActor
    func testValidateClassifierRulesRequiresPhysicalClassifierYamlBeforeCorePreviewFallback() async throws {
        let repoURL = try temporaryClassifierSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let predictor = ClassifierSettingsRecordingPredictor(
            result: .success(classifierSettingsValidationProbeResult())
        )
        let model = await loadedModel(
            updater: ClassifierSettingsRecordingUpdater(result: .success),
            predictor: predictor,
            config: .classifierSettingsFixture(repoPath: repoURL.path)
        )

        let passed = await model.validateClassifierRules()

        XCTAssertFalse(passed)
        XCTAssertEqual(model.validationStatusLabel, "Failed")
        XCTAssertEqual(model.validationError?.message, "分类规则文件不存在")
        let predictorRequests = await predictor.requests()
        XCTAssertEqual(predictorRequests, [])
    }

    @MainActor
    func testRevertToLastValidIsDisabledUntilAValidatedBackupExists() async throws {
        let repoURL = try temporaryClassifierSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try "version: 1\n".write(
            to: metadataURL.appendingPathComponent("classifier.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let loader = ClassifierSettingsRecordingLoader(
            result: .success(.classifierSettingsFixture(repoPath: repoURL.path))
        )
        let predictor = ClassifierSettingsRecordingPredictor(
            result: .success(classifierSettingsValidationProbeResult())
        )
        let model = ClassifierSettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: ClassifierSettingsRecordingUpdater(result: .success),
            predictor: predictor,
            errorMapper: ClassifierSettingsStaticErrorMapper(),
            accessibilityAnnouncer: ClassifierNoopAnnouncer()
        )

        await model.load()
        await model.revertToLastValid()

        let loaderPaths = await loader.requestedPaths()
        let predictorRequests = await predictor.requests()
        XCTAssertEqual(loaderPaths, [repoURL.path])
        XCTAssertEqual(predictorRequests, [])
        XCTAssertFalse(model.canRevertToLastValid)
        XCTAssertEqual(model.validationState, .idle)
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
        let model = ClassifierSettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            errorMapper: bridge
        )

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
    func testDefaultCoreBridgePreviewReadsRealClassifierYamlWithoutWritingFiles() async throws {
        let repoURL = try temporaryClassifierSettingsRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let classifierURL = repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.yaml", isDirectory: false)
        let originalClassifierYAML = try String(contentsOf: classifierURL, encoding: .utf8)
        let model = ClassifierSettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            predictor: bridge,
            errorMapper: bridge
        )

        await model.load()
        model.updatePreviewFilename("Invoice_2026Q1.pdf")
        await model.previewClassification()

        XCTAssertEqual(model.previewResult?.category, "finance")
        XCTAssertEqual(model.previewResult?.reason, .keyword)
        XCTAssertGreaterThan(model.previewResult?.confidence ?? 0, 0)
        XCTAssertNil(model.previewError)
        XCTAssertEqual(try String(contentsOf: classifierURL, encoding: .utf8), originalClassifierYAML)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    private func loadedModel(
        updater: ClassifierSettingsRecordingUpdater,
        predictor: any CoreCategoryPredicting = CoreBridge(),
        config: RepoConfigSnapshot = .classifierSettingsFixture(repoPath: "/tmp/repo"),
        fileOpener: any RepositoryFileOpening = NSWorkspaceRepositoryFileOpener(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = ClassifierNoopAnnouncer()
    ) async -> ClassifierSettingsModel {
        let model = ClassifierSettingsModel(
            repoPath: config.repoPath,
            loader: ClassifierSettingsRecordingLoader(result: .success(config)),
            updater: updater,
            predictor: predictor,
            errorMapper: ClassifierSettingsStaticErrorMapper(),
            fileOpener: fileOpener,
            accessibilityAnnouncer: accessibilityAnnouncer
        )
        await model.load()
        return model
    }
}

private enum ClassifierSettingsLoaderResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

private enum ClassifierSettingsPreviewResult {
    case success(ClassifyResultSnapshot)
    case failure(Error)
}

private actor ClassifierSettingsRecordingPredictor: CoreCategoryPredicting {
    struct Request: Equatable {
        var repoPath: String
        var filename: String
    }

    private let result: ClassifierSettingsPreviewResult
    private var requestsStorage: [Request] = []

    init(result: ClassifierSettingsPreviewResult) {
        self.result = result
    }

    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot {
        requestsStorage.append(Request(repoPath: repoPath, filename: filename))
        switch result {
        case let .success(preview):
            return preview
        case let .failure(error):
            throw error
        }
    }

    func requests() -> [Request] {
        requestsStorage
    }
}

@MainActor
private final class ClassifierSettingsRecordingFileOpener: RepositoryFileOpening {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let error: Error?
    private var requestsStorage: [Request] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func openFile(repoPath: String, relativePath: String) throws {
        requestsStorage.append(Request(repoPath: repoPath, relativePath: relativePath))
        if let error {
            throw error
        }
    }

    func requests() -> [Request] {
        requestsStorage
    }
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
        case let .success(config):
            return config
        case let .failure(error):
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
        case let .failureThenSuccess(error) where requestsStorage.count == 1:
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
            .classifierSettingsMapping(kind: .db, userMessage: "数据库错误")
        case let .Config(reason):
            .classifierSettingsMapping(kind: .config, userMessage: "分类规则无效：\(reason)")
        case let .Classify(reason):
            .classifierSettingsMapping(kind: .classify, userMessage: "无法预览分类：\(reason)")
        case .PermissionDenied:
            .classifierSettingsMapping(kind: .permissionDenied, userMessage: "无访问权限")
        default:
            .classifierSettingsMapping(kind: .internal, userMessage: "保存失败")
        }
    }
}

private func classifierSettingsValidationProbeResult() -> ClassifyResultSnapshot {
    ClassifyResultSnapshot(
        category: "inbox",
        suggestedName: "AreaMatrixValidationProbe.txt",
        reason: .default,
        confidence: 0
    )
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
