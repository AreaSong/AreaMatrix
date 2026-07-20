import Foundation

protocol CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot
}

protocol AppErrorMappingProviding {
    var appErrorMapping: CoreErrorMappingSnapshot { get }
}

struct AppSemanticError: Error, LocalizedError, AppErrorMappingProviding {
    let appErrorMapping: CoreErrorMappingSnapshot

    var errorDescription: String? {
        appErrorMapping.rawContext.isEmpty ? appErrorMapping.userMessage : appErrorMapping.rawContext
    }
}

extension CoreErrorMapping {
    func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let appError = error as? AppErrorMappingProviding {
            return appError.appErrorMapping
        }
        if let coreError = error as? CoreError {
            return await mapCoreError(coreError)
        }
        return await mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    func mapCoreErrorIfPresent(_ error: Error) async -> CoreErrorMappingSnapshot? {
        guard let coreError = error as? CoreError else { return nil }
        return await mapCoreError(coreError)
    }

    func mapKnownErrorIfPresent(_ error: Error) async -> CoreErrorMappingSnapshot? {
        if let appError = error as? AppErrorMappingProviding {
            return appError.appErrorMapping
        }
        return await mapCoreErrorIfPresent(error)
    }

    func mapCoreErrorContextIfPresent(_ error: Error) async -> CoreErrorContextSnapshot? {
        guard let coreError = error as? CoreError else { return nil }
        let mapping = await mapCoreError(coreError)
        return CoreErrorContextSnapshot(mapping: mapping, rawContext: coreError.rawContextSnapshot)
    }

    func mapCoreErrorDisplayIfPresent(_ error: Error) async -> CoreErrorDisplaySnapshot? {
        guard let coreError = error as? CoreError else { return nil }
        let mapping = await mapCoreError(coreError)
        return CoreErrorDisplaySnapshot(
            mapping: mapping,
            fallbackDetail: coreError.localizedDescription
        )
    }
}

struct CoreErrorRawContextSnapshot: Equatable {
    var kind: CoreErrorKindSnapshot
    var rawContext: String

    init?(_ error: Error) {
        guard let coreError = error as? CoreError else { return nil }
        kind = coreError.kindSnapshot
        rawContext = coreError.rawContextSnapshot
    }

    static func fileNotFoundPath(from error: Error) -> String? {
        guard let context = CoreErrorRawContextSnapshot(error), context.kind == .fileNotFound else {
            return nil
        }
        return context.rawContext
    }

    static func repoNotInitializedPath(from error: Error) -> String? {
        guard let context = CoreErrorRawContextSnapshot(error), context.kind == .repoNotInitialized else {
            return nil
        }
        return context.rawContext
    }
}

struct CoreErrorContextSnapshot: Equatable {
    var mapping: CoreErrorMappingSnapshot
    var rawContext: String

    var kind: CoreErrorKindSnapshot {
        mapping.kind
    }
}

struct CoreErrorDisplaySnapshot: Equatable {
    var mapping: CoreErrorMappingSnapshot
    var recovery: String
    var detail: String

    init(mapping: CoreErrorMappingSnapshot, fallbackDetail: String) {
        self.mapping = mapping
        recovery = mapping.recoveryText
        detail = mapping.rawContext.isEmpty ? fallbackDetail : mapping.rawContext
    }
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

    static func internalFailure(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "应用内部错误",
            severity: .critical,
            suggestedAction: "请记录错误信息并重启应用",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }

    static func invalidPath(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(coreMapping: mapCoreError(input: ErrorMappingInput(
            kind: .invalidPath,
            path: rawContext,
            reason: nil,
            message: nil
        )))
    }

    static func database(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(coreMapping: mapCoreError(input: ErrorMappingInput(
            kind: .db,
            path: nil,
            reason: nil,
            message: rawContext
        )))
    }

    static func conflict(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(coreMapping: mapCoreError(input: ErrorMappingInput(
            kind: .conflict,
            path: rawContext,
            reason: nil,
            message: nil
        )))
    }

    var recoveryText: String {
        recoveryText(fallback: userMessage)
    }

    func recoveryText(fallback: String) -> String {
        suggestedAction.isEmpty ? fallback : suggestedAction
    }
}

extension AppSemanticError {
    static func database(rawContext: String) -> AppSemanticError {
        AppSemanticError(appErrorMapping: .database(rawContext: rawContext))
    }

    static func invalidPath(rawContext: String) -> AppSemanticError {
        AppSemanticError(appErrorMapping: .invalidPath(rawContext: rawContext))
    }

    static func conflict(rawContext: String) -> AppSemanticError {
        AppSemanticError(appErrorMapping: .conflict(rawContext: rawContext))
    }

    static func internalFailure(rawContext: String) -> AppSemanticError {
        AppSemanticError(appErrorMapping: .internalFailure(rawContext: rawContext))
    }
}

func mapCoreErrorFromCore(_ error: CoreError) -> ErrorMapping {
    mapCoreError(input: ErrorMappingInput(coreError: error))
}

private extension CoreError {
    var kindSnapshot: CoreErrorKindSnapshot {
        switch self {
        case .Io:
            .io
        case .Db:
            .db
        case .Config:
            .config
        case .Validation:
            .validation
        case .Classify:
            .classify
        case .Conflict:
            .conflict
        case .DuplicateFile:
            .duplicateFile
        case .FileNotFound:
            .fileNotFound
        case .ExpiredAction:
            .expiredAction
        case .RepoNotInitialized:
            .repoNotInitialized
        case .InvalidPath:
            .invalidPath
        case .ICloudPlaceholder:
            .iCloudPlaceholder
        case .StagingRecoveryRequired:
            .stagingRecoveryRequired
        case .PermissionDenied:
            .permissionDenied
        case .Internal:
            .internal
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
