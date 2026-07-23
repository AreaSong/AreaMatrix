import Foundation

func mapCoreErrorFromCore(_ error: CoreError) -> ErrorMapping {
    mapCoreError(input: ErrorMappingInput(coreError: error))
}

extension CoreError {
    var kindSnapshot: CoreErrorKindSnapshot {
        switch self {
        case .Io: .io
        case .Db: .db
        case .Config: .config
        case .Validation: .validation
        case .Classify: .classify
        case .Conflict: .conflict
        case .DuplicateFile: .duplicateFile
        case .FileNotFound: .fileNotFound
        case .ExpiredAction: .expiredAction
        case .RepoNotInitialized: .repoNotInitialized
        case .InvalidPath: .invalidPath
        case .ICloudPlaceholder: .iCloudPlaceholder
        case .StagingRecoveryRequired: .stagingRecoveryRequired
        case .PermissionDenied: .permissionDenied
        case .Internal: .internal
        }
    }

    var rawContextSnapshot: String {
        switch self {
        case let .Io(message),
             let .Db(message),
             let .Internal(message):
            message
        case let .Config(reason),
             let .Validation(reason),
             let .Classify(reason):
            reason
        case let .Conflict(path),
             let .DuplicateFile(path),
             let .FileNotFound(path),
             let .ExpiredAction(path),
             let .RepoNotInitialized(path),
             let .InvalidPath(path),
             let .ICloudPlaceholder(path),
             let .StagingRecoveryRequired(path),
             let .PermissionDenied(path):
            path
        }
    }
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
            self.init(kind: .expiredAction, path: actionId, reason: nil, message: nil)
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

extension CoreErrorKindSnapshot {
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

extension CoreErrorSeveritySnapshot {
    init(coreSeverity: ErrorSeverity) {
        switch coreSeverity {
        case .low: self = .low
        case .medium: self = .medium
        case .high: self = .high
        case .critical: self = .critical
        }
    }
}

extension CoreErrorRecoverabilitySnapshot {
    init(coreRecoverability: ErrorRecoverability) {
        switch coreRecoverability {
        case .retryable: self = .retryable
        case .userActionRequired: self = .userActionRequired
        case .refreshRequired: self = .refreshRequired
        case .fatal: self = .fatal
        }
    }
}
