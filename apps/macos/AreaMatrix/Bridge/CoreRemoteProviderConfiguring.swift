import AreaMatrixFeatureAI
import Foundation

enum AIFallbackOperationSnapshot: Equatable {
    case classificationSuggestion
    case semanticSearch
    case embeddingIndexBuild
}

enum AIFallbackActionSnapshot: Equatable, Hashable {
    case retry
    case retryLater
    case openAISettings
    case openLocalModelStatus
    case configureRemoteAI
    case viewPrivacyRule
    case viewCallLog
    case buildSemanticIndex
    case useNormalSearch
    case classifyManually
}

enum AIFallbackCategorySnapshot: Equatable {
    case disabled
    case skipped
    case unavailable
    case error
}

enum AIFallbackKindSnapshot: Equatable {
    case aiDisabled
    case featureDisabled
    case localModelNotReady
    case remoteNotConfigured
    case remoteFailed
    case providerUnavailable
    case privacySkipped
    case semanticIndexNotReady
    case noEligibleInput
    case normalSearchUnavailable
    case callLogUnavailable
    case rateLimited
    case timeout
    case internalFailure
}

enum AIFallbackProviderErrorKindSnapshot: Equatable {
    case localModelNotReady
    case remoteNotConfigured
    case remoteFailed
    case providerUnavailable
    case rateLimited
    case timeout
    case callLogUnavailable
    case internalFailure
}

enum AIPrivacyDecisionSnapshot: Equatable {
    case allowed
    case denied
    case skipped
}

enum AIPrivacySkippedReasonSnapshot: Equatable {
    case privacyGateDisabled
    case scopeNotAllowed
    case providerNotConfigured
    case providerNotVerified
    case providerDisabled
    case privacyRule
    case fieldRule
    case noEligibleInput
}

struct AIFallbackStatusRequestSnapshot: Equatable {
    var operation: AIFallbackOperationSnapshot
    var route: AICallLogRouteSnapshot?
    var providerError: AIFallbackProviderErrorKindSnapshot?
    var providerErrorCode: String?
    var privacyDecision: AIPrivacyDecisionSnapshot?
    var privacySkippedReason: AIPrivacySkippedReasonSnapshot?
    var categorySkippedReason: AIClassificationSuggestionSkipReasonState?
    var semanticFallbackReason: SemanticSearchFallbackReasonSnapshot?
    var callLogStatus: AICallLogStatusSnapshot?
    var callLogID: Int64?
    var privacyRuleID: String?
    var retryAfter: Int64?
}

struct AIFallbackStatusSnapshot: Equatable {
    var operation: AIFallbackOperationSnapshot
    var kind: AIFallbackKindSnapshot
    var category: AIFallbackCategorySnapshot
    var title: String
    var message: String
    var retryable: Bool
    var retryDisabledReason: String?
    var primaryAction: AIFallbackActionSnapshot?
    var secondaryAction: AIFallbackActionSnapshot?
    var nonAIFallbackAction: AIFallbackActionSnapshot
    var route: AICallLogRouteSnapshot?
    var callLogID: Int64?
    var privacyRuleID: String?
    var retryAfter: Int64?
}

protocol CoreRemoteProviderConfiguring: Sendable {
    func loadRemoteProviderConfig(repoPath: String) async throws -> RemoteProviderConfigState
    func testRemoteProvider(
        repoPath: String,
        request: RemoteProviderTestRequestState
    ) async throws -> RemoteProviderTestResultState
    func enableRemoteProvider(
        repoPath: String,
        request: RemoteProviderEnableRequestState
    ) async throws -> RemoteProviderConfigState
    func disableRemoteProvider(
        repoPath: String,
        request: RemoteProviderDisableRequestState
    ) async throws -> RemoteProviderConfigState
}

protocol CoreAIPrivacyRulesManaging: Sendable {
    func loadAIPrivacyRules(repoPath: String) async throws -> AIPrivacyRulesSnapshot
    func updateAIPrivacyRules(
        repoPath: String,
        request: AIPrivacyRulesUpdateRequestSnapshot
    ) async throws -> AIPrivacyRulesSnapshot
}

protocol CoreAIClassificationSuggesting: Sendable {
    func suggestCategoryWithAI(
        repoPath: String,
        request: AIClassificationSuggestionRequestState
    ) async throws -> AIClassificationSuggestionState
}

// swiftlint:disable:next type_name
protocol CoreAIClassificationFallbackStatusReading: Sendable {
    func classificationFallbackStatus(
        repoPath: String,
        request: AIFallbackStatusRequestSnapshot
    ) async throws -> AIFallbackStatusSnapshot
}

