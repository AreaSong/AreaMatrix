@testable import AreaMatrix

actor RemotePrivacyRulesBridge: CoreAIPrivacyRulesManaging, CoreAIPrivacyEvaluating {
    struct Requests: Equatable {
        var loadCount = 0
        var updates: [AiPrivacyRulesUpdateRequest] = []
        var evaluations: [AiPrivacyEvaluationRequest] = []
    }

    private var snapshot: AiPrivacyRulesSnapshot
    private let evaluationReport: AiPrivacyEvaluationReport
    private let updateFails: Bool
    private var recorded = Requests()

    init(
        snapshot: AiPrivacyRulesSnapshot = .remoteProviderConfigPrivacyRules(),
        evaluationReport: AiPrivacyEvaluationReport = .remoteProviderConfigAllowedPrivacyEvaluation(),
        updateFails: Bool = false
    ) {
        self.snapshot = snapshot
        self.evaluationReport = evaluationReport
        self.updateFails = updateFails
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        recorded.loadCount += 1
        return snapshot
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        recorded.updates.append(request)
        if updateFails {
            throw CoreError.Db(message: "privacy gate write failed")
        }
        snapshot = snapshot.applyingPrivacyGateRequest(request)
        return snapshot
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport {
        recorded.evaluations.append(request)
        return evaluationReport
    }

    func requests() -> Requests {
        recorded
    }
}

actor AIPrivacyRulesFailingBridge: CoreAIPrivacyRulesManaging {
    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules read failed")
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request _: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules write failed")
    }
}
