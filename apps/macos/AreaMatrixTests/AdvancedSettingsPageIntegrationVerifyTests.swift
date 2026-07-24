@testable import AreaMatrix
import XCTest

final class AdvancedSettingsIntegrationTests: XCTestCase {
    @MainActor
    func testAdvancedSettingsPageIntegrationConnectsDeclaredCapabilitiesDiagnosticsLogsAndRecoveryExit() async throws {
        let context = try await makeAdvancedSettingsIntegrationContext()
        defer {
            removeTestTemporaryItems(context.repoURL, context.sourceRootURL)
        }

        await context.model.load()
        context.model.requestDiagnosticsExport()
        await context.model.collectDiagnostics()
        context.model.openLogsFolder()
        context.model.copyDiagnosticSummary()
        await context.model.requestOverviewOutput(.rootAreaMatrixFile)
        XCTAssertEqual(context.model.pendingRootOverviewStatus, .missing)
        await context.model.confirmRootOverview()
        await context.model.requestAllowReplaceDuringImport(true)
        XCTAssertTrue(context.model.isReplaceConfirmationPending)
        await context.model.confirmAllowReplaceDuringImport()

        try await assertAdvancedSettingsSavedConfig(context)

        _ = try await context.bridge.importIndexedFile(
            repoPath: context.repoURL.path,
            sourceURL: context.sourceURL,
            overrideCategory: "docs",
            overrideFilename: "advancedSettings-source.txt"
        )

        try await assertAdvancedSettingsDiagnosticsAndOverview(context)

        let opening = RepositoryOpeningResult.shellFixture(repoPath: context.repoURL.path, fileCount: 1)
        let recoverer = RecordingCoreStartupRecoverer()
        let shell = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            helpOpener: NoopWelcomeHelpOpener()
        )
        shell.route = .settingsGeneral(opening)
        shell.settingsGeneralSelectedTab = "advanced"
        shell.openMainRepositoryRepair(repoPath: context.repoURL.path)

        await assertAdvancedSettingsRepairExit(
            shell: shell,
            opening: opening,
            context: context,
            recoverer: recoverer
        )
    }

    @MainActor
    func testAdvancedSettingsLoadFailureShowsRecoverableErrorStateWithoutMockingSuccess() async {
        let model = AdvancedSettingsModel(
            repoPath: "/tmp/advancedSettings-broken-repo",
            loader: RecordingConfigurationLoader(result: .failure(CoreError.Config(reason: "invalid repo_config"))),
            updater: NoopConfigurationUpdater(),
            errorMapper: CoreBridge()
        )

        await model.load()

        guard case let .failed(error) = model.loadState else {
            return XCTFail("Expected advanced-settings advanced settings load to fail through the error state")
        }
        XCTAssertEqual(error.message, L10n.message("Unable to load advanced settings"))
        XCTAssertFalse(error.recovery.key.isEmpty)
        XCTAssertNil(model.draft)
        XCTAssertNil(model.savedConfig)
        XCTAssertFalse(model.hasRetryableSave)
    }

    @MainActor
    func testAdvancedSettingsLogFolderFailureKeepsPageLoadedWithRecoverableError() async {
        let model = await loadedAdvancedSettingsModel(
            logsOpener: RecordingAdvancedSettingsLogsOpener(result: .failure(AdvancedSettingsLogFolderError.missing(
                "/tmp/repo/.areamatrix/logs"
            )))
        )

        model.openLogsFolder()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.actionFeedback, .failed(AdvancedSettingsError(
            message: L10n.message("Open logs folder failed"),
            recovery: L10n.message(
                "Check that .areamatrix/logs exists, then retry after Core logging is initialized."
            )
        )))
    }

    @MainActor
    func testAdvancedSettingsDiagnosticsFailureMapsCoreErrorAndDoesNotMockSuccess() async {
        let model = await loadedAdvancedSettingsModel(
            diagnosticsCollector: ShellRecordingDiagnosticsCollector(result: .failure(CoreError.PermissionDenied(
                path: "/tmp/repo/.areamatrix"
            )))
        )

        model.requestDiagnosticsExport()
        await model.collectDiagnostics()

        XCTAssertEqual(model.loadState, .loaded)
        guard case let .failed(error) = model.diagnosticsState else {
            return XCTFail("Expected diagnostics failure state")
        }
        XCTAssertEqual(error.message, L10n.message("Diagnostics could not be exported"))
        XCTAssertFalse(error.recovery.key.isEmpty)
    }

    @MainActor
    func testAdvancedSettingsCancelledDiagnosticsIgnoresLateCollectorResult() async {
        let snapshot = DiagnosticsSnapshotSnapshot.testFixture(snapshotPath: "/tmp/late-advanced-diagnostics")
        let collector = SuspendedDiagnosticsCollector(result: .success(snapshot))
        let model = await loadedAdvancedSettingsModel(diagnosticsCollector: collector)

        model.requestDiagnosticsExport()
        let collection = Task { await model.collectDiagnostics() }
        await collector.waitUntilStarted()
        XCTAssertEqual(model.diagnosticsState, .collecting)

        model.cancelDiagnosticsExport()
        await collector.finish()
        await collection.value

        XCTAssertEqual(model.diagnosticsState, .idle)
    }
}

