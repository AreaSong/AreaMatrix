import Foundation

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

extension RemoteProviderProbePlanState {
    init(corePlan: RemoteProviderProbePlan) {
        keyReference = corePlan.keyReference
        probeToken = corePlan.probeToken
        method = RemoteProviderProbeMethodState(coreMethod: corePlan.method)
        url = corePlan.url
        headers = corePlan.headers.map(RemoteProviderProbeHeaderState.init(coreHeader:))
        authorization = RemoteProviderProbeAuthorizationState(coreAuthorization: corePlan.authorization)
        timeoutMilliseconds = corePlan.timeoutMillis
        maximumResponseBodyBytes = corePlan.maximumResponseBodyBytes
        followRedirects = corePlan.followRedirects
    }
}

extension RemoteProviderProbeObservation {
    init(state: RemoteProviderProbeObservationState) {
        self.init(
            probeToken: state.probeToken,
            outcome: RemoteProviderProbeOutcome(stateOutcome: state.outcome),
            httpStatus: state.httpStatus
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

private extension RemoteProviderProbeMethodState {
    init(coreMethod: RemoteProviderProbeMethod) {
        switch coreMethod {
        case .get: self = .get
        }
    }
}

private extension RemoteProviderProbeHeaderState {
    init(coreHeader: RemoteProviderProbeHeader) {
        self.init(name: coreHeader.name, value: coreHeader.value)
    }
}

private extension RemoteProviderProbeAuthorizationState {
    init(coreAuthorization: RemoteProviderProbeAuthorization) {
        switch coreAuthorization {
        case .bearer: self = .bearer
        case .anthropicApiKey: self = .anthropicAPIKey
        }
    }
}

private extension RemoteProviderProbeOutcome {
    init(stateOutcome: RemoteProviderProbeOutcomeState) {
        switch stateOutcome {
        case .httpResponse: self = .httpResponse
        case .connectionFailed: self = .connectionFailed
        case .credentialUnavailable: self = .credentialUnavailable
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
