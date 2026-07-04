import AppKit
import Foundation

enum AdvancedSettingsPlatformServices {
    static var rootOverviewInspector: any RootOverviewFileInspecting {
        LocalRootOverviewFileInspector()
    }

    static var appVersionReader: any AppVersionReading {
        BundleAppVersionReader()
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        SQLiteExistingRepositoryMetadataReader()
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
        let trimmedVersion = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBuild = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if trimmedVersion.isEmpty { return "Unknown" }
        if trimmedBuild.isEmpty { return trimmedVersion }
        return "\(trimmedVersion) (\(trimmedBuild))"
    }
}

struct AdvancedSettingsLogFolderOpener: AdvancedSettingsLogFolderOpening {
    @MainActor
    func openLogsFolder(repoPath: String) throws -> String {
        let logsURL = Self.logsURL(repoPath: repoPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: logsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw AdvancedSettingsLogFolderError.missing(logsURL.path)
        }
        guard NSWorkspace.shared.open(logsURL) else {
            throw AdvancedSettingsLogFolderError.openRejected(logsURL.path)
        }
        return logsURL.path
    }

    static func logsURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)
    }
}

struct AdvancedSettingsDiagnosticCopier: AdvancedSettingsDiagnosticSummaryCopying {
    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(summary, forType: .string) else {
            throw AdvancedSettingsDiagnosticSummaryError.copyRejected
        }
    }
}
