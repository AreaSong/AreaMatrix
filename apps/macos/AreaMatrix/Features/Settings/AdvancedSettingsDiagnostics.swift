import Foundation

struct SettingsDiagnosticsGeneration {
    private var value = 0

    mutating func begin() -> Int {
        value += 1
        return value
    }

    mutating func invalidate() {
        value += 1
    }

    func isCurrent(_ generation: Int) -> Bool {
        value == generation
    }
}

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
        repoSchemaVersion.map { "v\($0)" } ?? L10n.string("Unknown")
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
    case success(LocalizedMessage)
    case failed(AdvancedSettingsError)
}

enum AdvancedSettingsLogFolderError: Error, Equatable, LocalizedError {
    case missing(String)
    case openRejected(String)

    var errorDescription: String? {
        switch self {
        case let .missing(path):
            L10n.format("settings.advanced.logsMissing", path)
        case let .openRejected(path):
            L10n.format("settings.advanced.logsOpenRejected", path)
        }
    }
}

enum AdvancedSettingsDiagnosticSummaryError: Error, Equatable, LocalizedError {
    case copyRejected

    var errorDescription: String? {
        switch self {
        case .copyRejected:
            L10n.string("settings.advanced.diagnosticsCopyRejected")
        }
    }
}