extension CoreBridge: CoreRemoteProviderConfiguring {
    func loadRemoteProviderConfig(repoPath: String) async throws -> RemoteProviderConfigState {
        try await Task.detached(priority: .userInitiated) {
            try RemoteProviderConfigState(coreSnapshot: loadRemoteAiProviderConfig(repoPath: repoPath))
        }.value
    }

    func testRemoteProvider(
        repoPath: String,
        request: RemoteProviderTestRequestState
    ) async throws -> RemoteProviderTestResultState {
        try Task.checkCancellation()
        let plan = try prepareRemoteAiProviderProbe(
            repoPath: repoPath,
            request: RemoteProviderTestRequest(snapshot: request)
        )
        let observation = await remoteProviderProbePerformer.perform(
            plan: RemoteProviderProbePlanState(corePlan: plan)
        )
        if Task.isCancelled {
            _ = try? completeRemoteAiProviderProbe(
                repoPath: repoPath,
                observation: RemoteProviderProbeObservation(state: RemoteProviderProbeObservationState(
                    probeToken: plan.probeToken,
                    outcome: .connectionFailed,
                    httpStatus: nil
                ))
            )
            throw CancellationError()
        }
        return try RemoteProviderTestResultState(coreResult: completeRemoteAiProviderProbe(
            repoPath: repoPath,
            observation: RemoteProviderProbeObservation(state: observation)
        ))
    }

    func enableRemoteProvider(
        repoPath: String,
        request: RemoteProviderEnableRequestState
    ) async throws -> RemoteProviderConfigState {
        try await Task.detached(priority: .userInitiated) {
            try RemoteProviderConfigState(coreSnapshot: enableRemoteAiProvider(
                repoPath: repoPath,
                request: RemoteProviderEnableRequest(snapshot: request)
            ))
        }.value
    }

    func disableRemoteProvider(
        repoPath: String,
        request: RemoteProviderDisableRequestState
    ) async throws -> RemoteProviderConfigState {
        try await Task.detached(priority: .userInitiated) {
            try RemoteProviderConfigState(coreSnapshot: disableRemoteAiProvider(
                repoPath: repoPath,
                request: RemoteProviderDisableRequest(snapshot: request)
            ))
        }.value
    }
}

extension CoreBridge: CoreAIClassificationSuggesting {
    func suggestCategoryWithAI(
        repoPath: String,
        request: AIClassificationSuggestionRequestState
    ) async throws -> AIClassificationSuggestionState {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: repoPath)
        let coreRequest = try AiCategorySuggestionRequest(snapshot: request, contentLocale: contentLocale)
        return try await Task.detached(priority: .userInitiated) {
            try AIClassificationSuggestionState(coreSuggestion: suggestCategoryWithAi(
                repoPath: repoPath,
                request: coreRequest
            ))
        }.value
    }
}

extension CoreBridge: CoreAIClassificationFallbackStatusReading {
    func classificationFallbackStatus(
        repoPath: String,
        request: AIFallbackStatusRequestSnapshot
    ) async throws -> AIFallbackStatusSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AIFallbackStatusSnapshot(getAiFallbackStatus(
                repoPath: repoPath,
                request: AiFallbackStatusRequest(request)
            ))
        }.value
    }
}

extension AIFallbackStatusSnapshot {
    init(_ status: AiFallbackStatus) {
        self.init(
            operation: AIFallbackOperationSnapshot(status.operation),
            kind: AIFallbackKindSnapshot(status.kind),
            category: AIFallbackCategorySnapshot(status.category),
            title: status.title,
            message: status.message,
            retryable: status.retryable,
            retryDisabledReason: status.retryDisabledReason,
            primaryAction: status.primaryAction.map(AIFallbackActionSnapshot.init),
            secondaryAction: status.secondaryAction.map(AIFallbackActionSnapshot.init),
            nonAIFallbackAction: AIFallbackActionSnapshot(status.nonAiFallbackAction),
            route: status.route.map(AICallLogRouteSnapshot.init),
            callLogID: status.callLogId,
            privacyRuleID: status.privacyRuleId,
            retryAfter: status.retryAfter
        )
    }
}

