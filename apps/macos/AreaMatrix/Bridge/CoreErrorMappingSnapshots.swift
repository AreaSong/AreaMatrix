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

enum CoreErrorKindSnapshot: String, Equatable, Hashable {
    case io = "Io"
    case db = "Db"
    case config = "Config"
    case validation = "Validation"
    case classify = "Classify"
    case conflict = "Conflict"
    case revisionConflict = "RevisionConflict"
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
        case .revisionConflict: L10n.string("Revision conflict")
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

struct CoreErrorArgumentSnapshot: Equatable {
    var name: String
    var value: String
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
    var code: String
    var field: String?
    var arguments: [CoreErrorArgumentSnapshot]
    var recoveryActionIDs: [String]
    private var fallbackUserMessage: String
    private var usesKindLocalization: Bool
    private var customUserMessage: LocalizedMessage?
    var severity: CoreErrorSeveritySnapshot
    private var fallbackSuggestedAction: String
    private var customSuggestedAction: LocalizedMessage?
    var recoverability: CoreErrorRecoverabilitySnapshot
    var technicalDetails: String?

    var rawContext: String {
        technicalDetails ?? ""
    }

    var userMessage: String {
        L10n.resolve(userMessageDescriptor)
    }

    var userMessageDescriptor: LocalizedMessage {
        if let customUserMessage {
            return customUserMessage
        }
        if !code.isEmpty {
            return kind.messageDescriptor(
                fallback: L10n.string("error.unmapped.message") + " [\(code)]"
            )
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
        if recoveryActionIDs.contains(where: Self.knownRecoveryActionIDs.contains) {
            return kind.actionDescriptor(fallback: fallbackSuggestedAction)
        }
        if !code.isEmpty {
            return L10n.message("core.error.no-action")
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
        code = ""
        field = nil
        arguments = []
        recoveryActionIDs = []
        fallbackUserMessage = userMessage
        usesKindLocalization = false
        customUserMessage = nil
        self.severity = severity
        fallbackSuggestedAction = suggestedAction
        customSuggestedAction = nil
        self.recoverability = recoverability
        technicalDetails = rawContext.isEmpty ? nil : rawContext
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
        code = ""
        field = nil
        arguments = []
        recoveryActionIDs = []
        fallbackUserMessage = ""
        usesKindLocalization = false
        customUserMessage = userMessage
        self.severity = severity
        fallbackSuggestedAction = ""
        customSuggestedAction = suggestedAction
        self.recoverability = recoverability
        technicalDetails = rawContext.isEmpty ? nil : rawContext
    }
}

extension CoreErrorMappingSnapshot {
    static func localized(_ input: CoreErrorLocalizedSnapshotInput) -> CoreErrorMappingSnapshot {
        var snapshot = CoreErrorMappingSnapshot(
            kind: input.kind,
            userMessage: input.userMessage,
            severity: input.severity,
            suggestedAction: input.suggestedAction,
            recoverability: input.recoverability,
            rawContext: input.rawContext
        )
        snapshot.usesKindLocalization = true
        return snapshot
    }

    init(coreMapping: ErrorMapping) {
        kind = CoreErrorKindSnapshot(coreKind: coreMapping.kind)
        code = coreMapping.code
        field = coreMapping.field
        arguments = coreMapping.arguments.map { CoreErrorArgumentSnapshot(name: $0.name, value: $0.value) }
        recoveryActionIDs = coreMapping.recoveryActionIds
        fallbackUserMessage = ""
        usesKindLocalization = false
        customUserMessage = nil
        severity = CoreErrorSeveritySnapshot(coreSeverity: coreMapping.severity)
        fallbackSuggestedAction = ""
        customSuggestedAction = nil
        recoverability = CoreErrorRecoverabilitySnapshot(coreRecoverability: coreMapping.recoverability)
        technicalDetails = coreMapping.technicalDetails
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
            message: nil,
            expectedRevision: nil,
            currentRevision: nil
        )))
    }

    static func database(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(coreMapping: mapCoreError(input: ErrorMappingInput(
            kind: .db,
            path: nil,
            reason: nil,
            message: rawContext,
            expectedRevision: nil,
            currentRevision: nil
        )))
    }

    static func conflict(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(coreMapping: mapCoreError(input: ErrorMappingInput(
            kind: .conflict,
            path: rawContext,
            reason: nil,
            message: nil,
            expectedRevision: nil,
            currentRevision: nil
        )))
    }

    var recoveryText: String {
        recoveryText(fallback: userMessage)
    }

    func recoveryText(fallback: String) -> String {
        guard customSuggestedAction != nil || usesKindLocalization ||
            !fallbackSuggestedAction.isEmpty || !code.isEmpty || !recoveryActionIDs.isEmpty
        else {
            return fallback
        }
        return suggestedAction
    }

    func recoveryMessage(fallback: LocalizedMessage) -> LocalizedMessage {
        if customSuggestedAction != nil {
            return suggestedActionDescriptor
        }
        return !usesKindLocalization && fallbackSuggestedAction.isEmpty ? fallback : suggestedActionDescriptor
    }

    private static let knownRecoveryActionIDs: Set<String> = [
        "retry", "collect_diagnostics", "open_recovery", "open_settings", "review_configuration",
        "fix_input", "open_classifier", "refresh", "review_conflict", "reload_latest", "review_changes",
        "skip", "keep_both", "review_replace", "locate_file", "refresh_history", "initialize_repository",
        "choose_repository", "change_path", "download_and_retry", "choose_local_repository", "choose_folder",
        "open_system_settings", "leave_flow", "open_issue"
    ]
}

struct CoreErrorLocalizedSnapshotInput {
    var kind: CoreErrorKindSnapshot
    var userMessage: String
    var severity: CoreErrorSeveritySnapshot
    var suggestedAction: String
    var recoverability: CoreErrorRecoverabilitySnapshot
    var rawContext: String
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
