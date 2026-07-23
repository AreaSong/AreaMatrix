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
    var recovery: LocalizedMessage
    var detail: String

    init(mapping: CoreErrorMappingSnapshot, fallbackDetail: String) {
        self.mapping = mapping
        recovery = mapping.recoveryMessage(fallback: mapping.userMessageDescriptor)
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

    var displayName: String {
        switch self {
        case .io: L10n.string("I/O")
        case .db: L10n.string("Database")
        case .config: L10n.string("Configuration")
        case .validation: L10n.string("Validation")
        case .classify: L10n.string("Classification")
        case .conflict: L10n.string("Conflict")
        case .duplicateFile: L10n.string("Duplicate file")
        case .fileNotFound: L10n.string("File not found")
        case .expiredAction: L10n.string("Expired action")
        case .repoNotInitialized: L10n.string("Repository not initialized")
        case .invalidPath: L10n.string("Invalid path")
        case .iCloudPlaceholder: L10n.string("iCloud placeholder")
        case .stagingRecoveryRequired: L10n.string("Staging recovery required")
        case .permissionDenied: L10n.string("Permission denied")
        case .internal: L10n.string("Internal error")
        }
    }
}

enum CoreErrorSeveritySnapshot: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"

    var displayName: String {
        switch self {
        case .low: L10n.string("Low")
        case .medium: L10n.string("Medium")
        case .high: L10n.string("High")
        case .critical: L10n.string("Critical")
        }
    }
}

enum CoreErrorRecoverabilitySnapshot: String, Equatable {
    case retryable = "Retryable"
    case userActionRequired = "UserActionRequired"
    case refreshRequired = "RefreshRequired"
    case fatal = "Fatal"

    var displayName: String {
        switch self {
        case .retryable: L10n.string("Retryable")
        case .userActionRequired: L10n.string("User action required")
        case .refreshRequired: L10n.string("Refresh required")
        case .fatal: L10n.string("Fatal")
        }
    }
}

struct CoreErrorMappingSnapshot: Equatable {
    var kind: CoreErrorKindSnapshot
    private var fallbackUserMessage: String
    private var usesKindLocalization: Bool
    private var customUserMessage: LocalizedMessage?
    var severity: CoreErrorSeveritySnapshot
    private var fallbackSuggestedAction: String
    private var customSuggestedAction: LocalizedMessage?
    var recoverability: CoreErrorRecoverabilitySnapshot
    var rawContext: String

    var userMessage: String {
        L10n.resolve(userMessageDescriptor)
    }

    var userMessageDescriptor: LocalizedMessage {
        if let customUserMessage {
            return customUserMessage
        }
        guard usesKindLocalization else {
            return L10n.message(
                "error.unmapped.message",
                fallback: fallbackUserMessage,
                technicalDetail: fallbackUserMessage
            )
        }
        return kind.messageDescriptor(fallback: fallbackUserMessage)
    }

    var suggestedAction: String {
        L10n.resolve(suggestedActionDescriptor)
    }

    var suggestedActionDescriptor: LocalizedMessage {
        if let customSuggestedAction {
            return customSuggestedAction
        }
        guard usesKindLocalization else {
            return L10n.message(
                "error.unmapped.action",
                fallback: fallbackSuggestedAction,
                technicalDetail: fallbackSuggestedAction
            )
        }
        return kind.actionDescriptor(fallback: fallbackSuggestedAction)
    }

    init(
        kind: CoreErrorKindSnapshot,
        userMessage: String,
        severity: CoreErrorSeveritySnapshot,
        suggestedAction: String,
        recoverability: CoreErrorRecoverabilitySnapshot,
        rawContext: String
    ) {
        self.kind = kind
        fallbackUserMessage = userMessage
        usesKindLocalization = false
        customUserMessage = nil
        self.severity = severity
        fallbackSuggestedAction = suggestedAction
        customSuggestedAction = nil
        self.recoverability = recoverability
        self.rawContext = rawContext
    }

    init(
        kind: CoreErrorKindSnapshot,
        userMessage: LocalizedMessage,
        severity: CoreErrorSeveritySnapshot,
        suggestedAction: LocalizedMessage,
        recoverability: CoreErrorRecoverabilitySnapshot,
        rawContext: String
    ) {
        self.kind = kind
        fallbackUserMessage = ""
        usesKindLocalization = false
        customUserMessage = userMessage
        self.severity = severity
        fallbackSuggestedAction = ""
        customSuggestedAction = suggestedAction
        self.recoverability = recoverability
        self.rawContext = rawContext
    }
}