extension AiFallbackStatusRequest {
    init(_ request: AIFallbackStatusRequestSnapshot) {
        self.init(
            operation: request.operation.coreValue,
            route: request.route?.coreValue,
            providerError: request.providerError?.coreValue,
            providerErrorCode: request.providerErrorCode,
            privacyDecision: request.privacyDecision?.coreValue,
            privacySkippedReason: request.privacySkippedReason?.coreValue,
            categorySkippedReason: request.categorySkippedReason.map { AiCategorySuggestionSkipReason($0) },
            semanticFallbackReason: request.semanticFallbackReason.map(SemanticSearchFallbackReason.init),
            callLogStatus: request.callLogStatus?.coreValue,
            callLogId: request.callLogID,
            privacyRuleId: request.privacyRuleID,
            retryAfter: request.retryAfter
        )
    }
}

private extension AIFallbackOperationSnapshot {
    init(_ operation: AiFallbackOperation) {
        switch operation {
        case .classificationSuggestion: self = .classificationSuggestion
        case .semanticSearch: self = .semanticSearch
        case .embeddingIndexBuild: self = .embeddingIndexBuild
        }
    }

    var coreValue: AiFallbackOperation {
        switch self {
        case .classificationSuggestion: .classificationSuggestion
        case .semanticSearch: .semanticSearch
        case .embeddingIndexBuild: .embeddingIndexBuild
        }
    }
}

private extension AIFallbackActionSnapshot {
    init(_ action: AiFallbackAction) {
        switch action {
        case .retry: self = .retry
        case .retryLater: self = .retryLater
        case .openAiSettings: self = .openAISettings
        case .openLocalModelStatus: self = .openLocalModelStatus
        case .configureRemoteAi: self = .configureRemoteAI
        case .viewPrivacyRule: self = .viewPrivacyRule
        case .viewCallLog: self = .viewCallLog
        case .buildSemanticIndex: self = .buildSemanticIndex
        case .useNormalSearch: self = .useNormalSearch
        case .classifyManually: self = .classifyManually
        }
    }
}

private extension AIFallbackKindSnapshot {
    init(_ kind: AiFallbackKind) {
        guard let snapshot = Self.byCoreValue[kind] else {
            preconditionFailure("Unhandled AiFallbackKind from Core: \(kind)")
        }
        self = snapshot
    }

    private static let byCoreValue: [AiFallbackKind: Self] = [
        .aiDisabled: .aiDisabled,
        .featureDisabled: .featureDisabled,
        .localModelNotReady: .localModelNotReady,
        .remoteNotConfigured: .remoteNotConfigured,
        .remoteFailed: .remoteFailed,
        .providerUnavailable: .providerUnavailable,
        .privacySkipped: .privacySkipped,
        .semanticIndexNotReady: .semanticIndexNotReady,
        .noEligibleInput: .noEligibleInput,
        .normalSearchUnavailable: .normalSearchUnavailable,
        .callLogUnavailable: .callLogUnavailable,
        .rateLimited: .rateLimited,
        .timeout: .timeout,
        .internalFailure: .internalFailure
    ]
}

private extension AIFallbackCategorySnapshot {
    init(_ category: AiFallbackCategory) {
        switch category {
        case .disabled: self = .disabled
        case .skipped: self = .skipped
        case .unavailable: self = .unavailable
        case .error: self = .error
        }
    }
}

private extension AIFallbackProviderErrorKindSnapshot {
    var coreValue: AiFallbackProviderErrorKind {
        switch self {
        case .localModelNotReady: .localModelNotReady
        case .remoteNotConfigured: .remoteNotConfigured
        case .remoteFailed: .remoteFailed
        case .providerUnavailable: .providerUnavailable
        case .rateLimited: .rateLimited
        case .timeout: .timeout
        case .callLogUnavailable: .callLogUnavailable
        case .internalFailure: .internalFailure
        }
    }
}

private extension AiCategorySuggestionSkipReason {
    init(_ reason: AIClassificationSuggestionSkipReasonState) {
        switch reason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .ruleResultConfident: self = .ruleResultConfident
        case .noEligibleContext: self = .noEligibleContext
        case .privacyRule: self = .privacyRule
        case .providerUnavailable: self = .providerUnavailable
        }
    }
}

private extension SemanticSearchFallbackReason {
    init(_ reason: SemanticSearchFallbackReasonSnapshot) {
        switch reason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .providerUnavailable: self = .providerUnavailable
        case .privacyRule: self = .privacyRule
        case .semanticIndexNotReady: self = .semanticIndexNotReady
        case .callLogUnavailable: self = .callLogUnavailable
        case .noEligibleInput: self = .noEligibleInput
        case .normalSearchUnavailable: self = .normalSearchUnavailable
        case .rateLimited: self = .rateLimited
        case .timeout: self = .timeout
        }
    }
}
