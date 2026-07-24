import Foundation

func mapCoreErrorFromCore(_ error: CoreError) -> ErrorMapping {
    mapCoreError(input: ErrorMappingInput(coreError: error))
}

extension CoreError {
    var kindSnapshot: CoreErrorKindSnapshot {
        switch self {
        case .Io: .io
        case .Db, .DbLocked, .DbCorrupted: .db
        case .Config: .config
        case .Validation: .validation
        case .Classify: .classify
        case .Conflict: .conflict
        case .RevisionConflict: .revisionConflict
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
             let .DbLocked(message),
             let .DbCorrupted(message),
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
        case let .RevisionConflict(resource, _, _):
            resource
        }
    }
}

private extension ErrorMappingInput {
    init(coreError: CoreError) {
        let values = ErrorMappingInputValues(coreError: coreError)
        self.init(
            kind: values.kind,
            path: values.path,
            reason: values.reason,
            message: values.message,
            expectedRevision: values.expectedRevision,
            currentRevision: values.currentRevision
        )
    }
}

private struct ErrorMappingInputValues {
    let kind: ErrorKind
    var path: String?
    var reason: String?
    var message: String?
    var expectedRevision: Int64?
    var currentRevision: Int64?

    init(coreError: CoreError) {
        switch coreError {
        case let .Io(value): self = .message(.io, value)
        case let .Db(value): self = .message(.db, value)
        case let .DbLocked(value): self = .message(.dbLocked, value)
        case let .DbCorrupted(value): self = .message(.dbCorrupted, value)
        case let .Config(value): self = .reason(.config, value)
        case let .Validation(value): self = .reason(.validation, value)
        case let .Classify(value): self = .reason(.classify, value)
        case let .Conflict(value): self = .path(.conflict, value)
        case let .RevisionConflict(resource, expected, current):
            self = .revision(resource, expected, current)
        case .DuplicateFile, .FileNotFound, .ExpiredAction, .RepoNotInitialized, .InvalidPath,
             .ICloudPlaceholder, .StagingRecoveryRequired, .PermissionDenied, .Internal:
            self = Self.remaining(coreError)
        }
    }

    private init(kind: ErrorKind) {
        self.kind = kind
    }

    private static func remaining(_ coreError: CoreError) -> Self {
        switch coreError {
        case let .DuplicateFile(value): .path(.duplicateFile, value)
        case let .FileNotFound(value): .path(.fileNotFound, value)
        case let .ExpiredAction(value): .path(.expiredAction, value)
        case let .RepoNotInitialized(value): .path(.repoNotInitialized, value)
        case let .InvalidPath(value): .path(.invalidPath, value)
        case let .ICloudPlaceholder(value): .path(.iCloudPlaceholder, value)
        case let .StagingRecoveryRequired(value): .path(.stagingRecoveryRequired, value)
        case let .PermissionDenied(value): .path(.permissionDenied, value)
        case let .Internal(value): .message(.internal, value)
        case .Io, .Db, .DbLocked, .DbCorrupted, .Config, .Validation, .Classify, .Conflict, .RevisionConflict:
            Self(kind: .internal)
        }
    }

    private static func message(_ kind: ErrorKind, _ value: String) -> Self {
        var values = Self(kind: kind)
        values.message = value
        return values
    }

    private static func reason(_ kind: ErrorKind, _ value: String) -> Self {
        var values = Self(kind: kind)
        values.reason = value
        return values
    }

    private static func path(_ kind: ErrorKind, _ value: String) -> Self {
        var values = Self(kind: kind)
        values.path = value
        return values
    }

    private static func revision(_ resource: String, _ expected: Int64, _ current: Int64) -> Self {
        var values = Self(kind: .revisionConflict)
        values.path = resource
        values.expectedRevision = expected
        values.currentRevision = current
        return values
    }
}

extension CoreErrorKindSnapshot {
    init(coreKind: ErrorKind) {
        self = Self.primary(coreKind)
    }

    private static func primary(_ coreKind: ErrorKind) -> Self {
        switch coreKind {
        case .io: .io
        case .db, .dbLocked, .dbCorrupted: .db
        case .config: .config
        case .validation: .validation
        case .classify: .classify
        case .conflict: .conflict
        case .revisionConflict: .revisionConflict
        case .duplicateFile: .duplicateFile
        case .fileNotFound, .expiredAction, .repoNotInitialized, .invalidPath, .iCloudPlaceholder,
             .stagingRecoveryRequired, .permissionDenied, .internal:
            secondary(coreKind)
        }
    }

    private static func secondary(_ coreKind: ErrorKind) -> Self {
        switch coreKind {
        case .fileNotFound: .fileNotFound
        case .expiredAction: .expiredAction
        case .repoNotInitialized: .repoNotInitialized
        case .invalidPath: .invalidPath
        case .iCloudPlaceholder: .iCloudPlaceholder
        case .stagingRecoveryRequired: .stagingRecoveryRequired
        case .permissionDenied: .permissionDenied
        case .internal: .internal
        case .io, .db, .dbLocked, .dbCorrupted, .config, .validation, .classify, .conflict, .revisionConflict,
             .duplicateFile:
            .internal
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
