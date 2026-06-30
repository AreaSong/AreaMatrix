import Foundation

protocol CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot
}

enum CoreErrorKindSnapshot: String, Equatable {
    case io = "Io"
    case db = "Db"
    case config = "Config"
    case validation = "Validation"
    case classify = "Classify"
    case conflict = "Conflict"
    case duplicateFile = "DuplicateFile"
    case fileNotFound = "FileNotFound"
    case expiredAction = "ExpiredAction"
    case repoNotInitialized = "RepoNotInitialized"
    case invalidPath = "InvalidPath"
    case iCloudPlaceholder = "ICloudPlaceholder"
    case stagingRecoveryRequired = "StagingRecoveryRequired"
    case permissionDenied = "PermissionDenied"
    case `internal` = "Internal"
}

enum CoreErrorSeveritySnapshot: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
}

enum CoreErrorRecoverabilitySnapshot: String, Equatable {
    case retryable = "Retryable"
    case userActionRequired = "UserActionRequired"
    case refreshRequired = "RefreshRequired"
    case fatal = "Fatal"
}

struct CoreErrorMappingSnapshot: Equatable {
    var kind: CoreErrorKindSnapshot
    var userMessage: String
    var severity: CoreErrorSeveritySnapshot
    var suggestedAction: String
    var recoverability: CoreErrorRecoverabilitySnapshot
    var rawContext: String
}

extension CoreErrorMappingSnapshot {
    init(coreMapping: ErrorMapping) {
        kind = CoreErrorKindSnapshot(coreKind: coreMapping.kind)
        userMessage = coreMapping.userMessage
        severity = CoreErrorSeveritySnapshot(coreSeverity: coreMapping.severity)
        suggestedAction = coreMapping.suggestedAction
        recoverability = CoreErrorRecoverabilitySnapshot(coreRecoverability: coreMapping.recoverability)
        rawContext = coreMapping.rawContext
    }
}

func mapCoreErrorFromCore(_ error: CoreError) -> ErrorMapping {
    mapCoreError(input: ErrorMappingInput(coreError: error))
}

private extension ErrorMappingInput {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreError: CoreError) {
        switch coreError {
        case let .Io(message):
            self.init(kind: .io, path: nil, reason: nil, message: message)
        case let .Db(message):
            self.init(kind: .db, path: nil, reason: nil, message: message)
        case let .Config(reason):
            self.init(kind: .config, path: nil, reason: reason, message: nil)
        case let .Validation(reason):
            self.init(kind: .validation, path: nil, reason: reason, message: nil)
        case let .Classify(reason):
            self.init(kind: .classify, path: nil, reason: reason, message: nil)
        case let .Conflict(path):
            self.init(kind: .conflict, path: path, reason: nil, message: nil)
        case let .DuplicateFile(existingPath):
            self.init(kind: .duplicateFile, path: existingPath, reason: nil, message: nil)
        case let .FileNotFound(path):
            self.init(kind: .fileNotFound, path: path, reason: nil, message: nil)
        case let .ExpiredAction(actionId):
            self.init(kind: .expiredAction, path: nil, reason: actionId, message: nil)
        case let .RepoNotInitialized(path):
            self.init(kind: .repoNotInitialized, path: path, reason: nil, message: nil)
        case let .InvalidPath(path):
            self.init(kind: .invalidPath, path: path, reason: nil, message: nil)
        case let .ICloudPlaceholder(path):
            self.init(kind: .iCloudPlaceholder, path: path, reason: nil, message: nil)
        case let .StagingRecoveryRequired(path):
            self.init(kind: .stagingRecoveryRequired, path: path, reason: nil, message: nil)
        case let .PermissionDenied(path):
            self.init(kind: .permissionDenied, path: path, reason: nil, message: nil)
        case let .Internal(message):
            self.init(kind: .internal, path: nil, reason: nil, message: message)
        }
    }
}

private extension CoreErrorKindSnapshot {
    // swiftlint:disable:next cyclomatic_complexity
    init(coreKind: ErrorKind) {
        switch coreKind {
        case .io: self = .io
        case .db: self = .db
        case .config: self = .config
        case .validation: self = .validation
        case .classify: self = .classify
        case .conflict: self = .conflict
        case .duplicateFile: self = .duplicateFile
        case .fileNotFound: self = .fileNotFound
        case .expiredAction: self = .expiredAction
        case .repoNotInitialized: self = .repoNotInitialized
        case .invalidPath: self = .invalidPath
        case .iCloudPlaceholder: self = .iCloudPlaceholder
        case .stagingRecoveryRequired: self = .stagingRecoveryRequired
        case .permissionDenied: self = .permissionDenied
        case .internal: self = .internal
        }
    }
}

private extension CoreErrorSeveritySnapshot {
    init(coreSeverity: ErrorSeverity) {
        switch coreSeverity {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .critical: self = .critical
        }
    }
}

private extension CoreErrorRecoverabilitySnapshot {
    init(coreRecoverability: ErrorRecoverability) {
        switch coreRecoverability {
        case .retryable: self = .retryable
        case .userActionRequired: self = .userActionRequired
        case .refreshRequired: self = .refreshRequired
        case .fatal: self = .fatal
        }
    }
}
