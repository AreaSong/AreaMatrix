import Combine

// swiftlint:disable file_length
import Foundation

enum RemoteProviderKindState: String, CaseIterable, Equatable, Identifiable {
    case openAi, anthropic, other

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .openAi: "OpenAI"
        case .anthropic: "Anthropic"
        case .other: "Other"
        }
    }
}

enum RemoteProviderTestStatusState: String, Equatable {
    case succeeded, providerRejected, connectionFailed, unsupportedProvider
}

enum AIClassificationSuggestionPanelState: Equatable {
    case idle
    case loading
    case loaded(AIClassificationSuggestionState)
    case failed(AISettingsError, AiFallbackStatus?)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct RemoteProviderTestRequestState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var keyReference: String
}

struct RemoteProviderEnableRequestState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var keyReference: String
    var featureScope: [AISettingsFeatureKind]
    var verificationToken: String
    var dataFlowConfirmed: Bool
}

struct RemoteProviderDisableRequestState: Equatable {
    var removeStoredCredential: Bool
}

struct RemoteProviderConfigState: Equatable {
    var providerConfigured: Bool
    var providerVerified: Bool
    var remoteProviderEnabled: Bool
    var provider: RemoteProviderKindState?
    var modelID: String?
    var endpointURL: String?
    var credentialConfigured: Bool
    var featureScope: [AISettingsFeatureKind]
    var updatedAt: Int64?
    var disabledReason: String?
}

struct RemoteProviderTestResultState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var status: RemoteProviderTestStatusState
    var providerVerified: Bool
    var verificationToken: String?
    var sanitizedMessage: String
}

@MainActor
final class AIClassificationSuggestionPanelModel: ObservableObject {
    @Published private(set) var state: AIClassificationSuggestionPanelState = .idle
    @Published private(set) var fallbackStatus: AiFallbackStatus?
    @Published private(set) var isResolvingFallbackStatus = false

