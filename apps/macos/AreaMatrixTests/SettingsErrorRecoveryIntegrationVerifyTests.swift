import XCTest
@testable import AreaMatrix

final class SettingsErrorRecoveryIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testSettingsErrorRecoveryClosureUsesRealCoreForBoundCapabilitiesAndSafeRoutes() async throws {
        let context = try await Task31IntegrationContext.make()
        defer { context.cleanup() }

        try await verifyGeneralSettingsAndImportDefaults(context)
        try await verifyClassifierRepositoryAndOverview(context)
        try await verifyIntegrationsAdvancedAboutAndRecovery(context)
    }
}

@MainActor
private func verifyGeneralSettingsAndImportDefaults(_ context: Task31IntegrationContext) async throws {
    let general = GeneralSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        rootOverviewInspector: LocalRootOverviewFileInspector(),
        rootOverviewRevealer: Task31NoopFileRevealer(),
        ignoreRulesManager: Task31NoopIgnoreRulesManager(),
        errorMapper: context.bridge
    )

    await general.load()
    await general.requestStorageMode(.move)
    XCTAssertEqual(general.pendingStorageConfirmation, .move)
    await general.confirmPendingStorageMode()
    await general.requestOverviewOutput(.rootAreaMatrixFile)
    XCTAssertEqual(general.pendingRootOverviewStatus, .missing)
    await general.confirmRootOverview()

    let saved = try await context.bridge.loadConfig(repoPath: context.repoURL.path)
    XCTAssertEqual(saved.defaultMode, "Moved")
    XCTAssertEqual(saved.overviewOutput, "RootAreaMatrixFile")
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.rootOverviewURL.path))
    XCTAssertEqual(try String(contentsOf: context.readmeURL), "user readme\n")

    let opening = try await context.bridge.openConfiguredRepository(repoPath: context.repoURL.path)
    let shell = OnboardingModel(helpOpener: Task31NoopWelcomeHelpOpener())
    shell.route = .mainList(opening)
    shell.showGeneralSettings(opening: opening)
    shell.startImportEntry(opening: opening, source: .filePicker, urls: [context.sourceURL])
    XCTAssertEqual(shell.settingsGeneralSelectedTab, "general")
    XCTAssertEqual(shell.pendingImportEntry?.defaultStorageMode, .move)
}

@MainActor
private func verifyClassifierRepositoryAndOverview(_ context: Task31IntegrationContext) async throws {
    let classifier = ClassifierSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        predictor: context.bridge,
        errorMapper: context.bridge,
        accessibilityAnnouncer: Task31NoopAccessibilityAnnouncer()
    )

    await classifier.load()
    classifier.updatePreviewFilename("Invoice_2026Q1.pdf")
    await classifier.previewClassification()
    XCTAssertEqual(classifier.previewResult?.category, "finance")
    XCTAssertEqual(classifier.previewResult?.reason, .keyword)

    let imported = try await context.bridge.importIndexedFile(
        repoPath: context.repoURL.path,
        sourceURL: context.sourceURL,
        overrideCategory: "finance",
        overrideFilename: "Invoice_2026Q1.pdf"
    )
    XCTAssertEqual(imported.storageMode, "Indexed")
    XCTAssertEqual(imported.sourcePath, context.sourceURL.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.sourceURL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: context.repoURL.appendingPathComponent(imported.path).path))

    let generatedRevealer = Task31RecordingFileRevealer()
    let repository = RepositorySettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        repositoryOpener: context.bridge,
        fileLister: context.bridge,
        scanSessionReader: context.bridge,
        existingRepositoryMetadataReader: SQLiteExistingRepositoryMetadataReader(),
        generatedOverviewRevealer: generatedRevealer,
        diagnosticsCollector: Task31RecordingDiagnosticsCollector(),
        errorMapper: context.bridge
    )
    await repository.load()
    repository.revealGeneratedOverviewInFinder()

    XCTAssertEqual(repository.summary?.overviewMode, "Root AREAMATRIX.md enabled")
    XCTAssertEqual(repository.summary?.rootFile, "AREAMATRIX.md")
    XCTAssertEqual(repository.summary?.readmePolicy, "User file, never managed by AreaMatrix")
    XCTAssertEqual(repository.healthSummary?.databaseStatus, .ok)
    XCTAssertEqual(repository.healthSummary?.filesIndexed, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.generatedOverviewURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: context.rootOverviewURL.path))
    XCTAssertEqual(try String(contentsOf: context.readmeURL), "user readme\n")
    XCTAssertEqual(generatedRevealer.requests.map(\.relativePath), [RepositorySettingsSummary.generatedOverviewRelativePath])
}

