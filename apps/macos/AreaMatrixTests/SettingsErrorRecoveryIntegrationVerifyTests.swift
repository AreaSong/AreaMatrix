@testable import AreaMatrix
import XCTest

final class SettingsRecoveryIntegrationTests: XCTestCase {
    @MainActor
    func testSettingsErrorRecoveryClosureUsesRealCoreForBoundCapabilitiesAndSafeRoutes() async throws {
        let context = try await SettingsRecoveryIntegrationContext.make()
        defer { context.cleanup() }

        try await verifyGeneralSettingsAndImportDefaults(context)
        try await verifyClassifierRepositoryAndOverview(context)
        try await verifyIntegrationsAdvancedAboutAndRecovery(context)
    }
}

@MainActor
private func verifyGeneralSettingsAndImportDefaults(_ context: SettingsRecoveryIntegrationContext) async throws {
    let general = GeneralSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        rootOverviewInspector: LocalRootOverviewFileInspector(),
        rootOverviewRevealer: RecordingRepositoryFileRevealer(),
        ignoreRulesManager: NoopRepositoryIgnoreRulesManager(),
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
    let shell = OnboardingModel(helpOpener: NoopWelcomeHelpOpener())
    shell.route = .mainList(opening)
    shell.showGeneralSettings(opening: opening)
    shell.startImportEntry(opening: opening, source: .filePicker, urls: [context.sourceURL])
    XCTAssertEqual(shell.settingsGeneralSelectedTab, "general")
    XCTAssertEqual(shell.pendingImportEntry?.defaultStorageMode, .move)
}

@MainActor
private func verifyClassifierRepositoryAndOverview(_ context: SettingsRecoveryIntegrationContext) async throws {
    let classifier = ClassifierSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        predictor: context.bridge,
        errorMapper: context.bridge,
        accessibilityAnnouncer: NoopAccessibilityAnnouncer()
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

    let generatedRevealer = RecordingRepositoryFileRevealer()
    let repository = RepositorySettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        repositoryOpener: context.bridge,
        fileLister: context.bridge,
        scanSessionReader: context.bridge,
        existingRepositoryMetadataReader: SQLiteExistingRepositoryMetadataReader(),
        generatedOverviewRevealer: generatedRevealer,
        diagnosticsCollector: makeSettingsRecoveryDiagnosticsCollector(context),
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
    XCTAssertEqual(
        generatedRevealer.requests.map(\.relativePath),
        [RepositorySettingsSummary.generatedOverviewRelativePath]
    )
}

@MainActor
private func verifyIntegrationsAdvancedAboutAndRecovery(_ context: SettingsRecoveryIntegrationContext) async throws {
    let integrations = IntegrationsSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        errorMapper: context.bridge,
        statusDetector: StaticICloudStatusDetector(),
        finderOpener: RecordingRepositoryFinderOpener(),
        helpOpener: NoopICloudHelpOpener()
    )
    await integrations.load()
    await integrations.setICloudWarningsEnabled(false)

    let advanced = makeSettingsRecoveryAdvancedModel(context)
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
    try await verifySettingsRecoveryAboutAndRepairRoute(context)
}

@MainActor
private func makeSettingsRecoveryAdvancedModel(_ context: SettingsRecoveryIntegrationContext) -> AdvancedSettingsModel {
    AdvancedSettingsModel(
        repoPath: context.repoURL.path,
        loader: context.bridge,
        updater: context.bridge,
        rootOverviewInspector: LocalRootOverviewFileInspector(),
        diagnosticsCollector: makeSettingsRecoveryDiagnosticsCollector(context),
        appVersionReader: StaticAppVersionReader(version: "2.3.0"),
        coreVersionReader: context.bridge,
        metadataReader: SQLiteExistingRepositoryMetadataReader(),
        logsOpener: RecordingAdvancedSettingsLogsOpener(logsPath: "\(context.repoURL.path)/.areamatrix/logs"),
        summaryCopier: RecordingAdvancedDiagnosticCopier(),
        errorMapper: context.bridge
    )
}

