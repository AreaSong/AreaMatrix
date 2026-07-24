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

    static var logsOpener: any AdvancedSettingsLogFolderOpening {
        AdvancedSettingsLogFolderOpener()
    }

    static var diagnosticSummaryCopier: any AdvancedSettingsDiagnosticSummaryCopying {
        AdvancedSettingsDiagnosticCopier()
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

struct AdvancedSettingsLogFolderOpener: AdvancedSettingsLogFolderOpening {
    private let localURLOpener: any LocalFileURLOpening

    init(localURLOpener: any LocalFileURLOpening = AppPlatformServices.localFileURLOpener) {
        self.localURLOpener = localURLOpener
    }

    @MainActor
    func openLogsFolder(repoPath: String) throws -> String {
        let logsURL = RepositoryMetadataPath.logsURL(repoPath: repoPath)
        do {
            try localURLOpener.openExisting(logsURL, requiresDirectory: true)
        } catch LocalFileURLOpenError.openRejected(_) {
            throw AdvancedSettingsLogFolderError.openRejected(logsURL.path)
        } catch {
            throw AdvancedSettingsLogFolderError.missing(logsURL.path)
        }
        return logsURL.path
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
