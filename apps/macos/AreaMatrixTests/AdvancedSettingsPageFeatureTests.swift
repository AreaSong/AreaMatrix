@testable import AreaMatrix
import XCTest

final class AdvancedSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadUsesRepositoryConfigCoreConfigSnapshotForVisibleAdvancedSettings() async {
        let loader = RecordingConfigurationLoader(result: .success(.advancedSettingsFixture(
            repoPath: "/tmp/repo",
            overviewOutput: "RootAreaMatrixFile",
            allowReplaceDuringImport: true
        )))
        let model = AdvancedSettingsModel(
            repoPath: "/tmp/repo",
            loader: loader,
            updater: RecordingConfigurationUpdater(result: .success(())),
            diagnosticsCollector: RecordingDiagnosticsCollector(snapshot: .testFixture()),
            coreVersionReader: StaticCoreVersionReader(version: "0.1.0"),
            errorMapper: RecordingCoreErrorMapper.advancedSettings()
        )

        await model.load()

        await loader.assertRequestedPaths(["/tmp/repo"])
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, true)
    }

    @MainActor
    func testRecoveryToolsSectionExposesAdvancedSettingsStartupRecoveryCoreEntrypointWithoutInlineRecovery() {
        var didOpenRecoveryTools = false
        let section = AdvancedSettingsRecoveryToolsSection {
            didOpenRecoveryTools = true
        }

        assertTestMirrorDescription(of: section.body, contains: [
            "Recovery tools",
            "Open recovery tools...",
            "advanced-settings-startup-recovery-core-open-recovery-tools"
        ])

        section.onOpenRecoveryTools()
        XCTAssertTrue(didOpenRecoveryTools)
    }

    @MainActor
    func testAdvancedSettingsRecoveryToolsEntrypointRoutesToRepairConfirmationWithoutRunningRecovery() async {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let recoverer = RecordingCoreStartupRecoverer()
        let fixture = makeShellSettingsGeneralFixture(
            opening: opening,
            selectedTab: "advanced",
            model: makeShellOnboardingModel(startupRecoverer: recoverer)
        )
        let model = fixture.model

        model.openMainRepositoryRepair(repoPath: fixture.opening.config.repoPath)

        XCTAssertEqual(
            model.route,
            .dbRepairConfirm(DatabaseRepairRouteState(
                repoPath: "/tmp/repo",
                scanSession: nil,
                mapping: nil,
                returnRoute: .settingsGeneral(opening, selectedTab: "advanced")
            ))
        )
        await recoverer.assertNoRepoPathRequests()
    }

    @MainActor
    func testDatabaseRepairCancelFromAdvancedSettingsReturnsToSourceSettingsPage() {
        let opening = RepositoryOpeningResult.shellFixture(repoPath: "/tmp/repo", fileCount: 1)
        let fixture = makeShellSettingsGeneralFixture(
            opening: opening,
            selectedTab: "advanced",
            model: makeShellOnboardingModel()
        )
        let model = fixture.model

        model.openMainRepositoryRepair(repoPath: opening.config.repoPath)
        guard let repairRoute = requireDatabaseRepairRoute(model, message: "expected db repair route") else { return }

        model.returnFromDatabaseRepair(repairRoute)

        XCTAssertEqual(model.route, .settingsGeneral(opening))
        XCTAssertEqual(model.settingsGeneralSelectedTab, "advanced")
    }

    @MainActor
    func testRootOverviewRequiresConfirmationAndDoesNotWriteRootFiles() async throws {
        let repoURL = try temporaryAdvancedSettingsRepo()
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
        let model = await loadedAdvancedModel(
            updater: updater,
            config: .advancedSettingsFixture(repoPath: repoURL.path),
            inspector: LocalRootOverviewFileInspector()
        )

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        XCTAssertEqual(model.pendingRootOverviewStatus, .userContent)
        await updater.assertNoConfigurationUpdateRequests()

        await model.confirmRootOverview()

        await updater.assertRequestedConfigValues(\.overviewOutput, ["RootAreaMatrixFile"])
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("AREAMATRIX.md")), "user overview\n")
        XCTAssertEqual(try String(contentsOf: repoURL.appendingPathComponent("README.md")), "user readme\n")
    }

    @MainActor
    func testOverviewSaveFailureUsesOverviewGeneratedCoreRetryIdentifierAndRollsBack() async {
        let updater = RecordingConfigurationUpdater(failureThenSuccess: CoreError.Db(message: "locked"))
        let model = await loadedAdvancedModel(updater: updater)

        await model.requestOverviewOutput(.rootAreaMatrixFile)
        await model.confirmRootOverview()

        XCTAssertEqual(model.draft?.overviewOutput, .generatedOnly)
        XCTAssertEqual(model.saveError?.message, L10n.message("Could not save overview setting"))
        XCTAssertEqual(model.retrySaveAccessibilityIdentifier, "advanced-settings-overview-generated-retry-save")
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()

        await updater.assertRequestedConfigValues(\.overviewOutput, ["RootAreaMatrixFile", "RootAreaMatrixFile"])
        XCTAssertEqual(model.draft?.overviewOutput, .rootAreaMatrixFile)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testOverviewOutputSectionIsTaggedAsAdvancedSettingsOverviewGeneratedCoreFeature() {
        XCTAssertEqual(AdvancedSettingsOverviewOutput.generatedOnly.label, L10n.string("Generated only"))
        XCTAssertEqual(
            AdvancedSettingsOverviewOutput.rootAreaMatrixFile.label,
            L10n.string("Root AREAMATRIX.md")
        )
        XCTAssertEqual(
            AdvancedSettingsAccessibilityID.overviewOutput,
            "advanced-settings-overview-generated-overview-output"
        )
    }

    @MainActor
    func testAllowReplaceRequiresConfirmationAndDisableSavesDirectly() async {
        let updater = RecordingConfigurationUpdater(result: .success(()))
        let model = await loadedAdvancedModel(updater: updater)

        await model.requestAllowReplaceDuringImport(true)
        XCTAssertTrue(model.isReplaceConfirmationPending)
        await updater.assertNoConfigurationUpdateRequests()

        model.cancelAllowReplaceDuringImport()
        XCTAssertFalse(model.isReplaceConfirmationPending)
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, false)
        await updater.assertNoConfigurationUpdateRequests()

        await model.requestAllowReplaceDuringImport(true)
        await model.confirmAllowReplaceDuringImport()
        await model.requestAllowReplaceDuringImport(false)

        await updater.assertRequestedConfigValues(\.allowReplaceDuringImport, [true, false])
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, false)
    }

    @MainActor
    func testSaveFailureRollsBackAdvancedDraftAndRetryUsesSameCoreConfig() async {
        let updater = RecordingConfigurationUpdater(failureThenSuccess: CoreError.Db(message: "locked"))
        let model = await loadedAdvancedModel(updater: updater)

        await model.requestAllowReplaceDuringImport(true)
        await model.confirmAllowReplaceDuringImport()

        XCTAssertEqual(model.draft?.allowReplaceDuringImport, false)
        XCTAssertEqual(model.saveError?.message, L10n.message("Could not save advanced setting"))
        XCTAssertEqual(model.saveError?.recovery, L10n.message(
            "error.unmapped.action",
            fallback: "Retry save",
            technicalDetail: "Retry save"
        ))
        XCTAssertTrue(model.hasRetryableSave)

        await model.retrySave()

        await updater.assertRequestedConfigValues(\.allowReplaceDuringImport, [true, true])
        XCTAssertEqual(model.draft?.allowReplaceDuringImport, true)
        XCTAssertNil(model.saveError)
    }

    @MainActor
    func testDefaultCoreBridgePersistsAdvancedConfigWithoutCreatingRootFiles() async throws {
        let repoURL = try temporaryAdvancedSettingsRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let model = AdvancedSettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            diagnosticsCollector: bridge,
            coreVersionReader: bridge,
            errorMapper: bridge
        )

        await model.load()
        await model.requestOverviewOutput(.rootAreaMatrixFile)
        XCTAssertEqual(model.pendingRootOverviewStatus, .missing)
        await model.confirmRootOverview()
        await model.requestAllowReplaceDuringImport(true)
        await model.confirmAllowReplaceDuringImport()
        let reloaded = try await bridge.loadConfig(repoPath: repoURL.path)

        XCTAssertEqual(reloaded.overviewOutput, "RootAreaMatrixFile")
        XCTAssertTrue(reloaded.allowReplaceDuringImport)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
    }

    @MainActor
    func testDefaultCoreBridgeAppliesRootOverviewOnNextRegenerationWithoutTouchingReadme() async throws {
        let repoURL = try temporaryAdvancedSettingsRepo()
        let sourceRootURL = try temporaryAdvancedSettingsRepo()
        defer { removeTestTemporaryItems(repoURL, sourceRootURL) }
        let sourceURL = sourceRootURL.appendingPathComponent("overview-source.txt")
        let readmeURL = repoURL.appendingPathComponent("README.md")
        try Data("overview source".utf8).write(to: sourceURL)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        try "user readme\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        let model = AdvancedSettingsModel(
            repoPath: repoURL.path,
            loader: bridge,
            updater: bridge,
            diagnosticsCollector: bridge,
            coreVersionReader: bridge,
            errorMapper: bridge
        )

        await model.load()
        await model.requestOverviewOutput(.rootAreaMatrixFile)
        await model.confirmRootOverview()
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))

        _ = try await bridge.importIndexedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "overview-source.txt"
        )

        let rootOverview = try String(contentsOf: repoURL.appendingPathComponent("AREAMATRIX.md"))
        let generatedOverview = try String(contentsOf: repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("root.md", isDirectory: false))
        XCTAssertTrue(rootOverview.contains("AREAMATRIX:BEGIN"))
        XCTAssertTrue(generatedOverview.contains("AREAMATRIX:BEGIN"))
        XCTAssertEqual(try String(contentsOf: readmeURL), "user readme\n")
    }

    @MainActor
    private func loadedAdvancedModel(
        updater: RecordingConfigurationUpdater,
        config: AppRepoConfigSnapshot = .advancedSettingsFixture(repoPath: "/tmp/repo"),
        inspector: any RootOverviewFileInspecting = StaticRootOverviewFileInspector(status: .missing)
    ) async -> AdvancedSettingsModel {
        let model = AdvancedSettingsModel(
            repoPath: config.repoPath,
            loader: RecordingConfigurationLoader(result: .success(config)),
            updater: updater,
            rootOverviewInspector: inspector,
            diagnosticsCollector: RecordingDiagnosticsCollector(snapshot: .testFixture()),
            coreVersionReader: StaticCoreVersionReader(version: "0.1.0"),
            errorMapper: RecordingCoreErrorMapper.advancedSettings()
        )
        await model.load()
        return model
    }
}

private func temporaryAdvancedSettingsRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixAdvancedSettings")
}