@MainActor
private func assertAdvancedSettingsSavedConfig(_ context: AdvancedSettingsIntegrationContext) async throws {
    let savedConfig = try await context.bridge.loadConfig(repoPath: context.repoURL.path)
    XCTAssertEqual(savedConfig.overviewOutput, "RootAreaMatrixFile")
    XCTAssertTrue(savedConfig.allowReplaceDuringImport)
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.rootOverviewURL.path))
}

@MainActor
private func assertAdvancedSettingsDiagnosticsAndOverview(_ context: AdvancedSettingsIntegrationContext) async throws {
    let rootOverview = try String(contentsOf: context.rootOverviewURL)
    let generatedOverview = try String(contentsOf: context.generatedOverviewURL)
    XCTAssertEqual(context.model.draft?.overviewOutput, .rootAreaMatrixFile)
    XCTAssertEqual(context.model.draft?.allowReplaceDuringImport, true)
    XCTAssertTrue(rootOverview.contains("AREAMATRIX:BEGIN"))
    XCTAssertTrue(generatedOverview.contains("AREAMATRIX:BEGIN"))
    XCTAssertEqual(try String(contentsOf: context.readmeURL), "user readme\n")
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.sourceURL.path))
    XCTAssertEqual(context.model.versionInfo.appVersion, "9.8.7 (654)")
    XCTAssertEqual(context.model.versionInfo.coreVersion, "0.1.0-test")
    XCTAssertEqual(context.model.versionInfo.repoSchemaVersion, 3)
    XCTAssertNil(context.model.versionError)
    XCTAssertEqual(context.model.diagnosticsState, .collected(context.diagnosticsSnapshot))
    await context.diagnosticsCollector.assertRequestedRepoPaths([context.repoURL.path])
    context.logsOpener.assertOpenedRepoPaths([context.repoURL.path])
    context.summaryCopier.assertCopiedSummary(contains: [
        L10n.format(
            "advanced.diagnosticSummary",
            context.repoURL.lastPathComponent,
            "9.8.7 (654)",
            "0.1.0-test",
            "v3",
            "GeneratedOnly",
            "false"
        )
    ])
}

@MainActor
private func assertAdvancedSettingsRepairExit(
    shell: OnboardingModel,
    opening: RepositoryOpeningResult,
    context: AdvancedSettingsIntegrationContext,
    recoverer: RecordingCoreStartupRecoverer
) async {
    XCTAssertEqual(
        shell.route,
        .dbRepairConfirm(DatabaseRepairRouteState(
            repoPath: context.repoURL.path,
            scanSession: nil,
            mapping: nil,
            returnRoute: .settingsGeneral(opening, selectedTab: "advanced")
        ))
    )
    XCTAssertEqual(shell.settingsGeneralSelectedTab, "advanced")
    await recoverer.assertNoRepoPathRequests()
}

private struct AdvancedSettingsIntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let sourceURL: URL
    let readmeURL: URL
    let rootOverviewURL: URL
    let generatedOverviewURL: URL
    let diagnosticsSnapshot: DiagnosticsSnapshotSnapshot
    let diagnosticsCollector: ShellRecordingDiagnosticsCollector
    let logsOpener: RecordingAdvancedSettingsLogsOpener
    let summaryCopier: RecordingAdvancedDiagnosticCopier
    let bridge: CoreBridge
    let model: AdvancedSettingsModel
}