@MainActor
private func verifyIntegrationsAdvancedAboutAndRecovery(_ context: Task31IntegrationContext) async throws {
    let integrations = IntegrationsSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        errorMapper: context.bridge,
        statusDetector: Task31StaticICloudDetector(),
        finderOpener: Task31NoopFinderOpener(),
        helpOpener: Task31NoopICloudHelpOpener()
    )
    await integrations.load()
    await integrations.setICloudWarningsEnabled(false)

    let advanced = makeTask31AdvancedModel(context)
    await advanced.load()
    await advanced.requestAllowReplaceDuringImport(true)
    XCTAssertTrue(advanced.isReplaceConfirmationPending)
    await advanced.confirmAllowReplaceDuringImport()
    await advanced.requestOverviewOutput(.generatedOnly)

    let saved = try await context.bridge.loadConfig(repoPath: context.repoURL.path)
    XCTAssertFalse(saved.iCloudWarn)
    XCTAssertTrue(saved.allowReplaceDuringImport)
    XCTAssertEqual(saved.overviewOutput, "GeneratedOnly")
    XCTAssertEqual(try String(contentsOf: context.readmeURL), "user readme\n")

    let report = try await context.bridge.recoverOnStartup(repoPath: context.repoURL.path)
    XCTAssertEqual(report.cleanedStagingFiles, 0)
    try await verifyTask31AboutAndRecoveryRoute(context)
}

@MainActor
private func makeTask31AdvancedModel(_ context: Task31IntegrationContext) -> AdvancedSettingsModel {
    AdvancedSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        rootOverviewInspector: LocalRootOverviewFileInspector(),
        diagnosticsCollector: Task31RecordingDiagnosticsCollector(),
        appVersionReader: Task31StaticAppVersionReader(version: "2.3.31"),
        coreVersionReader: context.bridge,
        metadataReader: SQLiteExistingRepositoryMetadataReader(),
        logsOpener: Task31RecordingAdvancedLogsOpener(),
        summaryCopier: Task31RecordingAdvancedSummaryCopier(),
        errorMapper: context.bridge
    )
}

@MainActor
private func verifyTask31AboutAndRecoveryRoute(_ context: Task31IntegrationContext) async throws {
    let about = AboutSettingsModel(
        repoPath: context.repoURL.path,
        appVersionReader: Task31StaticAppVersionReader(version: "2.3.31"),
        coreVersionReader: context.bridge,
        metadataReader: SQLiteExistingRepositoryMetadataReader(),
        diagnosticsExporter: LocalAboutDiagnosticsExporter(baseDirectory: context.diagnosticsURL),
        externalLinkOpener: Task31NoopAboutExternalLinkOpener(),
        logsOpener: Task31RecordingAboutLogsOpener(),
        stringCopier: Task31RecordingStringCopier(),
        diagnosticsRevealer: Task31NoopAboutDiagnosticsRevealer(),
        errorMapper: context.bridge,
        accessibilityAnnouncer: Task31NoopAccessibilityAnnouncer()
    )
    await about.load()
    about.requestDiagnosticsExport()
    await about.collectDiagnostics()

    XCTAssertEqual(about.versionInfo.schemaVersion, "v1")
    XCTAssertNotEqual(about.versionInfo.coreVersion, "Unknown")
    if case .collected(let snapshot) = about.diagnosticsState {
        let report = try String(contentsOf: URL(fileURLWithPath: snapshot.exportPath)
            .appendingPathComponent("about-diagnostics.txt"))
        XCTAssertTrue(report.contains("User file contents: excluded"))
        XCTAssertFalse(report.contains(context.repoURL.path))
    } else {
        XCTFail("Expected About diagnostics export to complete")
    }

    let mapping = await context.bridge.mapCoreError(CoreError.Db(message: "database corrupted"))
    let shell = OnboardingModel(helpOpener: Task31NoopWelcomeHelpOpener())
    shell.route = .mainRepoError(context.repoURL.path, mapping)
    shell.openMainRepositoryRepair(repoPath: context.repoURL.path)
    XCTAssertEqual(shell.route, .dbRepairConfirm(context.repoURL.path, nil, mapping))
}

