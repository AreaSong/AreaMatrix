@testable import AreaMatrix
import XCTest

final class AboutSettingsPageFeatureTests: XCTestCase {
    @MainActor
    func testLoadShowsAppCoreAndSchemaVersionsThroughDeclaredReaders() async {
        let coreReader = AboutSettingsStaticCoreVersionReader(result: .success("0.1.0"))
        let metadataReader = AboutSettingsStaticMetadataReader(result: .success(ExistingRepositoryMetadataSnapshot(
            schemaVersion: 1,
            lastOpenedAt: nil
        )))
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: AboutSettingsStaticAppVersionReader(version: "1.2.3 (45)"),
            coreVersionReader: coreReader,
            metadataReader: metadataReader,
            diagnosticsExporter: AboutDiagnosticsExporter(result: .success(.fixture())),
            externalLinkOpener: AboutSettingsRecordingExternalLinkOpener(result: .success),
            logsOpener: AboutSettingsRecordingLogsOpener(result: .success),
            stringCopier: AboutSettingsRecordingStringCopier(),
            diagnosticsRevealer: AboutDiagnosticsRevealer(result: .success),
            errorMapper: AboutSettingsStaticErrorMapper(),
            accessibilityAnnouncer: AboutSettingsRecordingAnnouncer()
        )

        await model.load()
        let coreVersionRequestCount = await coreReader.requestCount()
        let metadataRequestedPaths = await metadataReader.requestedPaths()

        XCTAssertEqual(model.versionInfo, AboutSettingsVersionInfo(
            appVersion: "1.2.3 (45)",
            coreVersion: "0.1.0",
            schemaVersion: "v1"
        ))
        XCTAssertNil(model.versionError)
        XCTAssertEqual(coreVersionRequestCount, 1)
        XCTAssertEqual(metadataRequestedPaths, ["/tmp/repo"])
    }

    @MainActor
    func testSchemaFailureKeepsAboutPaneUsableWithUnknownAndDiagnosticsHint() async {
        let model = AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: AboutSettingsStaticAppVersionReader(version: "1.0"),
            coreVersionReader: AboutSettingsStaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: AboutSettingsStaticMetadataReader(result: .failure(CoreError.Db(message: "missing"))),
            diagnosticsExporter: AboutDiagnosticsExporter(result: .success(.fixture())),
            externalLinkOpener: AboutSettingsRecordingExternalLinkOpener(result: .success),
            logsOpener: AboutSettingsRecordingLogsOpener(result: .success),
            stringCopier: AboutSettingsRecordingStringCopier(),
            diagnosticsRevealer: AboutDiagnosticsRevealer(result: .success),
            errorMapper: AboutSettingsStaticErrorMapper(),
            accessibilityAnnouncer: AboutSettingsRecordingAnnouncer()
        )

        await model.load()

        XCTAssertEqual(model.versionInfo.schemaVersion, "Unknown")
        XCTAssertEqual(model.versionError?.message, "Schema version unavailable")
        XCTAssertEqual(model.versionError?.recovery, "Collect diagnostics...")
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
        let copier = AboutSettingsRecordingStringCopier()
        let announcer = AboutSettingsRecordingAnnouncer()
        let model = aboutSettingsModel(
            externalLinkOpener: AboutSettingsRecordingExternalLinkOpener(result: .failure),
            logsOpener: AboutSettingsRecordingLogsOpener(result: .failure),
            stringCopier: copier,
            accessibilityAnnouncer: announcer
        )

        model.openExternalLink(.github)
        XCTAssertEqual(model.actionFeedback, .failed(AboutSettingsError(
            message: "GitHub link could not be opened",
            recovery: "Copy the URL and open it in your browser.",
            copyableDetail: AboutExternalLink.github.urlString
        )))
        model.copyActionDetail(AboutSettingsError(
            message: "GitHub link could not be opened",
            recovery: "Copy the URL and open it in your browser.",
            copyableDetail: AboutExternalLink.github.urlString
        ))

        model.openLogs()

        XCTAssertEqual(copier.values, [AboutExternalLink.github.urlString])
        XCTAssertEqual(announcer.messages, ["GitHub link could not be opened", "Open logs failed"])
        if case let .failed(error) = model.actionFeedback {
            XCTAssertEqual(error.message, "Open logs failed")
            XCTAssertEqual(error.copyableDetail, "/tmp/repo/.areamatrix/logs")
        } else {
            XCTFail("Expected a logs failure banner")
        }
    }

    @MainActor
    private func aboutSettingsModel(
        diagnosticsExporter: any AboutDiagnosticsExporting =
            AboutDiagnosticsExporter(result: .success(.fixture())),
        externalLinkOpener: any AboutExternalLinkOpening =
            AboutSettingsRecordingExternalLinkOpener(result: .success),
        logsOpener: any AboutLogsOpening = AboutSettingsRecordingLogsOpener(result: .success),
        stringCopier: AboutSettingsRecordingStringCopier = AboutSettingsRecordingStringCopier(),
        accessibilityAnnouncer: AboutSettingsRecordingAnnouncer = AboutSettingsRecordingAnnouncer()
    ) -> AboutSettingsModel {
        AboutSettingsModel(
            repoPath: "/tmp/repo",
            appVersionReader: AboutSettingsStaticAppVersionReader(version: "1.0"),
            coreVersionReader: AboutSettingsStaticCoreVersionReader(result: .success("0.1.0")),
            metadataReader: AboutSettingsStaticMetadataReader(result: .success(ExistingRepositoryMetadataSnapshot(
                schemaVersion: 1,
                lastOpenedAt: nil
            ))),
            diagnosticsExporter: diagnosticsExporter,
            externalLinkOpener: externalLinkOpener,
            logsOpener: logsOpener,
            stringCopier: stringCopier,
            diagnosticsRevealer: AboutDiagnosticsRevealer(result: .success),
            errorMapper: AboutSettingsStaticErrorMapper(),
            accessibilityAnnouncer: accessibilityAnnouncer
        )
    }
}