extension CoreErrorMappingSnapshot {
    static func localized(
        kind: CoreErrorKindSnapshot,
        userMessage: String,
        severity: CoreErrorSeveritySnapshot,
        suggestedAction: String,
        recoverability: CoreErrorRecoverabilitySnapshot,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        var snapshot = CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: severity,
            suggestedAction: suggestedAction,
            recoverability: recoverability,
            rawContext: rawContext
        )
        snapshot.usesKindLocalization = true
        return snapshot
    }

    init(coreMapping: ErrorMapping) {
        self.init(
            kind: CoreErrorKindSnapshot(coreKind: coreMapping.kind),
            userMessage: coreMapping.userMessage,
            severity: CoreErrorSeveritySnapshot(coreSeverity: coreMapping.severity),
            suggestedAction: coreMapping.suggestedAction,
            recoverability: CoreErrorRecoverabilitySnapshot(coreRecoverability: coreMapping.recoverability),
            rawContext: coreMapping.rawContext
        )
        usesKindLocalization = true
    }

    static func internalFailure(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: L10n.message("error.internal.message"),
            severity: .critical,
            suggestedAction: L10n.message("error.internal.action"),
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

    func recoveryMessage(fallback: LocalizedMessage) -> LocalizedMessage {
        !usesKindLocalization && fallbackSuggestedAction.isEmpty ? fallback : suggestedActionDescriptor
    }
}

private extension CoreErrorKindSnapshot {
    func messageDescriptor(fallback: String) -> LocalizedMessage {
        switch self {
        case .io: L10n.message("core.error.Io.message", fallback: fallback)
        case .db: L10n.message("core.error.Db.message", fallback: fallback)
        case .config: L10n.message("core.error.Config.message", fallback: fallback)
        case .validation: L10n.message("core.error.Validation.message", fallback: fallback)
        case .classify: L10n.message("core.error.Classify.message", fallback: fallback)
        case .conflict: L10n.message("core.error.Conflict.message", fallback: fallback)
        case .duplicateFile: L10n.message("core.error.DuplicateFile.message", fallback: fallback)
        case .fileNotFound: L10n.message("core.error.FileNotFound.message", fallback: fallback)
        case .expiredAction: L10n.message("core.error.ExpiredAction.message", fallback: fallback)
        case .repoNotInitialized: L10n.message("core.error.RepoNotInitialized.message", fallback: fallback)
        case .invalidPath: L10n.message("core.error.InvalidPath.message", fallback: fallback)
        case .iCloudPlaceholder: L10n.message("core.error.ICloudPlaceholder.message", fallback: fallback)
        case .stagingRecoveryRequired:
            L10n.message("core.error.StagingRecoveryRequired.message", fallback: fallback)
        case .permissionDenied: L10n.message("core.error.PermissionDenied.message", fallback: fallback)
        case .internal: L10n.message("core.error.Internal.message", fallback: fallback)
        }
    }

    func actionDescriptor(fallback: String) -> LocalizedMessage {
        switch self {
        case .io: L10n.message("core.error.Io.action", fallback: fallback)
        case .db: L10n.message("core.error.Db.action", fallback: fallback)
        case .config: L10n.message("core.error.Config.action", fallback: fallback)
        case .validation: L10n.message("core.error.Validation.action", fallback: fallback)
        case .classify: L10n.message("core.error.Classify.action", fallback: fallback)
        case .conflict: L10n.message("core.error.Conflict.action", fallback: fallback)
        case .duplicateFile: L10n.message("core.error.DuplicateFile.action", fallback: fallback)
        case .fileNotFound: L10n.message("core.error.FileNotFound.action", fallback: fallback)
        case .expiredAction: L10n.message("core.error.ExpiredAction.action", fallback: fallback)
        case .repoNotInitialized: L10n.message("core.error.RepoNotInitialized.action", fallback: fallback)
        case .invalidPath: L10n.message("core.error.InvalidPath.action", fallback: fallback)
        case .iCloudPlaceholder: L10n.message("core.error.ICloudPlaceholder.action", fallback: fallback)
        case .stagingRecoveryRequired:
            L10n.message("core.error.StagingRecoveryRequired.action", fallback: fallback)
        case .permissionDenied: L10n.message("core.error.PermissionDenied.action", fallback: fallback)
        case .internal: L10n.message("core.error.Internal.action", fallback: fallback)
        }
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
