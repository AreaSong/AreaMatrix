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

struct AdvancedSettingsVersionInfo: Equatable {
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

enum AdvancedSettingsDiagnosticsState: Equatable {
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

enum AdvancedSettingsActionFeedback: Equatable {
    case success(String)
    case failed(AdvancedSettingsError)
}

enum AdvancedSettingsLogFolderError: Error, Equatable, LocalizedError {
    case missing(String)
    case openRejected(String)

    var errorDescription: String? {
        switch self {
        case let .missing(path):
            "Logs folder is missing: \(path)"
        case let .openRejected(path):
            "Finder rejected opening logs folder: \(path)"
        }
    }
}

enum AdvancedSettingsDiagnosticSummaryError: Error, Equatable, LocalizedError {
    case copyRejected

    var errorDescription: String? {
        switch self {
        case .copyRejected:
            "Pasteboard rejected the diagnostic summary."
        }
    }
}
