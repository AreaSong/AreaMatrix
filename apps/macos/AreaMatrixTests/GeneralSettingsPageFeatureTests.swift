@testable import AreaMatrix
import XCTest

final class GeneralSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesRepositoryConfigCoreConfigSnapshotForVisibleGeneralSettings() async {
        let loader = RecordingConfigurationLoader(result: .success(.generalSettingsFixture(
            repoPath: "/tmp/repo",
            defaultMode: "Indexed",
            overviewOutput: "RootAreaMatrixFile",
            locale: "en"
        )))
        let model = GeneralSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: RecordingConfigurationUpdater(result: .success(())),
            rootOverviewInspector: StaticRootOverviewFileInspector(status: .missing),
            errorMapper: RecordingCoreErrorMapper.generalSettings()
        )

        await model.load()

        await loader.assertRequestedPaths(["/tmp/repo"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.draft?.defaultStorageMode, .indexOnly)
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertEqual(model.draft?.contentLanguage, .en)
    }

    @MainActor
    func testCopyAndContentLanguageSaveThroughUpdateConfigWithoutMockState() async {
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = await loadedModel(updater: updater, config: .generalSettingsFixture(
            repoPath: "/tmp/repo",
            defaultMode: "Indexed",
            overviewOutput: "GeneratedOnly",
            locale: "en"
        ))

        await model.requestStorageMode(.copy)
        await model.updateContentLanguage(.zhHans)
        await model.updateContentLanguage(.followInterface)

        await updater.assertRequestedRepoPaths(["/tmp/repo", "/tmp/repo", "/tmp/repo"])
        await updater.assertRequestedConfigValue(at: 0, \.defaultMode, "Copied")
        await updater.assertRequestedConfigValue(at: 1, \.locale, "zh-Hans")
        await updater.assertRequestedConfigValue(at: 2, \.locale, "system")
        XCTAssertEqual(model.draft?.defaultStorageMode, .copy)
        XCTAssertEqual(model.draft?.contentLanguage, .followInterface)
    }

    @MainActor
    func testContentLanguageMappingCanonicalizesLegacyChineseLocale() {
        XCTAssertEqual(RepositoryContentLanguage.followInterface.snapshotValue, "system")
        XCTAssertEqual(RepositoryContentLanguage.zhHans.snapshotValue, "zh-Hans")
        XCTAssertEqual(RepositoryContentLanguage.en.snapshotValue, "en")
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "system"), .followInterface)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "zh-CN"), .zhHans)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "en"), .en)
        XCTAssertEqual(RepositoryContentLanguage(snapshotValue: "zh-Hans"), .zhHans)
    }

    func testCoreRepositoryTreeLocaleResolverNormalizesStoredLocales() {
        XCTAssertEqual(CoreRepositoryTreeLocaleResolver.resolve("zh-CN", preferredLanguages: []), "zh-Hans")
        XCTAssertEqual(CoreRepositoryTreeLocaleResolver.resolve("zh-Hans", preferredLanguages: []), "zh-Hans")
        XCTAssertEqual(CoreRepositoryTreeLocaleResolver.resolve("en", preferredLanguages: []), "en")
    }

    func testCoreRepositoryTreeLocaleResolverUsesSupportedSystemLanguageOrEnglishFallback() {
        XCTAssertEqual(
            CoreRepositoryTreeLocaleResolver.resolve(
                "system",
                preferredLanguages: ["fr-FR", "zh-Hans-CN", "en-US"]
            ),
            "zh-Hans"
        )
        XCTAssertEqual(
            CoreRepositoryTreeLocaleResolver.resolve(
                "system",
                preferredLanguages: ["fr-FR", "en-US", "zh-Hans-CN"]
            ),
            "en"
        )
        XCTAssertEqual(
            CoreRepositoryTreeLocaleResolver.resolve(
                "system",
                preferredLanguages: ["zh-Hant-TW", "fr-FR"]
            ),
            "zh-Hans"
        )
    }

    @MainActor
    func testDangerousStorageModeRequiresConfirmationBeforeUpdateConfig() async {
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = await loadedModel(updater: updater)

        await model.requestStorageMode(.move)
        XCTAssertEqual(model.pendingStorageConfirmation, .move)
        await updater.assertNoConfigurationUpdateRequests()

        model.cancelPendingStorageMode()
        XCTAssertNil(model.pendingStorageConfirmation)
        XCTAssertEqual(model.draft?.defaultStorageMode, .copy)
        await updater.assertNoConfigurationUpdateRequests()

        await model.requestStorageMode(.indexOnly)
        await model.confirmPendingStorageMode()

        await updater.assertRequestedConfigValues(\.defaultMode, ["Indexed"])
        XCTAssertEqual(model.draft?.defaultStorageMode, .indexOnly)
    }

    @MainActor
    func testImportMoveFileCoreMoveDefaultPersistsOnlyAfterRiskConfirmation() async {
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = await loadedModel(updater: updater)

        await model.requestStorageMode(.move)
        XCTAssertEqual(model.pendingStorageConfirmation, .move)
        await updater.assertNoConfigurationUpdateRequests()

        await model.confirmPendingStorageMode()

        XCTAssertNil(model.pendingStorageConfirmation)
        await updater.assertRequestedRepoPaths(["/tmp/repo"])
        await updater.assertRequestedConfigValues(\.defaultMode, ["Moved"])
        XCTAssertEqual(model.draft?.defaultStorageMode, .move)
    }

    @MainActor
    func testRootOverviewRequiresConfirmationAndDoesNotWriteFilesDuringSettingsSave() async throws {
        let repoURL = try temporaryGeneralSettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try "user overview\n".write(
            to: repoURL.appendingPathComponent("AREAMATRIX.md"),
            atomically: true,
            encoding: .utf8
        )
        try "user readme\n".write(
            to: repoURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = await loadedModel(
            updater: updater,
            config: .generalSettingsFixture(repoPath: repoURL.path),
            inspector: LocalRootOverviewFileInspector()
        )

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        XCTAssertEqual(model.pendingRootOverviewStatus, .userContent)
        await updater.assertNoConfigurationUpdateRequests()

        await model.confirmRootOverview()

        await updater.assertRequestedConfigValues(\.overviewOutput, ["RootAreaMatrixFile"])
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("AREAMATRIX.md")), "user overview\n")
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("README.md")), "user readme\n")
    }

    @MainActor
    func testUnsafeRootOverviewOffersFinderRecoveryWithoutUpdatingConfig() async {
        let unsafeReason = "Cannot safely update AREAMATRIX.md"
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let revealer = RecordingRepositoryFileRevealer()
        let model = await loadedModel(
            updater: updater,
            inspector: StaticRootOverviewFileInspector(
                // swiftformat:disable:next spaceAroundParens
                status: RootOverviewFileStatus.unsafe(unsafeReason)
            ),
            revealer: revealer
        )

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        model.revealRootOverviewInFinder()

        // swiftformat:disable:next spaceAroundParens
        XCTAssertEqual(model.pendingRootOverviewStatus, RootOverviewFileStatus.unsafe(unsafeReason))
        revealer.assertRevealRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: "/tmp/repo",
            relativePath: "AREAMATRIX.md"
        )])
        await updater.assertNoConfigurationUpdateRequests()
    }

    @MainActor
    func testSaveFailureRollsBackToLastSavedValueAndRetryUsesSameCoreConfig() async {
        let updater = RecordingConfigurationUpdater(failureThenSuccess: CoreError.Db(message: "locked"))
        let model = await loadedModel(updater: updater)

        await model.updateContentLanguage(.en)

        XCTAssertEqual(model.draft?.contentLanguage, .followInterface)
        XCTAssertEqual(model.saveError?.message, "数据库错误")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()

        await updater.assertRequestedConfigValues(\.locale, ["en", "en"])
        XCTAssertEqual(model.draft?.contentLanguage, .en)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testDefaultCoreBridgeUpdatesRealRepoConfigWithoutCreatingRootFiles() async throws {
        let repoURL = try temporaryGeneralSettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let model = GeneralSettingsModel(repoPath: repoURL.path, loader: bridge, updater: bridge)

        await model.load()
        await model.requestStorageMode(.indexOnly)
        XCTAssertEqual(model.pendingStorageConfirmation, .indexOnly)
        await model.confirmPendingStorageMode()
        await model.updateContentLanguage(.en)
        var reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.defaultMode, "Indexed")
        XCTAssertEqual(reloaded.locale, "en")
        await model.updateContentLanguage(.followInterface)
        reloaded = try await bridge.loadConfig(repoPath: repoURL.path)
        XCTAssertEqual(reloaded.locale, "system")
        await model.updateContentLanguage(.zhHans)
        reloaded = try await bridge.loadConfig(repoPath: repoURL.path)
        XCTAssertEqual(reloaded.locale, "zh-Hans")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    func testDefaultCoreBridgePersistsImportMoveFileCoreMoveDefaultWithoutMovingExternalFiles() async throws {
        let repoURL = try temporaryGeneralSettingsRepo()
        let sourceRoot = try temporaryGeneralSettingsRepo()
        defer { removeTestTemporaryItems(repoURL, sourceRoot) }
        let sourceURL = sourceRoot.appendingPathComponent("source.txt")
        try "source".write(to: sourceURL, atomically: true, encoding: .utf8)
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let model = GeneralSettingsModel(repoPath: repoURL.path, loader: bridge, updater: bridge)

        await model.load()
        await model.requestStorageMode(.move)
        XCTAssertEqual(model.pendingStorageConfirmation, .move)
        await model.confirmPendingStorageMode()
        let reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.defaultMode, "Moved")
        XCTAssertEqual(model.draft?.defaultStorageMode, .move)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("source.txt").path))
    }

    @MainActor
    func testOnboardingRoutesSettingsEntryToGeneralSettingsGeneralSettingsWithoutRepositoryPathFlow() {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let model = makeShellOnboardingModel(settingsReader: ShellStaticSettingsReader(repoPath: nil))

        model.showGeneralSettings(opening: opening)

        XCTAssertEqual(model.route, .settingsGeneral(opening))
        XCTAssertFalse(model.validatePathReturnRouteIsSettings)
    }

    @MainActor
    private func loadedModel(
        updater: RecordingConfigurationUpdater,
        config: RepoConfigSnapshot = .generalSettingsFixture(repoPath: "/tmp/repo"),
        inspector: any RootOverviewFileInspecting = StaticRootOverviewFileInspector(status: .missing),
        revealer: (any RepositoryFileRevealing)? = nil
    ) async -> GeneralSettingsModel {
        let model = GeneralSettingsModel(
            repoPath: config.repoPath,
            loader: RecordingConfigurationLoader(result: .success(config)),
            updater: updater,
            rootOverviewInspector: inspector,
            rootOverviewRevealer: revealer ?? RecordingRepositoryFileRevealer(),
            errorMapper: RecordingCoreErrorMapper.generalSettings()
        )
        await model.load()
        return model
    }
}

private func temporaryGeneralSettingsRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixGeneralSettings")
}
