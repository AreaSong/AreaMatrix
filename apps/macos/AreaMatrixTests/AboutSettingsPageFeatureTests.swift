@testable import AreaMatrix
import XCTest

final class AboutSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadShowsAppCoreAndSchemaVersionsThroughDeclaredReaders() async {
        let coreReader = StaticCoreVersionReader(result: .success("0.1.0"))
        let metadataReader = StaticExistingRepositoryMetadataReader(schemaVersion: 1)
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.2.3 (45)"),
            coreVersionReader: coreReader,
            metadataReader: metadataReader,
            diagnosticsExporter: AboutDiagnosticsExporter(result: .success(.fixture())),
            externalLinkOpener: RecordingAboutExternalLinkOpener(),
            logsOpener: RecordingAboutLogsOpener(),
            stringCopier: RecordingAboutStringCopier(),
            diagnosticsRevealer: RecordingAboutDiagnosticsRevealer(),
            errorMapper: RecordingCoreErrorMapper.aboutSettings(),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
        )

        await model.load()

        XCTAssertEqual(model.versionInfo, AboutSettingsVersionInfo(
            appVersion: "1.2.3 (45)",
            coreVersion: "0.1.0",
            schemaVersion: "v1"
        ))
        XCTAssertNil(model.versionError)
        await coreReader.assertRequestCount(1)
        await metadataReader.assertRequestedPaths(["/tmp/repo"])
    }

    @MainActor
    func testSchemaFailureKeepsAboutPaneUsableWithUnknownAndDiagnosticsHint() async {
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.0"),
            coreVersionReader: StaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: StaticExistingRepositoryMetadataReader(result: .failure(CoreError.Db(message: "missing"))),
            diagnosticsExporter: AboutDiagnosticsExporter(result: .success(.fixture())),
            externalLinkOpener: RecordingAboutExternalLinkOpener(),
            logsOpener: RecordingAboutLogsOpener(),
            stringCopier: RecordingAboutStringCopier(),
            diagnosticsRevealer: RecordingAboutDiagnosticsRevealer(),
            errorMapper: RecordingCoreErrorMapper.aboutSettings(),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
        )

        await model.load()

        XCTAssertEqual(model.versionInfo.schemaVersion, L10n.string("Unknown"))
        XCTAssertEqual(model.versionError?.message, L10n.string("Schema version unavailable"))
        XCTAssertEqual(model.versionError?.recovery, L10n.string("Collect diagnostics..."))
    }

    @MainActor
    func testSchemaFailureDefaultsToBridgeErrorMappingAndKeepsAboutRecovery() async {
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.0"),
            coreVersionReader: StaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: StaticExistingRepositoryMetadataReader(result: .failure(CoreError.Db(message: "missing"))),
            diagnosticsExporter: AboutDiagnosticsExporter(result: .success(.fixture())),
            externalLinkOpener: RecordingAboutExternalLinkOpener(),
            logsOpener: RecordingAboutLogsOpener(),
            stringCopier: RecordingAboutStringCopier(),
            diagnosticsRevealer: RecordingAboutDiagnosticsRevealer(),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer()
        )

        await model.load()

        XCTAssertEqual(model.versionInfo.schemaVersion, L10n.string("Unknown"))
        XCTAssertEqual(model.versionError?.message, L10n.string("Schema version unavailable"))
        XCTAssertEqual(model.versionError?.recovery, L10n.string("Collect diagnostics..."))
    }

    @MainActor
    func testDiagnosticsRequiresPrivacyConfirmationAndUsesAboutOnlyExporter() async {
        let exporter = AboutDiagnosticsExporter(result: .success(.fixture()))
        let model = aboutSettingsModel(diagnosticsExporter: exporter)

        await model.load()

        await model.collectDiagnostics()
        let contextsBeforeConfirmation = await exporter.contexts()
        XCTAssertEqual(contextsBeforeConfirmation, [])

        model.requestDiagnosticsExport()
        XCTAssertEqual(model.diagnosticsState, .confirmingPrivacy)
        await model.collectDiagnostics()
        let contexts = await exporter.contexts()

        XCTAssertEqual(contexts, [AboutDiagnosticsExportContext(
            versionInfo: AboutSettingsVersionInfo(
                appVersion: "1.0",
                coreVersion: "0.1.0",
                schemaVersion: "v1"
            ),
            versionIssue: nil
        )])
        XCTAssertEqual(model.diagnosticsState, .collected(.fixture()))
    }

    @MainActor
    func testDiagnosticsExporterWritesRedactedAboutReportWithoutCoreSnapshotDependency() async throws {
        let exportRoot = try makeAboutSettingsTemporaryDirectory()
        let exporter = LocalAboutDiagnosticsExporter(baseDirectory: exportRoot)

        let snapshot = try await exporter.exportDiagnostics(context: AboutDiagnosticsExportContext(
            versionInfo: AboutSettingsVersionInfo(
                appVersion: "1.0",
                coreVersion: "0.1.0",
                schemaVersion: "Unknown"
            ),
            versionIssue: "Schema version unavailable"
        ))

        XCTAssertTrue(snapshot.exportPath.hasPrefix(exportRoot.path))
        let reportURL = URL(fileURLWithPath: snapshot.exportPath)
            .appendingPathComponent("about-diagnostics.txt")
        let report = try String(contentsOf: reportURL, encoding: .utf8)
        XCTAssertTrue(report.contains("App version: 1.0"))
        XCTAssertTrue(report.contains("Core version: 0.1.0"))
        XCTAssertTrue(report.contains("Schema version: Unknown"))
        XCTAssertTrue(report.contains("Version issue: Schema version unavailable"))
        XCTAssertTrue(report.contains("User file contents: excluded"))
        XCTAssertTrue(report.contains("Original file paths: redacted"))
        XCTAssertFalse(report.contains("/tmp/repo"))
    }

    @MainActor
    func testExternalLinksAndLogsStayInMacLayerWithCopyableRecovery() {
        let copier = RecordingAboutStringCopier()
        let announcer = RecordingAccessibilityAnnouncer()
        let model = aboutSettingsModel(
            externalLinkOpener: RecordingAboutExternalLinkOpener { link in
                throw AboutSettingsPlatformError.openRejected(link.urlString)
            },
            logsOpener: RecordingAboutLogsOpener { _, path in
                throw AboutSettingsPlatformError.openRejected(path)
            },
            stringCopier: copier,
            accessibilityAnnouncer: announcer
        )

        model.openExternalLink(.github)
        XCTAssertEqual(model.actionFeedback, .failed(AboutSettingsError(
            message: L10n.format("settings.about.linkOpenFailed", AboutExternalLink.github.title),
            recovery: L10n.string("Copy the URL and open it in your browser."),
            copyableDetail: AboutExternalLink.github.urlString
        )))
        model.copyActionDetail(AboutSettingsError(
            message: L10n.format("settings.about.linkOpenFailed", AboutExternalLink.github.title),
            recovery: L10n.string("Copy the URL and open it in your browser."),
            copyableDetail: AboutExternalLink.github.urlString
        ))

        model.openLogs()

        copier.assertCopiedValues([AboutExternalLink.github.urlString])
        announcer.assertAnnouncements([
            L10n.format("settings.about.linkOpenFailed", AboutExternalLink.github.title),
            L10n.string("Open logs failed")
        ])
        if case let .failed(error) = model.actionFeedback {
            XCTAssertEqual(error.message, L10n.string("Open logs failed"))
            XCTAssertEqual(error.copyableDetail, "/tmp/repo/.areamatrix/logs")
        } else {
            XCTFail("Expected a logs failure banner")
        }
    }

    @MainActor
    func testCancelledAboutDiagnosticsIgnoresLateExporterResult() async {
        let snapshot = AboutDiagnosticsExportSnapshot.fixture()
        let exporter = SuspendedAboutDiagnosticsExporter(result: .success(snapshot))
        let model = aboutSettingsModel(diagnosticsExporter: exporter)
        await model.load()

        model.requestDiagnosticsExport()
        let collection = Task { await model.collectDiagnostics() }
        await exporter.waitUntilStarted()
        XCTAssertEqual(model.diagnosticsState, .collecting)

        model.cancelDiagnosticsExport()
        await exporter.finish()
        await collection.value

        XCTAssertEqual(model.diagnosticsState, .idle)
        XCTAssertNil(model.actionFeedback)
    }

    @MainActor
    private func aboutSettingsModel(
        diagnosticsExporter: any AboutDiagnosticsExporting =
            AboutDiagnosticsExporter(result: .success(.fixture())),
        externalLinkOpener: (any AboutExternalLinkOpening)? = nil,
        logsOpener: (any AboutLogsOpening)? = nil,
        stringCopier: RecordingAboutStringCopier? = nil,
        accessibilityAnnouncer: RecordingAccessibilityAnnouncer? = nil
    ) -> AboutSettingsModel {
        AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: StaticAppVersionReader(version: "1.0"),
            coreVersionReader: StaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: StaticExistingRepositoryMetadataReader(schemaVersion: 1),
            diagnosticsExporter: diagnosticsExporter,
            externalLinkOpener: externalLinkOpener ?? RecordingAboutExternalLinkOpener(),
            logsOpener: logsOpener ?? RecordingAboutLogsOpener(),
            stringCopier: stringCopier ?? RecordingAboutStringCopier(),
            diagnosticsRevealer: RecordingAboutDiagnosticsRevealer(),
            errorMapper: RecordingCoreErrorMapper.aboutSettings(),
            accessibilityAnnouncer: accessibilityAnnouncer ?? RecordingAccessibilityAnnouncer()
        )
    }
}

