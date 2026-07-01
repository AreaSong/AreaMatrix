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
            helpOpener: NoopWelcomeHelpOpener()
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
            .success(()),
            .success(()),
            .failure(CoreError.Config(reason: "locked")),
            .success(())
        ])
        let ignoreRulesManager = RecordingRepositoryIgnoreRulesManager(openScenario: .missingThenSuccess)
        let model = GeneralSettingsModel(
            repoPath: repoURL.path,
            loader: StaticConfigurationLoader(config: RepoConfigSnapshot
                .generalSettingsFixture(repoPath: repoURL.path)),
            updater: updater,
            rootOverviewInspector: LocalRootOverviewFileInspector(),
            rootOverviewRevealer: RecordingRepositoryFileRevealer(),
            ignoreRulesManager: ignoreRulesManager,
            errorMapper: RecordingCoreErrorMapper.generalSettings()
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

        let requestsAfterSuccess = await updater.requestedConfigs()
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
        let requests = await updater.requestedConfigs()

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

        assertTestMirrorDescription(of: loadingContent.body, contains: [
            "Loading settings...",
            "Button",
            "Close",
            "general-settings-loading-close-settings"
        ])

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
        errorMapper: aiCategorySuggestionErrorMapper()
    )
}

func aiCategorySuggestionErrorMapper() -> StaticCoreErrorMapper {
    StaticCoreErrorMapper(mapping: CoreErrorMappingSnapshot(
        kind: .config,
        userMessage: "Mapped ai-classification-suggestion core error",
        severity: .medium,
        suggestedAction: "Open AI settings",
        recoverability: .userActionRequired,
        rawContext: "ai-category-suggestion ai-classification-suggestion"
    ))
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

private typealias GeneralSettingsRecordingRepositoryOpener = RecordingRepositoryOpener
private typealias GeneralSettingsIntegrationUpdater = RecordingConfigurationUpdater

private extension RepositoryOpeningResult {
    static func generalSettingsIntegrationFixture(
        repoPath: String,
        defaultMode: String
    ) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .generalSettingsFixture(repoPath: repoPath, defaultMode: defaultMode),
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