@MainActor
private func makeAdvancedSettingsIntegrationContext() async throws -> AdvancedSettingsIntegrationContext {
    let repoURL = try advancedSettingsTemporaryDirectory()
    var cleanupURLs = [repoURL]
    var didSucceed = false
    defer {
        if !didSucceed {
            removeTestTemporaryItems(cleanupURLs)
        }
    }

    let (sourceRootURL, sourceURL) = try makeAdvancedSettingsSourceFixture()
    cleanupURLs.append(sourceRootURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let readmeURL = try makeAdvancedSettingsRepositoryFiles(repoURL: repoURL)

    let diagnosticsSnapshot = DiagnosticsSnapshotSnapshot.testFixture(
        snapshotPath: advancedSettingsDiagnosticsPath(repoURL: repoURL),
        createdAt: 1_778_000_000,
        warnings: ["index.db-wal disappeared during snapshot"]
    )
    let diagnosticsCollector = ShellRecordingDiagnosticsCollector(result: .success(diagnosticsSnapshot))
    let logsOpener = RecordingAdvancedSettingsLogsOpener(logsPath: advancedSettingsLogsPath(repoURL: repoURL))
    let summaryCopier = RecordingAdvancedDiagnosticCopier()
    let model = advancedSettingsIntegrationModel(
        repoURL: repoURL,
        bridge: bridge,
        diagnosticsCollector: diagnosticsCollector,
        logsOpener: logsOpener,
        summaryCopier: summaryCopier
    )

    didSucceed = true
    return AdvancedSettingsIntegrationContext(
        repoURL: repoURL,
        sourceRootURL: sourceRootURL,
        sourceURL: sourceURL,
        readmeURL: readmeURL,
        rootOverviewURL: repoURL.appendingPathComponent("AREAMATRIX.md"),
        generatedOverviewURL: repoURL
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("generated", isDirectory: true)
            .appendingPathComponent("root.md"),
        diagnosticsSnapshot: diagnosticsSnapshot,
        diagnosticsCollector: diagnosticsCollector,
        logsOpener: logsOpener,
        summaryCopier: summaryCopier,
        bridge: bridge,
        model: model
    )
}

private func makeAdvancedSettingsSourceFixture() throws -> (rootURL: URL, sourceURL: URL) {
    let sourceRootURL = try advancedSettingsTemporaryDirectory()
    let sourceURL = sourceRootURL.appendingPathComponent("advancedSettings-source.txt")
    try Data("advancedSettings overview source".utf8).write(to: sourceURL)
    return (sourceRootURL, sourceURL)
}

private func makeAdvancedSettingsRepositoryFiles(repoURL: URL) throws -> URL {
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: advancedSettingsLogsPath(repoURL: repoURL)),
                                            withIntermediateDirectories: true)
    let readmeURL = repoURL.appendingPathComponent("README.md")
    try "user readme\n".write(to: readmeURL, atomically: true, encoding: .utf8)
    return readmeURL
}

@MainActor
private func advancedSettingsIntegrationModel(
    repoURL: URL,
    bridge: CoreBridge,
    diagnosticsCollector: ShellRecordingDiagnosticsCollector,
    logsOpener: RecordingAdvancedSettingsLogsOpener,
    summaryCopier: RecordingAdvancedDiagnosticCopier
) -> AdvancedSettingsModel {
    AdvancedSettingsModel(
        repoPath: repoURL.path,
        loader: bridge,
        updater: bridge,
        rootOverviewInspector: LocalRootOverviewFileInspector(),
        diagnosticsCollector: diagnosticsCollector,
        appVersionReader: StaticAppVersionReader(version: "9.8.7 (654)"),
        coreVersionReader: StaticCoreVersionReader(version: "0.1.0-test"),
        metadataReader: SQLiteExistingRepositoryMetadataReader(),
        logsOpener: logsOpener,
        summaryCopier: summaryCopier,
        errorMapper: bridge
    )
}

private func advancedSettingsLogsPath(repoURL: URL) -> String {
    RepositoryMetadataPath.logsURL(repoPath: repoURL.path).path
}

private func advancedSettingsDiagnosticsPath(repoURL: URL) -> String {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("diagnostics", isDirectory: true)
        .appendingPathComponent("advanced-settings-diagnostics.db")
        .path
}

@MainActor
private func loadedAdvancedSettingsModel(
    diagnosticsCollector: any CoreDiagnosticsCollecting = ShellRecordingDiagnosticsCollector(result: .success(
        DiagnosticsSnapshotSnapshot.testFixture(
            snapshotPath: "/tmp/repo/.areamatrix/diagnostics/advanced-settings-diagnostics.db",
            createdAt: 1_778_000_000
        )
    )),
    logsOpener: (any AdvancedSettingsLogFolderOpening)? = nil
) async -> AdvancedSettingsModel {
    let resolvedLogsOpener = logsOpener ?? RecordingAdvancedSettingsLogsOpener(logsPath: "/tmp/repo/.areamatrix/logs")
    let model = AdvancedSettingsModel(
        repoPath: "/tmp/repo",
        loader: StaticConfigurationLoader(config: .advancedSettingsFixture(repoPath: "/tmp/repo")),
        updater: NoopConfigurationUpdater(),
        rootOverviewInspector: StaticRootOverviewFileInspector(status: .missing),
        diagnosticsCollector: diagnosticsCollector,
        appVersionReader: StaticAppVersionReader(version: "1.0.0"),
        coreVersionReader: StaticCoreVersionReader(version: "0.1.0"),
        metadataReader: StaticExistingRepositoryMetadataReader(schemaVersion: 1),
        logsOpener: resolvedLogsOpener,
        summaryCopier: RecordingAdvancedDiagnosticCopier(),
        errorMapper: CoreBridge()
    )
    await model.load()
    return model
}

private func advancedSettingsTemporaryDirectory() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixAdvancedSettings")
}