    let repoPath: String
    let request: AIClassificationSuggestionRequestState
    private let suggester: any CoreAIClassificationSuggesting
    private let fallbackReader: any CoreAIClassificationFallbackStatusReading
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        request: AIClassificationSuggestionRequestState,
        suggester: any CoreAIClassificationSuggesting = CoreBridge(),
        fallbackReader: any CoreAIClassificationFallbackStatusReading = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.request = request
        self.suggester = suggester
        self.fallbackReader = fallbackReader
        self.errorMapper = errorMapper
    }

    var suggestion: AIClassificationSuggestionState? {
        guard case let .loaded(suggestion) = state else { return nil }
        return suggestion
    }

    var failure: AISettingsError? {
        guard case let .failed(error, _) = state else { return nil }
        return error
    }

    var canAskForSuggestion: Bool {
        !state.isLoading && !isResolvingFallbackStatus
    }

    var statusText: String {
        switch state {
        case .idle:
            "No AI category suggestion is available."
        case .loading:
            "Loading AI suggestion..."
        case let .loaded(suggestion):
            fallbackStatus?.title ?? Self.statusText(for: suggestion)
        case let .failed(_, fallback):
            fallback?.title ?? "AI suggestion failed."
        }
    }

    var acceptDisabledReason: String? {
        guard let suggestion else { return "No suggestion to accept." }
        switch suggestion.status {
        case .suggested:
            if suggestion.suggestedCategory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                return "Target category is missing."
            }
            return suggestion.requiresUserConfirmation ? nil : "AI suggestion must require user confirmation."
        case .noSuggestion:
            return "No suggestion to accept."
        case .skipped:
            return Self.skippedText(for: suggestion.skippedReason)
        case .unavailable:
            return fallbackStatus?.retryDisabledReason ?? "AI suggestion is unavailable."
        }
    }

    func askForSuggestion() async {
        guard canAskForSuggestion else { return }
        state = .loading
        fallbackStatus = nil
        isResolvingFallbackStatus = false
        do {
            let suggestion = try await suggester.suggestCategoryWithAI(repoPath: repoPath, request: request)
            state = .loaded(suggestion)
            isResolvingFallbackStatus = suggestion.fallbackStatusRequest != nil
            fallbackStatus = await loadFallbackStatus(for: suggestion)
            isResolvingFallbackStatus = false
        } catch {
            let mappedError = await suggestionError(for: error)
            isResolvingFallbackStatus = true
            let fallback = await loadFallbackStatus(for: error)
            fallbackStatus = fallback
            isResolvingFallbackStatus = false
            state = .failed(mappedError, fallback)
        }
    }

    @discardableResult
    func retryFallbackSuggestion() async -> Bool {
        guard fallbackStatus?.retryable == true else { return false }
        await askForSuggestion()
        return true
    }

    private func suggestionError(for error: Error) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: "AI category suggestion could not be loaded.",
                recovery: mapping.suggestedAction.isEmpty ? "Retry or classify manually." : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: "AI category suggestion could not be loaded.",
            recovery: "Retry or classify manually.",
            detail: error.localizedDescription
        )
    }

    private static func statusText(for suggestion: AIClassificationSuggestionState) -> String {
        switch suggestion.status {
        case .suggested:
            "AI suggested a category."
        case .noSuggestion:
            "No AI category suggestion is available."
        case .skipped:
            skippedText(for: suggestion.skippedReason)
        case .unavailable:
            "AI suggestion is unavailable."
        }
    }

    private static func skippedText(for reason: AIClassificationSuggestionSkipReasonState?) -> String {
        switch reason {
        case .aiDisabled:
            "AI classification suggestions are off."
        case .featureDisabled:
            "AI classification feature is off."
        case .ruleResultConfident:
            "Rule classification is already confident."
        case .noEligibleContext:
            "No eligible context is available for AI."
        case .privacyRule:
            "Skipped by privacy rule."
        case .providerUnavailable:
            "AI provider is unavailable."
        case nil:
            "AI suggestion was skipped."
        }
    }

    private func loadFallbackStatus(for suggestion: AIClassificationSuggestionState) async -> AiFallbackStatus? {
        guard let request = suggestion.fallbackStatusRequest else { return nil }
        do {
            return try await fallbackReader.classificationFallbackStatus(repoPath: repoPath, request: request)
        } catch {
            return fallbackReaderFailureStatus(for: error, request: request)
        }
    }

    private func loadFallbackStatus(for error: Error) async -> AiFallbackStatus? {
        let providerError = providerErrorSnapshot(for: error)
        let request = AiFallbackStatusRequest(
            operation: .classificationSuggestion,
            route: nil,
            providerError: providerError.kind,
            providerErrorCode: providerError.code,
            privacyDecision: nil,
            privacySkippedReason: nil,
            categorySkippedReason: nil,
            semanticFallbackReason: nil,
            callLogStatus: .failed,
            callLogId: nil,
            privacyRuleId: nil,
            retryAfter: nil
        )
        do {
            return try await fallbackReader.classificationFallbackStatus(repoPath: repoPath, request: request)
        } catch {
            return fallbackReaderFailureStatus(for: error, request: request)
        }
    }

    private func providerErrorSnapshot(for error: Error) -> (kind: AiFallbackProviderErrorKind, code: String) {
        guard let coreError = error as? CoreError else { return (.internalFailure, "SwiftError") }
        switch coreError {
        case .Config:
            return (.providerUnavailable, "Config")
        case .PermissionDenied:
            return (.remoteFailed, "PermissionDenied")
        default:
            return (.internalFailure, "Internal")
        }
    }

    private func fallbackReaderFailureStatus(
        for error: Error,
        request: AiFallbackStatusRequest
    ) -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .internalFailure,
            category: .error,
            title: "AI fallback status could not be loaded.",
            message: fallbackReaderFailureMessage(for: error),
            retryable: false,
            retryDisabledReason: "Classify manually or retry after the fallback status is available.",
            primaryAction: .classifyManually,
            secondaryAction: request.callLogId == nil ? nil : .viewCallLog,
            nonAiFallbackAction: .classifyManually,
            route: request.route,
            callLogId: request.callLogId,
            privacyRuleId: request.privacyRuleId,
            retryAfter: nil
        )
    }

    private func fallbackReaderFailureMessage(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return "AreaMatrix could not read the standardized AI category fallback state."
        }
        switch coreError {
        case .Config:
            return "AreaMatrix could not read the AI category fallback state because fallback metadata is invalid."
        case .PermissionDenied:
            return "AreaMatrix does not have permission to read the AI category fallback metadata."
        default:
            return "AreaMatrix could not read the standardized AI category fallback state."
        }
    }
}

enum RemotePrivacyGateAction: Equatable {
    case enable, disable
}

@MainActor
final class RemotePrivacyGateModel: ObservableObject {
    @Published private(set) var snapshot: AiPrivacyRulesSnapshot?
    @Published private(set) var failure: AISettingsError?
    @Published private(set) var pendingAction: RemotePrivacyGateAction?
    @Published private(set) var isSaving = false