private actor AboutDiagnosticsExporter: AboutDiagnosticsExporting {
    private let result: Result<AboutDiagnosticsExportSnapshot, Error>
    private var capturedContexts: [AboutDiagnosticsExportContext] = []

    init(result: Result<AboutDiagnosticsExportSnapshot, Error>) {
        self.result = result
    }

    func exportDiagnostics(context: AboutDiagnosticsExportContext) async throws -> AboutDiagnosticsExportSnapshot {
        capturedContexts.append(context)
        return try result.get()
    }

    func contexts() -> [AboutDiagnosticsExportContext] {
        capturedContexts
    }
}

private actor SuspendedAboutDiagnosticsExporter: AboutDiagnosticsExporting {
    private let result: Result<AboutDiagnosticsExportSnapshot, Error>
    private var startContinuations: [CheckedContinuation<Void, Never>] = []
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var canFinish = false

    init(result: Result<AboutDiagnosticsExportSnapshot, Error>) {
        self.result = result
    }

    func exportDiagnostics(context _: AboutDiagnosticsExportContext) async throws -> AboutDiagnosticsExportSnapshot {
        hasStarted = true
        startContinuations.forEach { $0.resume() }
        startContinuations.removeAll()
        if !canFinish {
            await withCheckedContinuation { finishContinuation = $0 }
        }
        return try result.get()
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startContinuations.append($0) }
    }

    func finish() {
        canFinish = true
        finishContinuation?.resume()
        finishContinuation = nil
    }
}

private extension AboutDiagnosticsExportSnapshot {
    static func fixture() -> AboutDiagnosticsExportSnapshot {
        AboutDiagnosticsExportSnapshot(
            exportPath: "/tmp/AreaMatrix/Diagnostics/about-settings-diagnostics",
            createdAt: 1_714_000_000,
            warnings: []
        )
    }
}

private func makeAboutSettingsTemporaryDirectory() throws -> URL {
    try makeTestTemporaryDirectory(named: "areamatrix-about")
}

private extension RecordingCoreErrorMapper {
    static func aboutSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            let message = switch error {
            case .Db:
                "Collect diagnostics..."
            default:
                "Retry."
            }
            return CoreErrorMappingSnapshot.testFixture(
                kind: .db,
                userMessage: message,
                severity: .medium,
                suggestedAction: message,
                recoverability: .retryable,
                rawContext: error.localizedDescription
            )
        }
    }
}
