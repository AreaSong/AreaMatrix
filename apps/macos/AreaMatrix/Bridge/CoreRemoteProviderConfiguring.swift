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

// swiftlint:disable:next type_name
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

extension CoreBridge: CoreAIPrivacyEvaluating {
    func evaluateAIPrivacy(
        repoPath: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport {
        try await Task.detached(priority: .userInitiated) {
            try evaluateAiPrivacy(repoPath: repoPath, request: request)
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
