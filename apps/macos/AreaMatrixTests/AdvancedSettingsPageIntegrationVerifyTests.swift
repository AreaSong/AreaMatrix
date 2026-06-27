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
        let recoverer = RecordingStartupRecoverer()
        let shell = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        shell.route = .settingsGeneral(opening)
        shell.settingsGeneralSelectedTab = "advanced"
        shell.openMainRepositoryRepair(repoPath: context.repoURL.path)
        let recoveryRequests = await recoverer.requestedRepoPaths()

        assertAdvancedSettingsRepairExit(
            shell: shell,
            opening: opening,
            context: context,
            recoveryRequests: recoveryRequests
        )
    }

    @MainActor
    func testAdvancedSettingsLoadFailureShowsRecoverableErrorStateWithoutMockingSuccess() async {
        let model = AdvancedSettingsModel(
            repoPath: "/tmp/advancedSettings-broken-repo",
            loader: AdvancedSettingsFailingConfigLoader(error: CoreError.Config(reason: "invalid repo_config")),
            updater: AdvancedSettingsNoopConfigUpdater(),
            errorMapper: CoreBridge()
        )

        await model.load()

        guard case let .failed(error) = model.loadState else {
            return XCTFail("Expected advanced-settings advanced settings load to fail through the error state")
        }
        XCTAssertEqual(error.message, "Unable to load advanced settings")
        XCTAssertFalse(error.recovery.isEmpty)
        XCTAssertNil(model.draft)
        XCTAssertNil(model.savedConfig)
        XCTAssertFalse(model.hasRetryableSave)
    }

    @MainActor
    func testAdvancedSettingsLogFolderFailureKeepsPageLoadedWithRecoverableError() async {
        let model = await loadedAdvancedSettingsModel(
            logsOpener: AdvancedSettingsRecordingLogsOpener(result: .failure(AdvancedSettingsLogFolderError.missing(
                "/tmp/repo/.areamatrix/logs"
            )))
        )

        model.openLogsFolder()

        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.actionFeedback, .failed(AdvancedSettingsError(
            message: "Open logs folder failed",
            recovery: "Check that .areamatrix/logs exists, then retry after Core logging is initialized."
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
        XCTAssertEqual(error.message, "Diagnostics could not be exported")
        XCTAssertFalse(error.recovery.isEmpty)
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
    let diagnosticsRepoPaths = await context.diagnosticsCollector.requestedRepoPaths()
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
    XCTAssertEqual(context.model.versionInfo.repoSchemaVersion, 2)
    XCTAssertNil(context.model.versionError)
    XCTAssertEqual(context.model.diagnosticsState, .collected(context.diagnosticsSnapshot))
    XCTAssertEqual(diagnosticsRepoPaths, [context.repoURL.path])
    XCTAssertEqual(context.logsOpener.openedRepoPaths, [context.repoURL.path])
    assertAdvancedSettingsCopiedSummary(context.summaryCopier.copiedSummaries)
}

private func assertAdvancedSettingsCopiedSummary(_ copiedSummaries: [String]) {
    XCTAssertEqual(copiedSummaries.count, 1)
    XCTAssertTrue(copiedSummaries[0].contains("App version: 9.8.7 (654)"))
    XCTAssertTrue(copiedSummaries[0].contains("Core version: 0.1.0-test"))
    XCTAssertTrue(copiedSummaries[0].contains("Repo schema version: v2"))
    XCTAssertTrue(copiedSummaries[0].contains("Diagnostics exclude original file contents"))
}

@MainActor
private func assertAdvancedSettingsRepairExit(
    shell: OnboardingModel,
    opening: RepositoryOpeningResult,
    context: AdvancedSettingsIntegrationContext,
    recoveryRequests: [String]
) {
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
    XCTAssertEqual(recoveryRequests, [])
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
    let logsOpener: AdvancedSettingsRecordingLogsOpener
    let summaryCopier: RecordingDiagnosticSummaryCopier
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

    let diagnosticsSnapshot = DiagnosticsSnapshotSnapshot(
        snapshotPath: advancedSettingsDiagnosticsPath(repoURL: repoURL),
        createdAt: 1_778_000_000,
        warnings: ["paths redacted"]
    )
    let diagnosticsCollector = ShellRecordingDiagnosticsCollector(result: .success(diagnosticsSnapshot))
    let logsOpener = AdvancedSettingsRecordingLogsOpener(result: .success(advancedSettingsLogsPath(repoURL: repoURL)))
    let summaryCopier = RecordingDiagnosticSummaryCopier()
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
    logsOpener: AdvancedSettingsRecordingLogsOpener,
    summaryCopier: RecordingDiagnosticSummaryCopier
) -> AdvancedSettingsModel {
    AdvancedSettingsModel(
        repoPath: repoURL.path,
        loader: bridge,
        updater: bridge,
        rootOverviewInspector: LocalRootOverviewFileInspector(),
        diagnosticsCollector: diagnosticsCollector,
        appVersionReader: AdvancedSettingsStaticAppVersionReader(version: "9.8.7 (654)"),
        coreVersionReader: AdvancedSettingsStaticCoreVersionReader(version: "0.1.0-test"),
        metadataReader: SQLiteExistingRepositoryMetadataReader(),
        logsOpener: logsOpener,
        summaryCopier: summaryCopier,
        errorMapper: bridge
    )
}

private func advancedSettingsLogsPath(repoURL: URL) -> String {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("logs", isDirectory: true)
        .path
}

private func advancedSettingsDiagnosticsPath(repoURL: URL) -> String {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("diagnostics", isDirectory: true)
        .appendingPathComponent("advanced-settings-diagnostics.zip")
        .path
}

@MainActor
private func loadedAdvancedSettingsModel(
    diagnosticsCollector: any CoreDiagnosticsCollecting = ShellRecordingDiagnosticsCollector(result: .success(
        DiagnosticsSnapshotSnapshot(snapshotPath: "/tmp/repo/.areamatrix/diagnostics/advanced-settings-diagnostics.zip",
                                    createdAt: 1_778_000_000,
                                    warnings: [])
    )),
    logsOpener: (any AdvancedSettingsLogFolderOpening)? = nil
) async -> AdvancedSettingsModel {
    let resolvedLogsOpener = logsOpener ?? AdvancedSettingsRecordingLogsOpener(result: .success(
        "/tmp/repo/.areamatrix/logs"
    ))
    let model = AdvancedSettingsModel(
        repoPath: "/tmp/repo",
        loader: AdvancedSettingsStaticConfigLoader(config: .advancedSettingsFixture(repoPath: "/tmp/repo")),
        updater: AdvancedSettingsNoopConfigUpdater(),
        rootOverviewInspector: StaticRootOverviewInspector(status: .missing),
        diagnosticsCollector: diagnosticsCollector,
        appVersionReader: AdvancedSettingsStaticAppVersionReader(version: "1.0.0"),
        coreVersionReader: AdvancedSettingsStaticCoreVersionReader(version: "0.1.0"),
        metadataReader: AdvancedSettingsStaticMetadataReader(schemaVersion: 1),
        logsOpener: resolvedLogsOpener,
        summaryCopier: RecordingDiagnosticSummaryCopier(),
        errorMapper: CoreBridge()
    )
    await model.load()
    return model
}

private actor AdvancedSettingsStaticConfigLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor AdvancedSettingsFailingConfigLoader: CoreConfigurationLoading {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        throw error
    }
}

private actor AdvancedSettingsNoopConfigUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

private struct StaticRootOverviewInspector: RootOverviewFileInspecting {
    let status: RootOverviewFileStatus

    func status(repoPath _: String) -> RootOverviewFileStatus {
        status
    }
}

private struct AdvancedSettingsStaticAppVersionReader: AppVersionReading {
    let version: String

    func appVersion() -> String {
        version
    }
}

private actor AdvancedSettingsStaticCoreVersionReader: CoreVersionReading {
    let version: String

    init(version: String) {
        self.version = version
    }

    func coreVersion() async throws -> String {
        version
    }
}

private actor AdvancedSettingsStaticMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    init(schemaVersion: Int64) {
        self.schemaVersion = schemaVersion
    }

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

@MainActor
private final class AdvancedSettingsRecordingLogsOpener: AdvancedSettingsLogFolderOpening {
    private let result: Result<String, Error>
    private(set) var openedRepoPaths: [String] = []

    init(result: Result<String, Error>) {
        self.result = result
    }

    func openLogsFolder(repoPath: String) throws -> String {
        openedRepoPaths.append(repoPath)
        return try result.get()
    }
}

@MainActor
private final class RecordingDiagnosticSummaryCopier: AdvancedSettingsDiagnosticSummaryCopying {
    private(set) var copiedSummaries: [String] = []

    func copyDiagnosticSummary(_ summary: String) throws {
        copiedSummaries.append(summary)
    }
}

private actor RecordingStartupRecoverer: CoreStartupRecovering {
    private var repoPaths: [String] = []

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        repoPaths.append(repoPath)
        return RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

private func advancedSettingsTemporaryDirectory() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixAdvancedSettings")
}

private extension RepoConfigSnapshot {
    static func advancedSettingsFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
            repoPath: repoPath,
            defaultMode: "Copied",
            overviewOutput: "GeneratedOnly",
            aiEnabled: false,
            locale: "system",
            iCloudWarn: true,
            enableExtensionRules: true,
            enableKeywordRules: true,
            fallbackToInbox: true,
            allowReplaceDuringImport: false
        )
    }
}
