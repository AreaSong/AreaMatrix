@testable import AreaMatrix
import XCTest

final class GeneralSettingsIntegrationTests: XCTestCase {
    @MainActor
    func testGeneralSettingsPageIntegrationConnectsAllDeclaredCapabilitiesAndExitsBackToMain() async {
        let initialOpening = RepositoryOpeningResult.generalSettingsIntegrationFixture(
            repoPath: "/tmp/repo",
            defaultMode: "Copied"
        )
        let refreshedOpening = RepositoryOpeningResult.generalSettingsIntegrationFixture(
            repoPath: "/tmp/repo",
            defaultMode: "Moved"
        )
        let opener = GeneralSettingsRecordingRepositoryOpener(opening: refreshedOpening)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: opener,
            accessibilityAnnouncer: NoopAccessibilityAnnouncer(),
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.route = .mainList(initialOpening)
        model.showGeneralSettings(opening: initialOpening)
        XCTAssertEqual(model.route, .settingsGeneral(initialOpening))

        await model.refreshAfterGeneralSettings(opening: initialOpening)
        let refreshedPaths = await opener.requestedRepoPaths()

        XCTAssertEqual(refreshedPaths, ["/tmp/repo"])
        XCTAssertEqual(model.route, .mainList(refreshedOpening))
        model.startImportEntry(
            opening: refreshedOpening,
            source: .filePicker,
            urls: [URL(fileURLWithPath: "/tmp/source.pdf")]
        )
        XCTAssertEqual(model.pendingImportEntry?.defaultStorageMode, .move)
    }

