@testable import AreaMatrix
import XCTest

final class AdvancedSettingsIntegrationTests: XCTestCase {
    @MainActor
    func testS130PageIntegrationConnectsDeclaredCapabilitiesDiagnosticsLogsAndRecoveryExit() async throws {
        let context = try await makeS130IntegrationContext()
        defer {
            try? FileManager.default.removeItem(at: context.repoURL)
            try? FileManager.default.removeItem(at: context.sourceRootURL)
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

        try await assertS130SavedConfig(context)

        _ = try await context.bridge.importIndexedFile(
            repoPath: context.repoURL.path,
            sourceURL: context.sourceURL,
            overrideCategory: "docs",
            overrideFilename: "s130-source.txt"
        )

        try await assertS130DiagnosticsAndOverview(context)

        let opening = RepositoryOpeningResult.shellFixture(repoPath: context.repoURL.path, fileCount: 1)
        let recoverer = S130RecordingStartupRecoverer()
        let shell = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            startupRecoverer: recoverer,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )
        shell.route = .settingsGeneral(opening)
        shell.settingsGeneralSelectedTab = "advanced"
        shell.openMainRepositoryRepair(repoPath: context.repoURL.path)
        let recoveryRequests = await recoverer.requestedRepoPaths()

        assertS130RepairExit(shell: shell, opening: opening, context: context, recoveryRequests: recoveryRequests)
    }

    @MainActor
    func testS130LoadFailureShowsRecoverableErrorStateWithoutMockingSuccess() async {
        let model = AdvancedSettingsModel(
            repoPath: "/tmp/s130-broken-repo",
            loader: S130FailingConfigLoader(error: CoreError.Config(reason: "invalid repo_config")),
            updater: S130NoopConfigUpdater(),
            errorMapper: CoreBridge()
        )

        await model.load()

        guard case let .failed(error) = model.loadState else {
            return XCTFail("Expected S1-30 advanced settings load to fail through the error state")
        }
        XCTAssertEqual(error.message, "Unable to load advanced settings")
        XCTAssertFalse(error.recovery.isEmpty)
        XCTAssertNil(model.draft)
        XCTAssertNil(model.savedConfig)
        XCTAssertFalse(model.hasRetryableSave)
    }

