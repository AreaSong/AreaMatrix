import Combine
import Foundation

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
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: "AI category suggestion could not be loaded.",
                recovery: mapping.recoveryText(fallback: "Retry or classify manually."),
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
            return await fallbackReaderFailureStatus(for: error, request: request)
        }
    }

    private func loadFallbackStatus(for error: Error) async -> AiFallbackStatus? {
        let providerError = await providerErrorSnapshot(for: error)
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
            return await fallbackReaderFailureStatus(for: error, request: request)
        }
    }

    private func providerErrorSnapshot(for error: Error) async -> (kind: AiFallbackProviderErrorKind, code: String) {
        guard let mapping = await errorMapper.mapCoreErrorIfPresent(error) else {
            return (.internalFailure, "SwiftError")
        }
        switch mapping.kind {
        case .config:
            return (.providerUnavailable, "Config")
        case .permissionDenied:
            return (.remoteFailed, "PermissionDenied")
        default:
            return (.internalFailure, "Internal")
        }
    }

    private func fallbackReaderFailureStatus(
        for error: Error,
        request: AiFallbackStatusRequest
    ) async -> AiFallbackStatus {
        let message = await fallbackReaderFailureMessage(for: error)
        return AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .internalFailure,
            category: .error,
            title: "AI fallback status could not be loaded.",
            message: message,
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

    private func fallbackReaderFailureMessage(for error: Error) async -> String {
        guard let mapping = await errorMapper.mapCoreErrorIfPresent(error) else {
            return "AreaMatrix could not read the standardized AI category fallback state."
        }
        switch mapping.kind {
        case .config:
            return "AreaMatrix could not read the AI category fallback state because fallback metadata is invalid."
        case .permissionDenied:
            return "AreaMatrix does not have permission to read the AI category fallback metadata."
        default:
            return "AreaMatrix could not read the standardized AI category fallback state."
        }
    }
}