    @MainActor
    func testGeneralSettingsPageIntegrationCoversConfigMoveOverviewIgnoreRulesAndFailureRecovery() async throws {
        let (repoURL, sourceURL) = try makeGeneralSettingsIntegrationRepositoryFixture()
        defer { removeTestTemporaryItems(repoURL) }

        let updater = GeneralSettingsIntegrationUpdater(results: [
            .success,
            .success,
            .failure(CoreError.Config(reason: "locked")),
            .success
        ])
        let ignoreRulesManager = RecordingIgnoreRulesManager(openResult: .missingThenSuccess)
        let model = GeneralSettingsModel(
            repoPath: repoURL.path,
            loader: GeneralSettingsStaticConfigLoader(config: RepoConfigSnapshot
                .generalSettingsIntegrationFixture(repoPath: repoURL.path)),
            updater: updater,
            rootOverviewInspector: LocalRootOverviewFileInspector(),
            rootOverviewRevealer: GeneralSettingsNoopFileRevealer(),
            ignoreRulesManager: ignoreRulesManager,
            errorMapper: GeneralSettingsIntegrationErrorMapper()
        )

        await model.load()
        await model.requestStorageMode(GeneralSettingsStorageMode.move)
        XCTAssertEqual(model.pendingStorageConfirmation, GeneralSettingsStorageMode.move)
        await model.confirmPendingStorageMode()

        await model.requestOverviewOutput(GeneralSettingsOverviewOutput.rootAreaMatrixFile)
        XCTAssertEqual(model.pendingRootOverviewStatus, RootOverviewFileStatus.missing)
        await model.confirmRootOverview()

        model.openIgnoreRules()
        XCTAssertEqual(model.pendingIgnoreRulesAlert, GeneralSettingsIgnoreRulesAlert.createDefault)
        model.createDefaultIgnoreRulesAndOpen()

        let requestsAfterSuccess = await updater.requests()
        XCTAssertEqual(requestsAfterSuccess.map(\.defaultMode), ["Moved", "Moved"])
        XCTAssertEqual(requestsAfterSuccess.map(\.overviewOutput), ["GeneratedOnly", "RootAreaMatrixFile"])
        XCTAssertEqual(model.draft?.defaultStorageMode, .move)
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertNil(model.saveError)
        try assertGeneralSettingsFileBoundaries(repoURL: repoURL, sourceURL: sourceURL)
        XCTAssertEqual(ignoreRulesManager.createdPaths, [repoURL.path])
        XCTAssertEqual(ignoreRulesManager.openedPaths, [repoURL.path, repoURL.path])

        await model.updateLocale(GeneralSettingsLocale.en)
        XCTAssertEqual(model.draft?.locale, .system)
        XCTAssertEqual(model.saveError?.message, "配置错误")

        await model.retrySave()
        let requests = await updater.requests()

        XCTAssertEqual(requests.map(\.locale), ["system", "system", "en", "en"])
        XCTAssertEqual(model.draft?.locale, .en)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testGeneralSettingsLoadingStateKeepsCloseSettingsExit() {
        var didClose = false
        let loadingContent = GeneralSettingsLoadingContent {
            didClose = true
        }
        let bodyText = generalSettingsMirrorDescription(of: loadingContent.body)

        XCTAssertTrue(bodyText.contains("Loading settings..."))
        XCTAssertTrue(bodyText.contains("Button"))
        XCTAssertTrue(bodyText.contains("Close"))
        XCTAssertTrue(bodyText.contains("general-settings-loading-close-settings"))

        loadingContent.onClose()
        XCTAssertTrue(didClose)
    }
}

extension AiFallbackStatus {
    static func aiCategorySuggestionPrivacySkipped(callLogID: Int64) -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .privacySkipped,
            category: .skipped,
            title: "Skipped by privacy rule",
            message: "No AI call was made because a privacy rule blocked the available context.",
            retryable: false,
            retryDisabledReason: "Privacy skipped suggestions cannot be retried from this panel.",
            primaryAction: .viewPrivacyRule,
            secondaryAction: .viewCallLog,
            nonAiFallbackAction: .classifyManually,
            route: nil,
            callLogId: callLogID,
            privacyRuleId: "rule-confidential",
            retryAfter: nil
        )
    }

    static func aiCategorySuggestionProviderUnavailable(callLogID: Int64) -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .providerUnavailable,
            category: .unavailable,
            title: "AI provider is unavailable",
            message: "The configured AI provider cannot return a category suggestion right now.",
            retryable: true,
            retryDisabledReason: "Retry before accepting this suggestion.",
            primaryAction: .retry,
            secondaryAction: .viewCallLog,
            nonAiFallbackAction: .classifyManually,
            route: .remote,
            callLogId: callLogID,
            privacyRuleId: nil,
            retryAfter: nil
        )
    }

    static func aiCategorySuggestionInternalFailure() -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .internalFailure,
            category: .error,
            title: "AI suggestion failed.",
            message: "AreaMatrix could not standardize the AI category fallback state.",
            retryable: false,
            retryDisabledReason: "Retry is unavailable until the failure is resolved.",
            primaryAction: .viewCallLog,
            secondaryAction: nil,
            nonAiFallbackAction: .classifyManually,
            route: nil,
            callLogId: nil,
            privacyRuleId: nil,
            retryAfter: nil
        )
    }
}

@MainActor
func aiCategorySuggestionSuggestionModel(
    request: AIClassificationSuggestionRequestState,
    bridge: AICategorySuggestionSuggestionBridge,
    fallbackBridge: AICategorySuggestionFallbackBridge = AICategorySuggestionFallbackBridge()
) -> AIClassificationSuggestionPanelModel {
    AIClassificationSuggestionPanelModel(
        repoPath: "/tmp/repo",
        request: request,
        suggester: bridge,
        fallbackReader: fallbackBridge,
        errorMapper: AICategorySuggestionErrorMapper()
    )
}

struct AICategorySuggestionErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "Mapped ai-classification-suggestion core error",
            severity: .medium,
            suggestedAction: "Open AI settings",
            recoverability: .userActionRequired,
            rawContext: "ai-category-suggestion ai-classification-suggestion"
        )
    }
}

