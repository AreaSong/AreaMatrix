@testable import AreaMatrix
import Combine
import XCTest

final class ClassifierSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesRepositoryConfigCoreConfigSnapshotForVisibleClassifierSettings() async {
        let loader = RecordingConfigurationLoader(result: .success(.classifierSettingsFixture(
            repoPath: "/tmp/repo",
            enableExtensionRules: false,
            enableKeywordRules: true,
            fallbackToInbox: false
        )))
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = ClassifierSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: updater,
            errorMapper: RecordingCoreErrorMapper.classifierSettings()
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
        let updater = RecordingConfigurationUpdater(result: .success(()))
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
        let updater = RecordingConfigurationUpdater(failureThenSuccess: CoreError.Db(message: "locked"))
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
        let predictor = ClassifierSettingsSequencePredictor(results: [
            .success(ClassifyResultSnapshot(
                category: "finance",
                suggestedName: "Invoice_2026Q1.pdf",
                reason: .keyword,
                confidence: 0.9
            ))
        ])
        let model = await loadedModel(
            updater: RecordingConfigurationUpdater(result: .success(())),
            predictor: predictor
        )

        model.updatePreviewFilename("Invoice_2026Q1.pdf")
        await model.previewClassification()

        let requests = await predictor.requests()
        XCTAssertEqual(requests, [
            ClassifierSettingsSequencePredictor.Request(repoPath: "/tmp/repo", filename: "Invoice_2026Q1.pdf")
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
        let predictor = ClassifierSettingsSequencePredictor(results: [
            .failure(CoreError.Classify(reason: "classifier unavailable"))
        ])
        let model = await loadedModel(
            updater: RecordingConfigurationUpdater(result: .success(())),
            predictor: predictor
        )

        model.updatePreviewFilename("Bad.pdf")
        await model.previewClassification()

        let requests = await predictor.requests()
        XCTAssertEqual(requests, [
            ClassifierSettingsSequencePredictor.Request(repoPath: "/tmp/repo", filename: "Bad.pdf")
        ])
        XCTAssertNil(model.previewResult)
        XCTAssertEqual(model.previewError?.message, "无法预览分类：classifier unavailable")
        XCTAssertEqual(model.previewError?.recovery, "Retry preview")
        XCTAssertFalse(model.isPreviewing)
    }

    @MainActor
    func testPreviewFilenameUpdatePublishesSettingsViewChange() async {
        let model = await loadedModel(updater: RecordingConfigurationUpdater(result: .success(())))
        var publishCount = 0
        let cancellable = model.objectWillChange.sink {
            publishCount += 1
        }
        defer { cancellable.cancel() }

        model.updatePreviewFilename("Invoice_2026Q1.pdf")

        XCTAssertEqual(model.previewFilename, "Invoice_2026Q1.pdf")
        XCTAssertGreaterThanOrEqual(publishCount, 1)
    }

    @MainActor
    func testOpenClassifierYamlUsesRepositoryFileOpener() async {
        let opener = RecordingRepositoryFileOpener()
        let model = await loadedModel(
            updater: RecordingConfigurationUpdater(result: .success(())),
            fileOpener: opener
        )

        model.openClassifierYaml()

        let expected = RecordingRepositoryFileOpener.Request(
            repoPath: "/tmp/repo",
            relativePath: ".areamatrix/classifier.yaml"
        )
        XCTAssertEqual(opener.requests, [expected])
        XCTAssertNil(model.fileActionError)
    }

    @MainActor
    func testValidateClassifierRulesRequiresPhysicalClassifierYamlBeforeCorePreviewFallback() async throws {
        let repoURL = try temporaryClassifierSettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let predictor = ClassifierSettingsSequencePredictor()
        let model = await loadedModel(
            updater: RecordingConfigurationUpdater(result: .success(())),
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
        defer { removeTestTemporaryItems(repoURL) }
        let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
        try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
        try "version: 1\n".write(
            to: metadataURL.appendingPathComponent("classifier.yaml", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        let loader = RecordingConfigurationLoader(
            result: .success(.classifierSettingsFixture(repoPath: repoURL.path))
        )
        let predictor = ClassifierSettingsSequencePredictor()
        let model = ClassifierSettingsModel(
            repoPath: repoURL.path,
            loader: loader,
            updater: RecordingConfigurationUpdater(result: .success(())),
            predictor: predictor,
            errorMapper: RecordingCoreErrorMapper.classifierSettings(),
            accessibilityAnnouncer: NoopAccessibilityAnnouncer()
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
        defer { removeTestTemporaryItems(repoURL) }
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
        defer { removeTestTemporaryItems(repoURL) }
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
        updater: RecordingConfigurationUpdater,
        predictor: any CoreCategoryPredicting = CoreBridge(),
        config: RepoConfigSnapshot = .classifierSettingsFixture(repoPath: "/tmp/repo"),
        fileOpener: any RepositoryFileOpening = NSWorkspaceRepositoryFileOpener(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = NoopAccessibilityAnnouncer()
    ) async -> ClassifierSettingsModel {
        let model = ClassifierSettingsModel(
            repoPath: config.repoPath,
            loader: RecordingConfigurationLoader(result: .success(config)),
            updater: updater,
            predictor: predictor,
            errorMapper: RecordingCoreErrorMapper.classifierSettings(),
            fileOpener: fileOpener,
            accessibilityAnnouncer: accessibilityAnnouncer
        )
        await model.load()
        return model
    }
}

private func temporaryClassifierSettingsRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixClassifierSettings")
}
