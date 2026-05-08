import Foundation

struct RepositorySettingsPathActionError: Equatable, Sendable {
    var message: String
    var recovery: String
}

struct RepositorySettingsDiagnosticsError: Equatable, Sendable {
    var message: String
    var recovery: String
}

enum RepositorySettingsDiagnosticsState: Equatable, Sendable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(RepositorySettingsDiagnosticsError)

    var isConfirmingPrivacy: Bool {
        if case .confirmingPrivacy = self {
            return true
        }
        return false
    }

    var isCollecting: Bool {
        if case .collecting = self {
            return true
        }
        return false
    }
}
