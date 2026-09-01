import AreaMatrixFeatureAI
import Foundation

enum AIPrivacyDecisionState: Equatable {
    case allowed
    case denied
    case skipped
}

enum AIPrivacyEvaluationRouteState: Equatable {
    case local
    case remote
}

enum AIPrivacyInputFieldState: Equatable, Hashable {
    case fileName
    case repoRelativePath
    case `extension`
    case extractedTextExcerpt
    case aiSummary
    case noteSummary
    case tagCategoryContext
}

enum AIPrivacyProviderGateReasonState: Equatable {
    case privacyGateDisabled
    case scopeNotAllowed
    case providerNotConfigured
    case providerNotVerified
    case providerDisabled
}

enum AIPrivacyRuleAppliesToState: Equatable, Hashable {
    case remoteAi
    case localAndRemoteAi
}

enum AIPrivacyRuleKindState: Equatable, Hashable {
    case folder
    case category
    case keyword
    case `extension`
    case tag
}

enum AIPrivacySkippedReasonState: Equatable {
    case privacyGateDisabled
    case scopeNotAllowed
    case providerNotConfigured
    case providerNotVerified
    case providerDisabled
    case privacyRule
    case fieldRule
    case noEligibleInput
}

struct AIPrivacyEvaluationContextSnapshot: Equatable {
    var fileId: Int64?
    var repoRelativePath: String?
    var fileName: String?
    var category: String?
    var `extension`: String?
    var tags: [String]
}

struct AIPrivacyRuleMatchSnapshot: Equatable {
    var ruleId: String
    var name: String
    var kind: AIPrivacyRuleKindState
    var pattern: String
    var appliesTo: AIPrivacyRuleAppliesToState
    var matchedField: AIPrivacyInputFieldState?
}

struct AIPrivacyEvaluationReportSnapshot: Equatable {
    var decision: AIPrivacyDecisionState
    var skippedReason: AIPrivacySkippedReasonState?
    var providerGateReason: AIPrivacyProviderGateReasonState?
    var matchedRules: [AIPrivacyRuleMatchSnapshot]
    var matchedFieldType: AIPrivacyInputFieldState?
    var allowedFields: [AIPrivacyInputFieldState]
    var blockedFields: [AIPrivacyInputFieldState]
    var sentFields: [AIPrivacyInputFieldState]
    var message: String
}

struct AIPrivacyFieldRuleSnapshot: Equatable {
    var field: AIPrivacyInputFieldState
    var allowRemote: Bool
}

struct AIPrivacyFieldStateSnapshot: Equatable {
    var field: AIPrivacyInputFieldState
    var allowRemote: Bool
    var lastMatchedCount: Int64
}

struct AIPrivacyProviderScopeSnapshot: Equatable {
    var providerConfigured: Bool
    var providerVerified: Bool
    var remoteProviderEnabled: Bool
    var featureScope: [AISettingsFeatureKind]
}

struct AIPrivacyRuleInputSnapshot: Equatable {
    var ruleId: String?
    var name: String
    var kind: AIPrivacyRuleKindState
    var pattern: String
    var appliesTo: AIPrivacyRuleAppliesToState
    var enabled: Bool
    var description: String?
}

struct AIPrivacyRuleRecordSnapshot: Equatable {
    var ruleId: String
    var name: String
    var kind: AIPrivacyRuleKindState
    var pattern: String
    var appliesTo: AIPrivacyRuleAppliesToState
    var enabled: Bool
    var description: String?
    var matchCount: Int64
    var lastMatchedAt: Int64?
}

struct AIPrivacyRulesSnapshot: Equatable {
    var privacyGateEnabled: Bool
    var rules: [AIPrivacyRuleRecordSnapshot]
    var remoteAllowedFields: [AIPrivacyFieldStateSnapshot]
    var providerScope: AIPrivacyProviderScopeSnapshot
    var updatedAt: Int64?
    var remoteBlockedByDefault: Bool
}

struct AIPrivacyRulesUpdateRequestSnapshot: Equatable {
    var privacyGateEnabled: Bool
    var rules: [AIPrivacyRuleInputSnapshot]
    var remoteAllowedFields: [AIPrivacyFieldRuleSnapshot]
    var providerScope: AIPrivacyProviderScopeSnapshot
    var confirmed: Bool
}

struct AIPrivacyEvaluationRequestSnapshot: Equatable {
    var feature: AISettingsFeatureKind
    var route: AIPrivacyEvaluationRouteState
    var requestedFields: [AIPrivacyInputFieldState]
    var privacyGateEnabled: Bool
    var providerScope: AIPrivacyProviderScopeSnapshot
    var rules: [AIPrivacyRuleInputSnapshot]
    var remoteAllowedFields: [AIPrivacyFieldRuleSnapshot]
    var context: AIPrivacyEvaluationContextSnapshot
}

extension CoreBridge: CoreAIPrivacyRulesManaging {
    func loadAIPrivacyRules(repoPath: String) async throws -> AIPrivacyRulesSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AIPrivacyRulesSnapshot(listAiPrivacyRules(repoPath: repoPath))
        }.value
    }

    func updateAIPrivacyRules(
        repoPath: String,
        request: AIPrivacyRulesUpdateRequestSnapshot
    ) async throws -> AIPrivacyRulesSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AIPrivacyRulesSnapshot(updateAiPrivacyRules(
                repoPath: repoPath,
                request: request.coreValue
            ))
        }.value
    }
}

extension CoreBridge: CoreAIPrivacyEvaluating {
    func evaluateAIPrivacy(
        repoPath: String,
        request: AIPrivacyEvaluationRequestSnapshot
    ) async throws -> AIPrivacyEvaluationReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AIPrivacyEvaluationReportSnapshot(evaluateAiPrivacy(
                repoPath: repoPath,
                request: request.coreValue
            ))
        }.value
    }
}
