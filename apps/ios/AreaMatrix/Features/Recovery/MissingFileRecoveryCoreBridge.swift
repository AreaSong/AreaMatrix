import Foundation

protocol MissingFileRecoveryCoreBridge: Sendable {
    func getMissingFileState(repoPath: String, fileID: Int64) async throws -> MissingFileRecoveryState
    func relinkMissingFile(
        repoPath: String,
        request: MissingFileRelinkRequest
    ) async throws -> MissingFileRecoveryReport
    func removeMissingFileRecord(
        repoPath: String,
        request: MissingFileRemoveRecordRequest
    ) async throws -> MissingFileRecoveryReport
}

enum MissingFileReason: String, Equatable, Sendable {
    case pathMissing = "PathMissing"
    case permissionDenied = "PermissionDenied"
    case cloudPlaceholder = "CloudPlaceholder"
    case externalVolumeDisconnected = "ExternalVolumeDisconnected"
    case unknown = "Unknown"

    var displayText: String {
        switch self {
        case .pathMissing:
            "Path missing"
        case .permissionDenied:
            "Permission denied"
        case .cloudPlaceholder:
            "Cloud placeholder"
        case .externalVolumeDisconnected:
            "External volume disconnected"
        case .unknown:
            "Unknown"
        }
    }
}

enum MissingFileRecoveryStatus: String, Equatable, Sendable {
    case missing = "Missing"
    case present = "Present"
    case relinked = "Relinked"
    case hashMismatch = "HashMismatch"
    case recordRemoved = "RecordRemoved"
    case blocked = "Blocked"
}

struct MissingFileRecoveryState: Equatable, Sendable {
    var fileID: Int64
    var relativePath: String
    var lastKnownPath: String?
    var lastSeenAt: Int64?
    var reason: MissingFileReason
    var expectedHashSha256: String?
    var canLocate: Bool
    var canTryAgain: Bool
    var canRemoveRecord: Bool
    var removeRecordRequiresConfirmation: Bool
    var canRunRescan: Bool
    var rescanDisabledReason: String?

    var fileText: String {
        relativePath.isEmpty ? "No last known path is available." : relativePath
    }

    var lastKnownLocationText: String {
        guard let lastKnownPath, !lastKnownPath.isEmpty else {
            return "No last known path is available."
        }
        return lastKnownPath
    }

    var lastSeenText: String {
        guard let lastSeenAt, lastSeenAt > 0 else {
            return "Unknown"
        }
        return Date(timeIntervalSince1970: TimeInterval(lastSeenAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var hashRequirementText: String {
        if expectedHashSha256?.isEmpty == false {
            return "Selected file must match the missing record hash."
        }
        return "Selected file will be checked by Core before relinking."
    }
}

struct MissingFileRelinkRequest: Equatable, Sendable {
    var fileID: Int64
    var newPath: String
    var confirmed: Bool
}

struct MissingFileRemoveRecordRequest: Equatable, Sendable {
    var fileID: Int64
    var confirmed: Bool
}

struct MissingFileRecoveryReport: Equatable, Sendable {
    var fileID: Int64
    var status: MissingFileRecoveryStatus
    var previousPath: String?
    var currentPath: String?
    var hashMatched: Bool
    var recordRemoved: Bool
    var fileDeleted: Bool
    var changeLogAction: String?
    var message: String?

    var displayMessage: String {
        if let message, !message.isEmpty {
            return message
        }
        switch status {
        case .relinked:
            return "File relinked."
        case .hashMismatch:
            return "Selected file does not match the missing record."
        case .recordRemoved:
            return "AreaMatrix record removed. No user file was deleted."
        case .present:
            return "File is available again."
        case .blocked:
            return "Recovery is blocked."
        case .missing:
            return "File is still missing."
        }
    }
}

enum MissingFileRecoveryError: Error, Equatable, Sendable {
    case fileNotFound(String)
    case database(String)
    case permissionDenied(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .fileNotFound:
            "This missing file record is no longer available."
        case let .database(message):
            message.isEmpty ? "Repository metadata could not be updated." : message
        case .permissionDenied:
            "AreaMatrix does not have permission to complete this recovery action."
        case let .unavailable(message):
            message.isEmpty ? "Missing file recovery is unavailable." : message
        }
    }

    var recovery: String {
        switch self {
        case .fileNotFound:
            "Return to the file list and refresh."
        case .database:
            "Try again after the repository database is available."
        case .permissionDenied:
            "Check file and repository permissions, then try again."
        case .unavailable:
            "Try again."
        }
    }

    static func map(_ error: Error) -> MissingFileRecoveryError {
        if let recoveryError = error as? MissingFileRecoveryError {
            return recoveryError
        }
        if let detailError = error as? MobileFileDetailError {
            switch detailError {
            case let .fileNotFound(message):
                return .fileNotFound(message)
            case let .database(message):
                return .database(message)
            case let .permissionDenied(message):
                return .permissionDenied(message)
            case let .unavailable(message):
                return .unavailable(message)
            }
        }
        return .unavailable(error.localizedDescription)
    }
}

extension LiveMobileRepositoryCoreBridge: MissingFileRecoveryCoreBridge {
    func getMissingFileState(repoPath: String, fileID: Int64) async throws -> MissingFileRecoveryState {
        try await Task.detached(priority: .userInitiated) {
            try MissingFileRecoveryCoreFFIClient().getMissingFileState(repoPath: repoPath, fileID: fileID)
        }.value
    }

    func relinkMissingFile(
        repoPath: String,
        request: MissingFileRelinkRequest
    ) async throws -> MissingFileRecoveryReport {
        try await Task.detached(priority: .userInitiated) {
            try MissingFileRecoveryCoreFFIClient().relinkMissingFile(repoPath: repoPath, request: request)
        }.value
    }

    func removeMissingFileRecord(
        repoPath: String,
        request: MissingFileRemoveRecordRequest
    ) async throws -> MissingFileRecoveryReport {
        try await Task.detached(priority: .userInitiated) {
            try MissingFileRecoveryCoreFFIClient().removeMissingFileRecord(repoPath: repoPath, request: request)
        }.value
    }
}
