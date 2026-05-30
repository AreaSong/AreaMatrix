import Foundation

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
    func loadAIPrivacyRules(repoPath: String) async throws -> AiPrivacyRulesSnapshot
    func updateAIPrivacyRules(
        repoPath: String,
        request: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot
}

protocol CoreAIClassificationSuggesting: Sendable {
    func suggestCategoryWithAI(
        repoPath: String,
        request: AIClassificationSuggestionRequestState
    ) async throws -> AIClassificationSuggestionState
}

protocol CoreAIClassificationFallbackStatusReading: Sendable {
    func classificationFallbackStatus(
        repoPath: String,
        request: AiFallbackStatusRequest
    ) async throws -> AiFallbackStatus
}

protocol CoreAICallLogListing: Sendable {
    func listAICalls(
        repoPath: String,
        filter: AiCallLogFilter,
        pagination: AiCallLogPagination
    ) async throws -> AiCallLogPage
}

protocol CoreAICallLogClearing: Sendable {
    func clearAICallLog(
        repoPath: String,
        request: AiCallLogClearRequest
    ) async throws -> AiCallLogClearReport
}

enum AIClassificationContextPolicyState: Equatable {
    case fileNameOnly
    case fileNameAndPath
    case limitedTextSummary
}

enum AIClassificationSuggestionStatusState: Equatable {
    case suggested
    case noSuggestion
    case skipped
    case unavailable
}

enum AIClassificationSuggestionRouteState: Equatable {
    case local
    case remote

    var label: String {
        switch self {
        case .local: "Local"
        case .remote: "Remote"
        }
    }
}

enum AIClassificationSuggestionContextFieldState: Equatable {
    case fileName
    case `extension`
    case repoRelativePath
    case limitedTextSummary

    var label: String {
        switch self {
        case .fileName: "filename"
        case .extension: "extension"
        case .repoRelativePath: "repo-relative path"
        case .limitedTextSummary: "limited text summary"
        }
    }
}

enum AIClassificationSuggestionSkipReasonState: Equatable {
    case aiDisabled
    case featureDisabled
    case ruleResultConfident
    case noEligibleContext
    case privacyRule
    case providerUnavailable
}

struct AIClassificationSuggestionRequestState: Equatable {
    var fileID: Int64
    var contextPolicy: AIClassificationContextPolicyState
    var privacyPolicyRef: String? = nil
}

struct AIClassificationSuggestionState: Equatable {
    var fileID: Int64
    var status: AIClassificationSuggestionStatusState
    var currentCategory: String?
    var suggestedCategory: String?
    var confidence: Float
    var reason: String?
    var route: AIClassificationSuggestionRouteState?
    var usedContext: [AIClassificationSuggestionContextFieldState]
    var skippedReason: AIClassificationSuggestionSkipReasonState?
    var privacyRuleID: String?
    var callLogID: Int64?
    var requiresUserConfirmation: Bool
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
        try ensureRemoteProviderProbeRuntime()
        return try await Task.detached(priority: .userInitiated) {
            try RemoteProviderTestResultState(coreResult: testRemoteAiProvider(
                repoPath: repoPath,
                request: RemoteProviderTestRequest(snapshot: request)
            ))
        }.value
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

    private func ensureRemoteProviderProbeRuntime() throws {
        _ = try RemoteProviderProbeRuntimeInstaller().ensureInstalled()
    }
}

extension CoreBridge: CoreAIPrivacyRulesManaging {
    func loadAIPrivacyRules(repoPath: String) async throws -> AiPrivacyRulesSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try listAiPrivacyRules(repoPath: repoPath)
        }.value
    }

    func updateAIPrivacyRules(
        repoPath: String,
        request: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try updateAiPrivacyRules(repoPath: repoPath, request: request)
        }.value
    }
}

extension CoreBridge: CoreAIClassificationSuggesting {
    func suggestCategoryWithAI(
        repoPath: String,
        request: AIClassificationSuggestionRequestState
    ) async throws -> AIClassificationSuggestionState {
        try await Task.detached(priority: .userInitiated) {
            try AIClassificationSuggestionState(coreSuggestion: suggestCategoryWithAi(
                repoPath: repoPath,
                request: AiCategorySuggestionRequest(snapshot: request)
            ))
        }.value
    }
}

extension CoreBridge: CoreAIClassificationFallbackStatusReading {
    func classificationFallbackStatus(
        repoPath: String,
        request: AiFallbackStatusRequest
    ) async throws -> AiFallbackStatus {
        try await Task.detached(priority: .userInitiated) {
            try getAiFallbackStatus(repoPath: repoPath, request: request)
        }.value
    }
}