private func makeSettingsRecoveryDiagnosticsCollector(
    _ context: SettingsRecoveryIntegrationContext
) -> RecordingDiagnosticsCollector {
    RecordingDiagnosticsCollector(snapshot: .settingsErrorRecoveryFixture(repoPath: context.repoURL.path))
}

@MainActor
private func verifySettingsRecoveryAboutAndRepairRoute(_ context: SettingsRecoveryIntegrationContext) async throws {
    let about = AboutSettingsModel(
        repoPath: context.repoURL.path,
        appVersionReader: StaticAppVersionReader(version: "2.3.0"),
        coreVersionReader: context.bridge,
        metadataReader: SQLiteExistingRepositoryMetadataReader(),
        diagnosticsExporter: LocalAboutDiagnosticsExporter(baseDirectory: context.diagnosticsURL),
        externalLinkOpener: NoopAboutExternalLinkOpener(),
        logsOpener: RecordingAboutLogsOpener(),
        stringCopier: RecordingAboutStringCopier(),
        diagnosticsRevealer: NoopAboutDiagnosticsRevealer(),
        errorMapper: context.bridge,
        accessibilityAnnouncer: NoopAccessibilityAnnouncer()
    )
    await about.load()
    about.requestDiagnosticsExport()
    await about.collectDiagnostics()

    XCTAssertEqual(about.versionInfo.schemaVersion, "v2")
    XCTAssertNotEqual(about.versionInfo.coreVersion, "Unknown")
    if case let .collected(snapshot) = about.diagnosticsState {
        let report = try String(contentsOf: URL(fileURLWithPath: snapshot.exportPath)
            .appendingPathComponent("about-diagnostics.txt"))
        XCTAssertTrue(report.contains("User file contents: excluded"))
        XCTAssertFalse(report.contains(context.repoURL.path))
    } else {
        XCTFail("Expected About diagnostics export to complete")
    }

    let mapping = await context.bridge.mapCoreError(CoreError.Db(message: "database corrupted"))
    let shell = OnboardingModel(helpOpener: NoopWelcomeHelpOpener())
    shell.route = .mainRepoError(context.repoURL.path, mapping)
    shell.openMainRepositoryRepair(repoPath: context.repoURL.path)
    XCTAssertEqual(
        shell.route,
        .dbRepairConfirm(DatabaseRepairRouteState(
            repoPath: context.repoURL.path,
            scanSession: nil,
            mapping: mapping,
            returnRoute: .mainRepoError(mapping)
        ))
    )
}

private struct SettingsRecoveryIntegrationContext {
    let repoURL: URL
    let sourceRootURL: URL
    let sourceURL: URL
    let readmeURL: URL
    let rootOverviewURL: URL
    let generatedOverviewURL: URL
    let diagnosticsURL: URL
    let bridge: CoreBridge

    static func make() async throws -> SettingsRecoveryIntegrationContext {
        let repoURL = try temporaryDirectory(prefix: "AreaMatrixSettingsRecoveryRepo")
        let sourceRootURL = try temporaryDirectory(prefix: "AreaMatrixSettingsRecoverySource")
        let diagnosticsURL = try temporaryDirectory(prefix: "AreaMatrixSettingsRecoveryDiagnostics")
        let sourceURL = sourceRootURL.appendingPathComponent("Invoice_2026Q1.pdf")
        try Data("settings recovery invoice bytes".utf8).write(to: sourceURL)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent(".areamatrix/logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        let readmeURL = repoURL.appendingPathComponent("README.md")
        try "user readme\n".write(to: readmeURL, atomically: true, encoding: .utf8)

        return SettingsRecoveryIntegrationContext(
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
        removeTestTemporaryItems(repoURL, sourceRootURL, diagnosticsURL)
    }

    private static func temporaryDirectory(prefix: String) throws -> URL {
        try makeTestTemporaryDirectory(named: prefix)
    }
}
