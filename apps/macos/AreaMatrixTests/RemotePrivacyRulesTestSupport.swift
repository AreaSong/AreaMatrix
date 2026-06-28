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

extension AiPrivacyEvaluationReport {
    static func remoteProviderConfigAllowedPrivacyEvaluation() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .allowed,
            skippedReason: nil,
            providerGateReason: nil,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [.fileName, .repoRelativePath, .extension],
            blockedFields: [],
            sentFields: [.fileName, .repoRelativePath],
            message: "Privacy rules allow this AI request."
        )
    }

    static func aiTagSuggestionPrivacyRuleBlocked() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AiPrivacyRuleMatch(
                    ruleId: "rule-confidential",
                    name: "Block confidential",
                    kind: .keyword,
                    pattern: "confidential",
                    appliesTo: .remoteAi,
                    matchedField: .fileName
                )
            ],
            matchedFieldType: .fileName,
            allowedFields: [],
            blockedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            sentFields: [],
            message: "A privacy rule blocked the tag suggestion input."
        )
    }
}

extension AiPrivacyRulesSnapshot {
    static func remoteProviderConfigPrivacyRules(
        privacyGateEnabled: Bool = false,
        featureScope: [AiFeatureKind] = [.autoSummaries]
    ) -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: privacyGateEnabled,
            rules: [.remoteProviderConfigRuleRecord()],
            remoteAllowedFields: [
                AiPrivacyFieldState(field: .fileName, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .extractedTextExcerpt, allowRemote: false, lastMatchedCount: 2),
                AiPrivacyFieldState(field: .noteSummary, allowRemote: true, lastMatchedCount: 0)
            ],
            providerScope: AiPrivacyProviderScopeSnapshot(
                providerConfigured: true,
                providerVerified: true,
                remoteProviderEnabled: false,
                featureScope: featureScope
            ),
            updatedAt: 901,
            remoteBlockedByDefault: true
        )
    }

    func applyingPrivacyGateRequest(_ request: AiPrivacyRulesUpdateRequest) -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: request.privacyGateEnabled,
            rules: request.rules.map(AiPrivacyRuleRecord.init(input:)),
            remoteAllowedFields: request.remoteAllowedFields.map(AiPrivacyFieldState.init(rule:)),
            providerScope: request.providerScope,
            updatedAt: 902,
            remoteBlockedByDefault: remoteBlockedByDefault
        )
    }
}

extension AiPrivacyRuleRecord {
    static func remoteProviderConfigRuleRecord() -> AiPrivacyRuleRecord {
        AiPrivacyRuleRecord(
            ruleId: "rule-confidential",
            name: "Block confidential",
            kind: .keyword,
            pattern: "confidential",
            appliesTo: .remoteAi,
            enabled: true,
            description: "Fixture privacy rule",
            matchCount: 4,
            lastMatchedAt: 900
        )
    }

    init(input: AiPrivacyRuleInput) {
        self.init(
            ruleId: input.ruleId ?? "generated-rule",
            name: input.name,
            kind: input.kind,
            pattern: input.pattern,
            appliesTo: input.appliesTo,
            enabled: input.enabled,
            description: input.description,
            matchCount: 0,
            lastMatchedAt: nil
        )
    }
}

extension AiPrivacyFieldState {
    init(rule: AiPrivacyFieldRule) {
        self.init(field: rule.field, allowRemote: rule.allowRemote, lastMatchedCount: 0)
    }
}