    @MainActor
    func testS130LogFolderFailureKeepsPageLoadedWithRecoverableError() async {
        let model = await loadedS130Model(
            logsOpener: S130RecordingLogsOpener(result: .failure(AdvancedSettingsLogFolderError.missing(
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
    func testS130DiagnosticsFailureMapsCoreErrorAndDoesNotMockSuccess() async {
        let model = await loadedS130Model(
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
private func assertS130SavedConfig(_ context: S130IntegrationContext) async throws {
    let savedConfig = try await context.bridge.loadConfig(repoPath: context.repoURL.path)
    XCTAssertEqual(savedConfig.overviewOutput, "RootAreaMatrixFile")
    XCTAssertTrue(savedConfig.allowReplaceDuringImport)
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.rootOverviewURL.path))
}

@MainActor
private func assertS130DiagnosticsAndOverview(_ context: S130IntegrationContext) async throws {
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
    XCTAssertEqual(context.model.versionInfo.repoSchemaVersion, 1)
    XCTAssertNil(context.model.versionError)
    XCTAssertEqual(context.model.diagnosticsState, .collected(context.diagnosticsSnapshot))
    XCTAssertEqual(diagnosticsRepoPaths, [context.repoURL.path])
    XCTAssertEqual(context.logsOpener.openedRepoPaths, [context.repoURL.path])
    assertS130CopiedSummary(context.summaryCopier.copiedSummaries)
}

private func assertS130CopiedSummary(_ copiedSummaries: [String]) {
    XCTAssertEqual(copiedSummaries.count, 1)
    XCTAssertTrue(copiedSummaries[0].contains("App version: 9.8.7 (654)"))
    XCTAssertTrue(copiedSummaries[0].contains("Core version: 0.1.0-test"))
    XCTAssertTrue(copiedSummaries[0].contains("Repo schema version: v1"))
    XCTAssertTrue(copiedSummaries[0].contains("Diagnostics exclude original file contents"))
}

@MainActor
private func assertS130RepairExit(
    shell: OnboardingModel,
    opening: RepositoryOpeningResult,
    context: S130IntegrationContext,
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

private struct S130IntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let sourceURL: URL
    let readmeURL: URL
    let rootOverviewURL: URL
    let generatedOverviewURL: URL
    let diagnosticsSnapshot: DiagnosticsSnapshotSnapshot
    let diagnosticsCollector: ShellRecordingDiagnosticsCollector
    let logsOpener: S130RecordingLogsOpener
    let summaryCopier: S130RecordingDiagnosticSummaryCopier
    let bridge: CoreBridge
    let model: AdvancedSettingsModel
}

@MainActor
private func makeS130IntegrationContext() async throws -> S130IntegrationContext {
    let repoURL = try s130TemporaryDirectory()
    var cleanupURLs = [repoURL]
    var didSucceed = false
    defer {
        if !didSucceed {
            cleanupURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    let (sourceRootURL, sourceURL) = try makeS130SourceFixture()
    cleanupURLs.append(sourceRootURL)

    let bridge = CoreBridge()
    try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
    let readmeURL = try makeS130RepositoryFiles(repoURL: repoURL)

    let diagnosticsSnapshot = DiagnosticsSnapshotSnapshot(
        snapshotPath: s130DiagnosticsPath(repoURL: repoURL),
        createdAt: 1_778_000_000,
        warnings: ["paths redacted"]
    )
    let diagnosticsCollector = ShellRecordingDiagnosticsCollector(result: .success(diagnosticsSnapshot))
    let logsOpener = S130RecordingLogsOpener(result: .success(s130LogsPath(repoURL: repoURL)))
    let summaryCopier = S130RecordingDiagnosticSummaryCopier()
    let model = s130IntegrationModel(repoURL: repoURL, bridge: bridge, diagnosticsCollector: diagnosticsCollector,
                                     logsOpener: logsOpener, summaryCopier: summaryCopier)

    didSucceed = true
    return S130IntegrationContext(
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

private func makeS130SourceFixture() throws -> (rootURL: URL, sourceURL: URL) {
    let sourceRootURL = try s130TemporaryDirectory()
    let sourceURL = sourceRootURL.appendingPathComponent("s130-source.txt")
    try Data("s130 overview source".utf8).write(to: sourceURL)
    return (sourceRootURL, sourceURL)
}

private func makeS130RepositoryFiles(repoURL: URL) throws -> URL {
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: s130LogsPath(repoURL: repoURL)),
                                            withIntermediateDirectories: true)
    let readmeURL = repoURL.appendingPathComponent("README.md")
    try "user readme\n".write(to: readmeURL, atomically: true, encoding: .utf8)
    return readmeURL
}

@MainActor
private func s130IntegrationModel(
    repoURL: URL,
    bridge: CoreBridge,
    diagnosticsCollector: ShellRecordingDiagnosticsCollector,
    logsOpener: S130RecordingLogsOpener,
    summaryCopier: S130RecordingDiagnosticSummaryCopier
) -> AdvancedSettingsModel {
    AdvancedSettingsModel(
        repoPath: repoURL.path,
        loader: bridge,
        updater: bridge,
        rootOverviewInspector: LocalRootOverviewFileInspector(),
        diagnosticsCollector: diagnosticsCollector,
        appVersionReader: S130StaticAppVersionReader(version: "9.8.7 (654)"),
        coreVersionReader: S130StaticCoreVersionReader(version: "0.1.0-test"),
        metadataReader: SQLiteExistingRepositoryMetadataReader(),
        logsOpener: logsOpener,
        summaryCopier: summaryCopier,
        errorMapper: bridge
    )
}

private func s130LogsPath(repoURL: URL) -> String {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("logs", isDirectory: true)
        .path
}

private func s130DiagnosticsPath(repoURL: URL) -> String {
    repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("diagnostics", isDirectory: true)
        .appendingPathComponent("s1-30.zip")
        .path
}

@MainActor
private func loadedS130Model(
    diagnosticsCollector: any CoreDiagnosticsCollecting = ShellRecordingDiagnosticsCollector(result: .success(
        DiagnosticsSnapshotSnapshot(snapshotPath: "/tmp/repo/.areamatrix/diagnostics/s1-30.zip",
                                    createdAt: 1_778_000_000,
                                    warnings: [])
    )),
    logsOpener: (any AdvancedSettingsLogFolderOpening)? = nil
) async -> AdvancedSettingsModel {
    let resolvedLogsOpener = logsOpener ?? S130RecordingLogsOpener(result: .success(
        "/tmp/repo/.areamatrix/logs"
    ))
    let model = AdvancedSettingsModel(
        repoPath: "/tmp/repo",
        loader: S130StaticConfigLoader(config: .s130Fixture(repoPath: "/tmp/repo")),
        updater: S130NoopConfigUpdater(),
        rootOverviewInspector: S130StaticRootOverviewInspector(status: .missing),
        diagnosticsCollector: diagnosticsCollector,
        appVersionReader: S130StaticAppVersionReader(version: "1.0.0"),
        coreVersionReader: S130StaticCoreVersionReader(version: "0.1.0"),
        metadataReader: S130StaticMetadataReader(schemaVersion: 1),
        logsOpener: resolvedLogsOpener,
        summaryCopier: S130RecordingDiagnosticSummaryCopier(),
        errorMapper: CoreBridge()
    )
    await model.load()
    return model
}

private actor S130StaticConfigLoader: CoreConfigurationLoading {
    private let config: RepoConfigSnapshot

    init(config: RepoConfigSnapshot) {
        self.config = config
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        config
    }
}

private actor S130FailingConfigLoader: CoreConfigurationLoading {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func loadConfig(repoPath _: String) async throws -> RepoConfigSnapshot {
        throw error
    }
}

private actor S130NoopConfigUpdater: CoreConfigurationUpdating {
    func updateConfig(repoPath _: String, newConfig _: RepoConfigSnapshot) async throws {}
}

private struct S130StaticRootOverviewInspector: RootOverviewFileInspecting {
    let status: RootOverviewFileStatus

    func status(repoPath _: String) -> RootOverviewFileStatus {
        status
    }
}

private struct S130StaticAppVersionReader: AppVersionReading {
    let version: String

    func appVersion() -> String {
        version
    }
}

private actor S130StaticCoreVersionReader: CoreVersionReading {
    let version: String

    init(version: String) {
        self.version = version
    }

    func coreVersion() async throws -> String {
        version
    }
}

private actor S130StaticMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64

    init(schemaVersion: Int64) {
        self.schemaVersion = schemaVersion
    }

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(schemaVersion: schemaVersion, lastOpenedAt: nil)
    }
}

@MainActor
private final class S130RecordingLogsOpener: AdvancedSettingsLogFolderOpening {
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
private final class S130RecordingDiagnosticSummaryCopier: AdvancedSettingsDiagnosticSummaryCopying {
    private(set) var copiedSummaries: [String] = []

    func copyDiagnosticSummary(_ summary: String) throws {
        copiedSummaries.append(summary)
    }
}

private actor S130RecordingStartupRecoverer: CoreStartupRecovering {
    private var repoPaths: [String] = []

    func recoverOnStartup(repoPath: String) async throws -> RecoveryReportSnapshot {
        repoPaths.append(repoPath)
        return RecoveryReportSnapshot(cleanedStagingFiles: 0, revertedStagingDbRows: 0, warnings: [])
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

private func s130TemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS130-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension RepoConfigSnapshot {
    static func s130Fixture(repoPath: String) -> RepoConfigSnapshot {
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