private struct Task31IntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let sourceURL: URL
    let readmeURL: URL
    let rootOverviewURL: URL
    let generatedOverviewURL: URL
    let diagnosticsURL: URL
    let bridge: CoreBridge

    static func make() async throws -> Task31IntegrationContext {
        let repoURL = try temporaryDirectory(prefix: "AreaMatrixTask31Repo")
        let sourceRootURL = try temporaryDirectory(prefix: "AreaMatrixTask31Source")
        let diagnosticsURL = try temporaryDirectory(prefix: "AreaMatrixTask31Diagnostics")
        let sourceURL = sourceRootURL.appendingPathComponent("Invoice_2026Q1.pdf")
        try Data("task 31 invoice bytes".utf8).write(to: sourceURL)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent(".areamatrix/logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        let readmeURL = repoURL.appendingPathComponent("README.md")
        try "user readme\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        return Task31IntegrationContext(
            repoURL: repoURL,
            sourceRootURL: sourceRootURL,
            sourceURL: sourceURL,
            readmeURL: readmeURL,
            rootOverviewURL: repoURL.appendingPathComponent("AREAMATRIX.md"),
            generatedOverviewURL: repoURL.appendingPathComponent(".areamatrix/generated/root.md"),
            diagnosticsURL: diagnosticsURL,
            bridge: bridge
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repoURL)
        try? FileManager.default.removeItem(at: sourceRootURL)
        try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    private static func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class Task31NoopFileRevealer: RepositoryFileRevealing {
    @MainActor
    func revealFile(repoPath: String, relativePath: String) throws {}
}

private final class Task31RecordingFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private(set) var requests: [Request] = []

    @MainActor
    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
    }
}

private final class Task31NoopIgnoreRulesManager: RepositoryIgnoreRulesManaging {
    @MainActor
    func openIgnoreRules(repoPath: String) throws {}

    @MainActor
    func createDefaultIgnoreRules(repoPath: String) throws {}
}

private struct Task31StaticICloudDetector: ICloudStatusDetecting {
    func snapshot(repoPath: String, config: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        IntegrationsICloudSnapshot(repositoryLocation: .localFolder, iCloudStatus: .unavailable)
    }
}

private final class Task31NoopFinderOpener: RepositoryFinderOpening {
    @MainActor
    func openRepositoryInFinder(repoPath: String) throws {}
}

private struct Task31NoopICloudHelpOpener: ICloudHelpOpening {
    @MainActor
    func openICloudHelp() throws {}
}

private actor Task31RecordingDiagnosticsCollector: CoreDiagnosticsCollecting {
    private var repoPaths: [String] = []

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        return DiagnosticsSnapshotSnapshot(
            snapshotPath: "\(repoPath)/.areamatrix/diagnostics/task-31.zip",
            createdAt: 1_778_031_000,
            warnings: []
        )
    }
}

private struct Task31StaticAppVersionReader: AppVersionReading {
    let version: String

    func appVersion() -> String { version }
}

private final class Task31RecordingAdvancedLogsOpener: AdvancedSettingsLogFolderOpening {
    @MainActor
    func openLogsFolder(repoPath: String) throws -> String {
        "\(repoPath)/.areamatrix/logs"
    }
}

private final class Task31RecordingAdvancedSummaryCopier: AdvancedSettingsDiagnosticSummaryCopying {
    private(set) var summaries: [String] = []

    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws {
        summaries.append(summary)
    }
}

private struct Task31NoopAboutExternalLinkOpener: AboutExternalLinkOpening {
    @MainActor
    func open(link: AboutExternalLink) throws -> String { link.urlString }
}

private struct Task31RecordingAboutLogsOpener: AboutLogsOpening {
    @MainActor
    func logsPath(repoPath: String) -> String { "\(repoPath)/.areamatrix/logs" }

    @MainActor
    func openLogs(repoPath: String) throws -> String { logsPath(repoPath: repoPath) }
}

private final class Task31RecordingStringCopier: AboutStringCopying {
    private(set) var values: [String] = []

    @MainActor
    func copy(_ value: String) throws {
        values.append(value)
    }
}

private struct Task31NoopAboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    @MainActor
    func revealDiagnostics(at path: String) throws {}
}

private struct Task31NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

private final class Task31NoopAccessibilityAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_ message: String) {}
}