private func makeGeneralSettingsIntegrationRepositoryFixture() throws -> (repoURL: URL, sourceURL: URL) {
    let repoURL = try makeGeneralSettingsIntegrationTemporaryRepository()
    try FileManager.default.createDirectory(
        at: repoURL.appendingPathComponent(".areamatrix", isDirectory: true),
        withIntermediateDirectories: true
    )
    try "readme".write(
        to: repoURL.appendingPathComponent("README.md"),
        atomically: true,
        encoding: .utf8
    )
    let sourceURL = repoURL.appendingPathComponent("source.txt")
    try "source".write(to: sourceURL, atomically: true, encoding: .utf8)
    return (repoURL, sourceURL)
}

private func assertGeneralSettingsFileBoundaries(repoURL: URL, sourceURL: URL) throws {
    XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("README.md")), "readme")
}

private enum GeneralSettingsUpdateResult {
    case success
    case failure(Error)
}

private actor GeneralSettingsIntegrationUpdater: CoreConfigurationUpdating {
    private let results: [GeneralSettingsUpdateResult]
    private var index = 0
    private var configs: [RepoConfigSnapshot] = []

    init(results: [GeneralSettingsUpdateResult]) {
        self.results = results
    }

    func updateConfig(repoPath _: String, newConfig: RepoConfigSnapshot) async throws {
        configs.append(newConfig)
        let result = index < results.count ? results[index] : .success
        index += 1
        if case let .failure(error) = result {
            throw error
        }
    }

    func requests() -> [RepoConfigSnapshot] {
        configs
    }
}

private enum GeneralSettingsIgnoreOpenResult {
    case success
    case missingThenSuccess
}

@MainActor
private final class RecordingIgnoreRulesManager: RepositoryIgnoreRulesManaging {
    private let openResult: GeneralSettingsIgnoreOpenResult
    private var openAttempts = 0
    private(set) var openedPaths: [String] = []
    private(set) var createdPaths: [String] = []

    init(openResult: GeneralSettingsIgnoreOpenResult = .success) {
        self.openResult = openResult
    }

    func openIgnoreRules(repoPath: String) throws {
        openedPaths.append(repoPath)
        if openResult == .missingThenSuccess, openAttempts == 0 {
            openAttempts += 1
            throw RepositoryIgnoreRulesError.ignoreRulesMissing
        }
        openAttempts += 1
    }

    func createDefaultIgnoreRules(repoPath: String) throws {
        createdPaths.append(repoPath)
    }
}

private actor GeneralSettingsStaticConfigLoader: CoreConfigurationLoading {
    let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor GeneralSettingsIntegrationErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "配置错误",
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: "general-settings"
        )
    }
}

private actor GeneralSettingsRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    let opening: RepositoryOpeningResult
    private var repoPaths: [String] = []

    init(opening: RepositoryOpeningResult) {
        self.opening = opening
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        repoPaths.append(repoPath)
        return opening
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

@MainActor
private final class GeneralSettingsNoopFileRevealer: RepositoryFileRevealing {
    func revealFile(repoPath _: String, relativePath _: String) throws {}
}

@MainActor
private final class NoopAccessibilityAnnouncer: AccessibilityAnnouncing {
    func announce(_: String) {}
}

private extension RepoConfigSnapshot {
    static func generalSettingsIntegrationFixture(
        repoPath: String,
        defaultMode: String = "Copied",
        overviewOutput: String = "GeneratedOnly",
        locale: String = "system"
    ) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: defaultMode,
            overviewOutput: overviewOutput,
            aiEnabled: false,
            locale: locale,
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}

private extension RepositoryOpeningResult {
    static func generalSettingsIntegrationFixture(
        repoPath: String,
        defaultMode: String
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .generalSettingsIntegrationFixture(repoPath: repoPath, defaultMode: defaultMode),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: 1,
                children: [
                    RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: 1, children: [])
                ]
            ),
            currentCategoryFiles: [
                FileEntrySnapshot.generalSettingsIntegrationFixture(id: 1, currentName: "source.pdf")
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func generalSettingsIntegrationFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 12,
            hashSha256: "hash-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1,
            updatedAt: 1
        )
    }
}

private func makeGeneralSettingsIntegrationTemporaryRepository() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixGeneralSettingsIntegration")
}

private func generalSettingsMirrorDescription(of value: Any) -> String {
    testMirrorDescription(of: value)
}