    let repoPath: String
    private let bridge: any CoreAIPrivacyRulesManaging
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        bridge: any CoreAIPrivacyRulesManaging = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.bridge = bridge
        self.errorMapper = errorMapper
    }

    var statusText: String {
        if isSaving { return "Updating privacy gate..." }
        guard let snapshot else { return "Privacy rules are loading." }
        if snapshot.privacyGateEnabled {
            return "Privacy gate is on. Rules are checked before every remote AI call."
        }
        return "Privacy gate is off. Remote AI calls are blocked until the gate is enabled."
    }

    func load() async {
        guard !isSaving else { return }
        do {
            snapshot = try await bridge.loadAIPrivacyRules(repoPath: repoPath)
            failure = nil
        } catch {
            failure = await privacyError(
                for: error,
                message: "Remote privacy rules could not be loaded.",
                recovery: "Retry loading privacy rules before enabling remote AI."
            )
        }
    }

    @discardableResult
    func enablePrivacyGate(providerConfig: RemoteProviderConfigState?) async -> Bool {
        await setPrivacyGate(
            true,
            action: .enable,
            providerConfig: providerConfig,
            message: "Remote provider was configured, but privacy gate could not be enabled.",
            recovery: "Retry enable privacy gate, open privacy rules, or disable remote AI."
        )
    }

    @discardableResult
    func disablePrivacyGate(providerConfig: RemoteProviderConfigState?) async -> Bool {
        await setPrivacyGate(
            false,
            action: .disable,
            providerConfig: providerConfig,
            message: "Remote AI was disabled, but privacy gate could not be disabled.",
            recovery: "Retry disable privacy gate. Remote provider remains disabled."
        )
    }

    @discardableResult
    func retryPending(providerConfig: RemoteProviderConfigState?) async -> Bool {
        switch pendingAction {
        case .enable:
            await enablePrivacyGate(providerConfig: providerConfig)
        case .disable:
            await disablePrivacyGate(providerConfig: providerConfig)
        case nil:
            false
        }
    }

    private func setPrivacyGate(
        _ enabled: Bool,
        action: RemotePrivacyGateAction,
        providerConfig: RemoteProviderConfigState?,
        message: String,
        recovery: String
    ) async -> Bool {
        guard let providerConfig else {
            failure = AISettingsError(message: message, recovery: recovery, detail: "Remote provider state is missing.")
            pendingAction = action
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let base = try await currentSnapshot()
            let updated = try await bridge.updateAIPrivacyRules(
                repoPath: repoPath,
                request: base.privacyGateUpdateRequest(enabled: enabled, providerConfig: providerConfig)
            )
            return handleUpdatedSnapshot(
                updated,
                expectedGate: enabled,
                action: action,
                message: message,
                recovery: recovery
            )
        } catch {
            failure = await privacyError(for: error, message: message, recovery: recovery)
            pendingAction = action
            return false
        }
    }

    private func currentSnapshot() async throws -> AiPrivacyRulesSnapshot {
        if let snapshot { return snapshot }
        let loaded = try await bridge.loadAIPrivacyRules(repoPath: repoPath)
        snapshot = loaded
        return loaded
    }

    private func handleUpdatedSnapshot(
        _ updated: AiPrivacyRulesSnapshot,
        expectedGate: Bool,
        action: RemotePrivacyGateAction,
        message: String,
        recovery: String
    ) -> Bool {
        snapshot = updated
        guard updated.privacyGateEnabled == expectedGate else {
            failure = AISettingsError(message: message, recovery: recovery, detail: "Privacy gate returned unchanged.")
            pendingAction = action
            return false
        }
        failure = nil
        pendingAction = nil
        return true
    }

    private func privacyError(for error: Error, message: String, recovery: String) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: message,
                recovery: mapping.suggestedAction.isEmpty ? recovery : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: recovery, detail: error.localizedDescription)
    }
}

private extension AiPrivacyRulesSnapshot {
    func privacyGateUpdateRequest(
        enabled: Bool,
        providerConfig: RemoteProviderConfigState
    ) -> AiPrivacyRulesUpdateRequest {
        AiPrivacyRulesUpdateRequest(
            privacyGateEnabled: enabled,
            rules: rules.map(AiPrivacyRuleInput.init(record:)),
            remoteAllowedFields: remoteAllowedFields.map(AiPrivacyFieldRule.init(fieldState:)),
            providerScope: AiPrivacyProviderScopeSnapshot(providerConfig: providerConfig),
            confirmed: true
        )
    }
}

private extension AiPrivacyRuleInput {
    init(record: AiPrivacyRuleRecord) {
        self.init(
            ruleId: record.ruleId,
            name: record.name,
            kind: record.kind,
            pattern: record.pattern,
            appliesTo: record.appliesTo,
            enabled: record.enabled,
            description: record.description
        )
    }
}

private extension AiPrivacyFieldRule {
    init(fieldState: AiPrivacyFieldState) {
        self.init(field: fieldState.field, allowRemote: fieldState.allowRemote)
    }
}

private extension AiPrivacyProviderScopeSnapshot {
    init(providerConfig: RemoteProviderConfigState) {
        self.init(
            providerConfigured: providerConfig.providerConfigured,
            providerVerified: providerConfig.providerVerified,
            remoteProviderEnabled: providerConfig.remoteProviderEnabled,
            featureScope: providerConfig.featureScope.map(AiFeatureKind.init(snapshotFeature:))
        )
    }
}