extension CoreBridge: CoreAICallLogListing {
    func listAICalls(
        repoPath: String,
        filter: AiCallLogFilter,
        pagination: AiCallLogPagination
    ) async throws -> AiCallLogPage {
        try await Task.detached(priority: .userInitiated) {
            try listAiCalls(repoPath: repoPath, filter: filter, pagination: pagination)
        }.value
    }
}

extension CoreBridge: CoreAICallLogClearing {
    func clearAICallLog(
        repoPath: String,
        request: AiCallLogClearRequest
    ) async throws -> AiCallLogClearReport {
        try await Task.detached(priority: .userInitiated) {
            try clearAiCallLog(repoPath: repoPath, request: request)
        }.value
    }
}

extension RemoteProviderConfigState {
    init(coreSnapshot: RemoteProviderConfigSnapshot) {
        providerConfigured = coreSnapshot.providerConfigured
        providerVerified = coreSnapshot.providerVerified
        remoteProviderEnabled = coreSnapshot.remoteProviderEnabled
        provider = coreSnapshot.provider.map(RemoteProviderKindState.init(coreProvider:))
        modelID = coreSnapshot.modelId
        endpointURL = coreSnapshot.endpointUrl
        credentialConfigured = coreSnapshot.credentialConfigured
        featureScope = coreSnapshot.featureScope.map(AISettingsFeatureKind.init(coreFeature:))
        updatedAt = coreSnapshot.updatedAt
        disabledReason = coreSnapshot.disabledReason
    }
}

extension AIClassificationSuggestionState {
    init(coreSuggestion: AiCategorySuggestion) {
        fileID = coreSuggestion.fileId
        status = AIClassificationSuggestionStatusState(coreStatus: coreSuggestion.status)
        currentCategory = coreSuggestion.currentCategory
        suggestedCategory = coreSuggestion.suggestedCategory
        confidence = coreSuggestion.confidence
        reason = coreSuggestion.reason
        route = coreSuggestion.route.map(AIClassificationSuggestionRouteState.init(coreRoute:))
        usedContext = coreSuggestion.usedContext.map(AIClassificationSuggestionContextFieldState.init(coreField:))
        skippedReason = coreSuggestion.skippedReason.map(AIClassificationSuggestionSkipReasonState.init(coreReason:))
        privacyRuleID = coreSuggestion.privacyRuleId
        callLogID = coreSuggestion.callLogId
        requiresUserConfirmation = coreSuggestion.requiresUserConfirmation
    }
}

extension RemoteProviderTestResultState {
    init(coreResult: RemoteProviderTestResult) {
        provider = RemoteProviderKindState(coreProvider: coreResult.provider)
        modelID = coreResult.modelId
        endpointURL = coreResult.endpointUrl
        status = RemoteProviderTestStatusState(coreStatus: coreResult.status)
        providerVerified = coreResult.providerVerified
        verificationToken = coreResult.verificationToken
        sanitizedMessage = coreResult.sanitizedMessage
    }
}

extension AiCategorySuggestionRequest {
    init(snapshot: AIClassificationSuggestionRequestState) {
        self.init(
            fileId: snapshot.fileID,
            contextPolicy: AiCategorySuggestionContextPolicy(snapshotPolicy: snapshot.contextPolicy),
            privacyPolicyRef: snapshot.privacyPolicyRef
        )
    }
}

extension RemoteProviderTestRequest {
    init(snapshot: RemoteProviderTestRequestState) {
        self.init(
            provider: RemoteAiProviderKind(snapshotProvider: snapshot.provider),
            modelId: snapshot.modelID,
            endpointUrl: snapshot.endpointURL,
            keyReference: snapshot.keyReference
        )
    }
}

extension RemoteProviderEnableRequest {
    init(snapshot: RemoteProviderEnableRequestState) {
        self.init(
            provider: RemoteAiProviderKind(snapshotProvider: snapshot.provider),
            modelId: snapshot.modelID,
            endpointUrl: snapshot.endpointURL,
            keyReference: snapshot.keyReference,
            featureScope: snapshot.featureScope.map(AiFeatureKind.init(snapshotFeature:)),
            verificationToken: snapshot.verificationToken,
            dataFlowConfirmed: snapshot.dataFlowConfirmed
        )
    }
}

extension RemoteProviderDisableRequest {
    init(snapshot: RemoteProviderDisableRequestState) {
        self.init(removeStoredCredential: snapshot.removeStoredCredential)
    }
}

private extension AiCategorySuggestionContextPolicy {
    init(snapshotPolicy: AIClassificationContextPolicyState) {
        switch snapshotPolicy {
        case .fileNameOnly: self = .fileNameOnly
        case .fileNameAndPath: self = .fileNameAndPath
        case .limitedTextSummary: self = .limitedTextSummary
        }
    }
}

