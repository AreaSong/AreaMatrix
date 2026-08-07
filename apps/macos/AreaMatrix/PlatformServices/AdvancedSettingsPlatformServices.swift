import AppKit
import Foundation

enum AdvancedSettingsPlatformServices {
    static func makeDiagnosticSummaryCopier(
        writer: any PasteboardStringWriting
    ) -> any AdvancedSettingsDiagnosticSummaryCopying {
        AdvancedSettingsDiagnosticCopier(writer: writer)
    }

    static func diagnosticsPackagePreviewer(
        interfaceLocaleIdentifier: @escaping @Sendable () -> String
    ) -> any DiagnosticsPackagePreviewing {
        DiagnosticsPackagePreviewService(
            exporter: DiagnosticPackageExporter(interfaceLocaleIdentifier: interfaceLocaleIdentifier)
        )
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

    init(writer: any PasteboardStringWriting) {
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

struct DefaultDiagnosticsPackageHandler: DiagnosticsPackageHandling {
    // The App composition root is synchronous; only the protocol operations require the main actor.
    // swiftlint:disable:next unneeded_synthesized_initializer
    nonisolated init() {}

    @MainActor
    func export(
        _ preview: DiagnosticPackagePreview,
        suggestedFileName: String
    ) throws -> URL? {
        try DiagnosticsPackageHandler().export(preview, suggestedFileName: suggestedFileName)
    }

    @MainActor
    func openPackage() throws -> DiagnosticPackageInspection? {
        try DiagnosticsPackageHandler().openPackage()
    }
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
