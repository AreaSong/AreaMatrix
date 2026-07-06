import AppKit
import Foundation

enum AboutSettingsPlatformServices {
    static var appVersionReader: any AppVersionReading {
        AppPlatformServices.appVersionReader
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        AppPlatformServices.existingRepositoryMetadataReader
    }

    static var diagnosticsExporter: any AboutDiagnosticsExporting {
        LocalAboutDiagnosticsExporter()
    }

    static var externalLinkOpener: any AboutExternalLinkOpening {
        NSWorkspaceAboutExternalLinkOpener()
    }

    static var logsOpener: any AboutLogsOpening {
        NSWorkspaceAboutLogsOpener()
    }

    static var stringCopier: any AboutStringCopying {
        NSPasteboardAboutStringCopier()
    }

    static var diagnosticsRevealer: any AboutDiagnosticsRevealing {
        NSWorkspaceAboutDiagnosticsRevealer()
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        AppPlatformServices.accessibilityAnnouncer
    }
}

enum PlatformDifferencesPlatformServices {
    static var appVersionReader: any AppVersionReading {
        AppPlatformServices.appVersionReader
    }
}

struct NSWorkspaceAboutExternalLinkOpener: AboutExternalLinkOpening {
    private let externalURLOpener: any ExternalURLStringOpening

    init(externalURLOpener: any ExternalURLStringOpening = AppPlatformServices.externalURLStringOpener) {
        self.externalURLOpener = externalURLOpener
    }

    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        do {
            try externalURLOpener.openHTTPSURLString(link.urlString)
        } catch let error as ExternalURLOpenError {
            switch error {
            case .invalidURL:
                throw AboutSettingsPlatformError.invalidURL(link.urlString)
            case .openRejected:
                throw AboutSettingsPlatformError.openRejected(link.urlString)
            }
        } catch {
            throw AboutSettingsPlatformError.invalidURL(link.urlString)
        }
        return link.urlString
    }
}

struct NSWorkspaceAboutLogsOpener: AboutLogsOpening {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func logsPath(repoPath: String) -> String {
        RepositoryMetadataPath.logsURL(repoPath: repoPath).path
    }

    @MainActor
    func openLogs(repoPath: String) throws -> String {
        let url = RepositoryMetadataPath.logsURL(repoPath: repoPath)
        do {
            try localURLOpener.openExisting(url, requiresDirectory: true)
        } catch LocalFileURLOpenError.openRejected(_) {
            throw AboutSettingsPlatformError.openRejected(url.path)
        } catch {
            throw AboutSettingsPlatformError.missingPath(url.path)
        }
        return url.path
    }
}

struct NSPasteboardAboutStringCopier: AboutStringCopying {
    private let writer: any PasteboardStringWriting

    init(writer: any PasteboardStringWriting = AppPlatformServices.pasteboardStringWriter) {
        self.writer = writer
    }

    @MainActor
    func copy(_ value: String) throws {
        guard writer.write(value) else {
            throw AboutSettingsPlatformError.copyRejected
        }
    }
}

struct NSWorkspaceAboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func revealDiagnostics(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        do {
            try localURLOpener.revealExisting(url)
        } catch {
            throw AboutSettingsPlatformError.missingPath(path)
        }
    }
}

struct LocalAboutDiagnosticsExporter: AboutDiagnosticsExporting {
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory
    }

    func exportDiagnostics(context: AboutDiagnosticsExportContext) async throws -> AboutDiagnosticsExportSnapshot {
        let createdAt = Int64(Date().timeIntervalSince1970)
        let exportURL = try Self.makeExportURL(baseDirectory: baseDirectory, createdAt: createdAt)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)
        let reportURL = exportURL.appendingPathComponent("about-diagnostics.txt", isDirectory: false)
        try Self.report(context: context, createdAt: createdAt)
            .write(to: reportURL, atomically: true, encoding: .utf8)

        return AboutDiagnosticsExportSnapshot(
            exportPath: exportURL.path,
            createdAt: createdAt,
            warnings: []
        )
    }

    private static func makeExportURL(baseDirectory: URL?, createdAt: Int64) throws -> URL {
        let directory = baseDirectory ?? defaultDiagnosticsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(
            "about-diagnostics-\(createdAt)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private static func defaultDiagnosticsDirectory() -> URL {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (supportURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("AreaMatrix", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static func report(context: AboutDiagnosticsExportContext, createdAt: Int64) -> String {
        let formatter = ISO8601DateFormatter()
        let createdAtLabel = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
        return """
        AreaMatrix About diagnostics
        Created at: \(createdAtLabel)
        App version: \(context.versionInfo.appVersion)
        Core version: \(context.versionInfo.coreVersion)
        Schema version: \(context.versionInfo.schemaVersion)
        Version issue: \(context.versionIssue ?? "none")
        User file contents: excluded
        Original file paths: redacted
        Automatic upload: disabled
        """
    }
}
