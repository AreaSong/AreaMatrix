import AppKit
import Foundation

enum AdvancedSettingsPlatformServices {
    static var rootOverviewInspector: any RootOverviewFileInspecting {
        AppPlatformServices.rootOverviewInspector
    }

    static var appVersionReader: any AppVersionReading {
        AppPlatformServices.appVersionReader
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        AppPlatformServices.existingRepositoryMetadataReader
    }

    static var diagnosticSummaryCopier: any AdvancedSettingsDiagnosticSummaryCopying {
        AdvancedSettingsDiagnosticCopier()
    }

    @MainActor
    static var diagnosticsPackageHandler: any DiagnosticsPackageHandling {
        DiagnosticsPackageHandler()
    }

    static var diagnosticsPackagePreviewer: any DiagnosticsPackagePreviewing {
        DiagnosticsPackagePreviewService()
    }
}

struct BundleAppVersionReader: AppVersionReading {
    func appVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Self.versionIdentifier(version: version, build: build)
    }

    static func versionIdentifier(version: String?, build: String?) -> String {
        let trimmedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBuild = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedVersion.isEmpty { return L10n.string("Unknown") }
        if trimmedBuild.isEmpty { return trimmedVersion }
        return "\(trimmedVersion)+\(trimmedBuild)"
    }
}

struct AdvancedSettingsDiagnosticCopier: AdvancedSettingsDiagnosticSummaryCopying {
    private let writer: any PasteboardStringWriting

    init(writer: any PasteboardStringWriting = AppPlatformServices.pasteboardStringWriter) {
        self.writer = writer
    }

    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws {
        guard writer.write(summary) else {
            throw AdvancedSettingsDiagnosticSummaryError.copyRejected
        }
    }
}

@MainActor
protocol DiagnosticsPackageHandling {
    func export(
        _ preview: DiagnosticPackagePreview,
        suggestedFileName: String
    ) throws -> URL?

    func openPackage() throws -> DiagnosticPackageInspection?
}

protocol DiagnosticsPackagePreviewing: Sendable {
    func makePreview(
        events: [ObservabilityEventSnapshot],
        privacySelection: DiagnosticPackagePrivacySelection,
        repositoryURL: URL?,
        summary: String
    ) async throws -> DiagnosticPackagePreview
}

actor DiagnosticsPackagePreviewService: DiagnosticsPackagePreviewing {
    private let exporter: DiagnosticPackageExporter

    init(exporter: DiagnosticPackageExporter = DiagnosticPackageExporter()) {
        self.exporter = exporter
    }

    func makePreview(
        events: [ObservabilityEventSnapshot],
        privacySelection: DiagnosticPackagePrivacySelection,
        repositoryURL: URL?,
        summary: String
    ) throws -> DiagnosticPackagePreview {
        try exporter.preview(
            events: events,
            privacySelection: privacySelection,
            repositoryURL: repositoryURL,
            summary: summary
        )
    }
}

@MainActor
struct DiagnosticsPackageHandler: DiagnosticsPackageHandling {
    private let exporter: DiagnosticPackageExporter
    private let reader: DiagnosticPackageReader
    private let panelService: DiagnosticPackagePanelService

    init(
        exporter: DiagnosticPackageExporter = DiagnosticPackageExporter(),
        reader: DiagnosticPackageReader = DiagnosticPackageReader(),
        panelService: DiagnosticPackagePanelService = DiagnosticPackagePanelService()
    ) {
        self.exporter = exporter
        self.reader = reader
        self.panelService = panelService
    }

    func export(
        _ preview: DiagnosticPackagePreview,
        suggestedFileName: String
    ) throws -> URL? {
        guard let destination = panelService.chooseNewPackageDestination(
            suggestedFileName: suggestedFileName
        ) else { return nil }
        return try exporter.export(preview, to: destination)
    }

    func openPackage() throws -> DiagnosticPackageInspection? {
        guard let packageURL = panelService.choosePackageToRead() else { return nil }
        return try reader.inspect(packageURL)
    }
}
