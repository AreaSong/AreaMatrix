import AppKit
import Foundation

protocol CoreVersionReading: Sendable {
    func coreVersion() async throws -> String
}

protocol AppVersionReading: Sendable {
    func appVersion() -> String
}

protocol AdvancedSettingsLogFolderOpening {
    @MainActor
    func openLogsFolder(repoPath: String) throws -> String
}

protocol AdvancedSettingsDiagnosticSummaryCopying {
    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws
}

struct AdvancedSettingsVersionInfo: Equatable, Sendable {
    var appVersion: String
    var coreVersion: String
    var repoSchemaVersion: Int64?

    static let unknown = AdvancedSettingsVersionInfo(
        appVersion: "Unknown",
        coreVersion: "Unknown",
        repoSchemaVersion: nil
    )

    var repoSchemaVersionLabel: String {
        repoSchemaVersion.map { "v\($0)" } ?? "Unknown"
    }
}

enum AdvancedSettingsDiagnosticsState: Equatable, Sendable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(AdvancedSettingsError)

    var isConfirmingPrivacy: Bool {
        if case .confirmingPrivacy = self { return true }
        return false
    }

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}

enum AdvancedSettingsActionFeedback: Equatable, Sendable {
    case success(String)
    case failed(AdvancedSettingsError)
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

struct NSWorkspaceAdvancedSettingsLogFolderOpener: AdvancedSettingsLogFolderOpening {
    @MainActor
    func openLogsFolder(repoPath: String) throws -> String {
        let logsURL = Self.logsURL(repoPath: repoPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: logsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
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

struct NSPasteboardAdvancedSettingsDiagnosticSummaryCopier: AdvancedSettingsDiagnosticSummaryCopying {
    @MainActor
    func copyDiagnosticSummary(_ summary: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(summary, forType: .string) else {
            throw AdvancedSettingsDiagnosticSummaryError.copyRejected
        }
    }
}

enum AdvancedSettingsLogFolderError: Error, Equatable, LocalizedError, Sendable {
    case missing(String)
    case openRejected(String)

    var errorDescription: String? {
        switch self {
        case .missing(let path):
            return "Logs folder is missing: \(path)"
        case .openRejected(let path):
            return "Finder rejected opening logs folder: \(path)"
        }
    }
}

enum AdvancedSettingsDiagnosticSummaryError: Error, Equatable, LocalizedError, Sendable {
    case copyRejected

    var errorDescription: String? {
        switch self {
        case .copyRejected:
            return "Pasteboard rejected the diagnostic summary."
        }
    }
}