private struct AboutSettingsStaticAppVersionReader: AppVersionReading {
    let version: String

    func appVersion() -> String {
        version
    }
}

private actor AboutSettingsStaticCoreVersionReader: CoreVersionReading {
    private let result: Result<String, Error>
    private var count = 0

    init(result: Result<String, Error>) {
        self.result = result
    }

    func coreVersion() async throws -> String {
        count += 1
        return try result.get()
    }

    func requestCount() -> Int {
        count
    }
}

private actor AboutSettingsStaticMetadataReader: ExistingRepositoryMetadataReading {
    private let result: Result<ExistingRepositoryMetadataSnapshot, Error>
    private var paths: [String] = []

    init(result: Result<ExistingRepositoryMetadataSnapshot, Error>) {
        self.result = result
    }

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        paths.append(repoPath)
        return try result.get()
    }

    func requestedPaths() -> [String] {
        paths
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

private final class AboutSettingsRecordingExternalLinkOpener: AboutExternalLinkOpening {
    enum ResultState {
        case success
        case failure
    }

    private let result: ResultState
    private(set) var openedLinks: [AboutExternalLink] = []

    init(result: ResultState) {
        self.result = result
    }

    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        openedLinks.append(link)
        if result == .failure {
            throw AboutSettingsPlatformError.openRejected(link.urlString)
        }
        return link.urlString
    }
}

private final class AboutSettingsRecordingLogsOpener: AboutLogsOpening {
    enum ResultState {
        case success
        case failure
    }

    private let result: ResultState
    private(set) var openedRepoPaths: [String] = []

    init(result: ResultState) {
        self.result = result
    }

    @MainActor
    func logsPath(repoPath: String) -> String {
        "\(repoPath)/.areamatrix/logs"
    }

    @MainActor
    func openLogs(repoPath: String) throws -> String {
        openedRepoPaths.append(repoPath)
        let path = logsPath(repoPath: repoPath)
        if result == .failure {
            throw AboutSettingsPlatformError.openRejected(path)
        }
        return path
    }
}

private final class AboutSettingsRecordingStringCopier: AboutStringCopying {
    private(set) var values: [String] = []

    @MainActor
    func copy(_ value: String) throws {
        values.append(value)
    }
}

private final class AboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    enum ResultState {
        case success
        case failure
    }

    private let result: ResultState
    private(set) var paths: [String] = []

    init(result: ResultState) {
        self.result = result
    }

    @MainActor
    func revealDiagnostics(at path: String) throws {
        paths.append(path)
        if result == .failure {
            throw AboutSettingsPlatformError.openRejected(path)
        }
    }
}

private actor AboutSettingsStaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        let message = switch error {
        case .Db:
            "Collect diagnostics..."
        default:
            "Retry."
        }
        return CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: message,
            severity: .medium,
            suggestedAction: message,
            recoverability: .retryable,
            rawContext: error.localizedDescription
        )
    }
}

private final class AboutSettingsRecordingAnnouncer: AccessibilityAnnouncing {
    private(set) var messages: [String] = []

    @MainActor
    func announce(_ message: String) {
        messages.append(message)
    }
}

private extension AboutDiagnosticsExportSnapshot {
    static func fixture() -> AboutDiagnosticsExportSnapshot {
        AboutDiagnosticsExportSnapshot(
            exportPath: "/tmp/AreaMatrix/Diagnostics/s1-31",
            createdAt: 1_714_000_000,
            warnings: []
        )
    }
}

private func makeAboutSettingsTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("areamatrix-about-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