private extension AIClassificationSuggestionStatusState {
    init(coreStatus: AiCategorySuggestionStatus) {
        switch coreStatus {
        case .suggested: self = .suggested
        case .noSuggestion: self = .noSuggestion
        case .skipped: self = .skipped
        case .unavailable: self = .unavailable
        }
    }
}

private extension AIClassificationSuggestionRouteState {
    init(coreRoute: AiCategorySuggestionRoute) {
        switch coreRoute {
        case .local: self = .local
        case .remote: self = .remote
        }
    }
}

private extension AIClassificationSuggestionContextFieldState {
    init(coreField: AiCategorySuggestionContextField) {
        switch coreField {
        case .fileName: self = .fileName
        case .extension: self = .extension
        case .repoRelativePath: self = .repoRelativePath
        case .limitedTextSummary: self = .limitedTextSummary
        }
    }
}

private extension AIClassificationSuggestionSkipReasonState {
    init(coreReason: AiCategorySuggestionSkipReason) {
        switch coreReason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .ruleResultConfident: self = .ruleResultConfident
        case .noEligibleContext: self = .noEligibleContext
        case .privacyRule: self = .privacyRule
        case .providerUnavailable: self = .providerUnavailable
        }
    }
}

extension AiCallLogRoute {
    init(snapshotRoute: AIClassificationSuggestionRouteState) {
        switch snapshotRoute {
        case .local: self = .local
        case .remote: self = .remote
        }
    }
}

extension AiCategorySuggestionSkipReason {
    init(snapshotReason: AIClassificationSuggestionSkipReasonState) {
        switch snapshotReason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .ruleResultConfident: self = .ruleResultConfident
        case .noEligibleContext: self = .noEligibleContext
        case .privacyRule: self = .privacyRule
        case .providerUnavailable: self = .providerUnavailable
        }
    }
}

extension AIClassificationSuggestionSkipReasonState {
    var fallbackProviderErrorCode: String? {
        switch self {
        case .providerUnavailable:
            "ProviderUnavailable"
        case .aiDisabled, .featureDisabled, .ruleResultConfident, .noEligibleContext, .privacyRule:
            nil
        }
    }
}

extension AIClassificationSuggestionState {
    var fallbackStatusRequest: AiFallbackStatusRequest? {
        switch status {
        case .suggested:
            nil
        case .noSuggestion, .skipped, .unavailable:
            AiFallbackStatusRequest(
                operation: .classificationSuggestion,
                route: route.map(AiCallLogRoute.init(snapshotRoute:)),
                providerError: fallbackProviderError,
                providerErrorCode: skippedReason?.fallbackProviderErrorCode,
                privacyDecision: skippedReason == .privacyRule ? .skipped : nil,
                privacySkippedReason: skippedReason == .privacyRule ? .privacyRule : nil,
                categorySkippedReason: skippedReason.map(AiCategorySuggestionSkipReason.init(snapshotReason:)),
                semanticFallbackReason: nil,
                callLogStatus: fallbackCallLogStatus,
                callLogId: callLogID,
                privacyRuleId: privacyRuleID,
                retryAfter: nil
            )
        }
    }

    private var fallbackProviderError: AiFallbackProviderErrorKind? {
        switch skippedReason {
        case .providerUnavailable:
            .providerUnavailable
        case .aiDisabled, .featureDisabled, .ruleResultConfident, .noEligibleContext, .privacyRule, nil:
            nil
        }
    }

    private var fallbackCallLogStatus: AiCallLogStatus? {
        switch status {
        case .suggested:
            nil
        case .noSuggestion, .skipped:
            .skipped
        case .unavailable:
            .unavailable
        }
    }
}

private extension RemoteProviderKindState {
    init(coreProvider: RemoteAiProviderKind) {
        switch coreProvider {
        case .openAi: self = .openAi
        case .anthropic: self = .anthropic
        case .other: self = .other
        }
    }
}

private extension RemoteProviderTestStatusState {
    init(coreStatus: RemoteProviderTestStatus) {
        switch coreStatus {
        case .succeeded: self = .succeeded
        case .providerRejected: self = .providerRejected
        case .connectionFailed: self = .connectionFailed
        case .unsupportedProvider: self = .unsupportedProvider
        }
    }
}

private extension RemoteAiProviderKind {
    init(snapshotProvider: RemoteProviderKindState) {
        switch snapshotProvider {
        case .openAi: self = .openAi
        case .anthropic: self = .anthropic
        case .other: self = .other
        }
    }
}
