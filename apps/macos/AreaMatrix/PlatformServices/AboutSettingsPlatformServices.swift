import AppKit
import Foundation

enum AboutSettingsPlatformServices {
    static var appVersionReader: any AppVersionReading {
        BundleAppVersionReader()
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        SQLiteExistingRepositoryMetadataReader()
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
        VoiceOverAccessibilityAnnouncer()
    }
}

enum PlatformDifferencesPlatformServices {
    static var appVersionReader: any AppVersionReading {
        BundleAppVersionReader()
    }
}

struct NSWorkspaceAboutExternalLinkOpener: AboutExternalLinkOpening {
    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        guard let url = URL(string: link.urlString) else {
            throw AboutSettingsPlatformError.invalidURL(link.urlString)
        }
        guard NSWorkspace.shared.open(url) else {
            throw AboutSettingsPlatformError.openRejected(link.urlString)
        }
        return link.urlString
    }
}

struct NSWorkspaceAboutLogsOpener: AboutLogsOpening {
    @MainActor
    func logsPath(repoPath: String) -> String {
        Self.logsURL(repoPath: repoPath).path
    }

    @MainActor
    func openLogs(repoPath: String) throws -> String {
        let url = Self.logsURL(repoPath: repoPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw AboutSettingsPlatformError.missingPath(url.path)
        }
        guard NSWorkspace.shared.open(url) else {
            throw AboutSettingsPlatformError.openRejected(url.path)
        }
        return url.path
    }

    static func logsURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }
}

struct NSPasteboardAboutStringCopier: AboutStringCopying {
    @MainActor
    func copy(_ value: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(value, forType: .string) else {
            throw AboutSettingsPlatformError.copyRejected
        }
    }
}

struct NSWorkspaceAboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    @MainActor
    func revealDiagnostics(at path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AboutSettingsPlatformError.missingPath(path)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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
