import AreaMatrixFeatureAI
import Foundation

extension AIPrivacyDecisionSnapshot {
    var coreValue: AiPrivacyDecision {
        switch self {
        case .allowed: .allowed
        case .denied: .denied
        case .skipped: .skipped
        }
    }
}

extension AIPrivacySkippedReasonSnapshot {
    var coreValue: AiPrivacySkippedReason {
        switch self {
        case .privacyGateDisabled: .privacyGateDisabled
        case .scopeNotAllowed: .scopeNotAllowed
        case .providerNotConfigured: .providerNotConfigured
        case .providerNotVerified: .providerNotVerified
        case .providerDisabled: .providerDisabled
        case .privacyRule: .privacyRule
        case .fieldRule: .fieldRule
        case .noEligibleInput: .noEligibleInput
        }
    }
}

extension AIPrivacyEvaluationRouteState {
    init(_ route: AiPrivacyEvaluationRoute) {
        switch route {
        case .local: self = .local
        case .remote: self = .remote
        }
    }

    var coreValue: AiPrivacyEvaluationRoute {
        switch self {
        case .local: .local
        case .remote: .remote
        }
    }
}

extension AIPrivacyInputFieldState {
    init(_ field: AiPrivacyInputField) {
        switch field {
        case .fileName: self = .fileName
        case .repoRelativePath: self = .repoRelativePath
        case .extension: self = .extension
        case .extractedTextExcerpt: self = .extractedTextExcerpt
        case .aiSummary: self = .aiSummary
        case .noteSummary: self = .noteSummary
        case .tagCategoryContext: self = .tagCategoryContext
        }
    }

    var coreValue: AiPrivacyInputField {
        switch self {
        case .fileName: .fileName
        case .repoRelativePath: .repoRelativePath
        case .extension: .extension
        case .extractedTextExcerpt: .extractedTextExcerpt
        case .aiSummary: .aiSummary
        case .noteSummary: .noteSummary
        case .tagCategoryContext: .tagCategoryContext
        }
    }
}

extension AIPrivacyProviderGateReasonState {
    init(_ reason: AiPrivacyProviderGateReason) {
        switch reason {
        case .privacyGateDisabled: self = .privacyGateDisabled
        case .scopeNotAllowed: self = .scopeNotAllowed
        case .providerNotConfigured: self = .providerNotConfigured
        case .providerNotVerified: self = .providerNotVerified
        case .providerDisabled: self = .providerDisabled
        }
    }

    var coreValue: AiPrivacyProviderGateReason {
        switch self {
        case .privacyGateDisabled: .privacyGateDisabled
        case .scopeNotAllowed: .scopeNotAllowed
        case .providerNotConfigured: .providerNotConfigured
        case .providerNotVerified: .providerNotVerified
        case .providerDisabled: .providerDisabled
        }
    }
}

extension AIPrivacyRuleAppliesToState {
    init(_ appliesTo: AiPrivacyRuleAppliesTo) {
        switch appliesTo {
        case .remoteAi: self = .remoteAi
        case .localAndRemoteAi: self = .localAndRemoteAi
        }
    }

    var coreValue: AiPrivacyRuleAppliesTo {
        switch self {
        case .remoteAi: .remoteAi
        case .localAndRemoteAi: .localAndRemoteAi
        }
    }
}

extension AIPrivacyRuleKindState {
    init(_ kind: AiPrivacyRuleKind) {
        switch kind {
        case .folder: self = .folder
        case .category: self = .category
        case .keyword: self = .keyword
        case .extension: self = .extension
        case .tag: self = .tag
        }
    }

    var coreValue: AiPrivacyRuleKind {
        switch self {
        case .folder: .folder
        case .category: .category
        case .keyword: .keyword
        case .extension: .extension
        case .tag: .tag
        }
    }
}

extension AIPrivacySkippedReasonState {
    init(_ reason: AiPrivacySkippedReason) {
        switch reason {
        case .privacyGateDisabled: self = .privacyGateDisabled
        case .scopeNotAllowed: self = .scopeNotAllowed
        case .providerNotConfigured: self = .providerNotConfigured
        case .providerNotVerified: self = .providerNotVerified
        case .providerDisabled: self = .providerDisabled
        case .privacyRule: self = .privacyRule
        case .fieldRule: self = .fieldRule
        case .noEligibleInput: self = .noEligibleInput
        }
    }

    var coreValue: AiPrivacySkippedReason {
        switch self {
        case .privacyGateDisabled: .privacyGateDisabled
        case .scopeNotAllowed: .scopeNotAllowed
        case .providerNotConfigured: .providerNotConfigured
        case .providerNotVerified: .providerNotVerified
        case .providerDisabled: .providerDisabled
        case .privacyRule: .privacyRule
        case .fieldRule: .fieldRule
        case .noEligibleInput: .noEligibleInput
        }
    }
}

extension AIPrivacyDecisionState {
    init(_ decision: AiPrivacyDecision) {
        switch decision {
        case .allowed: self = .allowed
        case .denied: self = .denied
        case .skipped: self = .skipped
        }
    }

    var coreValue: AiPrivacyDecision {
        switch self {
        case .allowed: .allowed
        case .denied: .denied
        case .skipped: .skipped
        }
    }
}

extension AIPrivacyEvaluationContextSnapshot {
    init(_ context: AiPrivacyEvaluationContext) {
        self.init(
            fileId: context.fileId,
            repoRelativePath: context.repoRelativePath,
            fileName: context.fileName,
            category: context.category,
            extension: context.extension,
            tags: context.tags
        )
    }

    var coreValue: AiPrivacyEvaluationContext {
        AiPrivacyEvaluationContext(
            fileId: fileId,
            repoRelativePath: repoRelativePath,
            fileName: fileName,
            category: category,
            extension: `extension`,
            tags: tags
        )
    }
}

extension AIPrivacyRuleMatchSnapshot {
    init(_ match: AiPrivacyRuleMatch) {
        self.init(
            ruleId: match.ruleId,
            name: match.name,
            kind: AIPrivacyRuleKindState(match.kind),
            pattern: match.pattern,
            appliesTo: AIPrivacyRuleAppliesToState(match.appliesTo),
            matchedField: match.matchedField.map(AIPrivacyInputFieldState.init)
        )
    }

    var coreValue: AiPrivacyRuleMatch {
        AiPrivacyRuleMatch(
            ruleId: ruleId,
            name: name,
            kind: kind.coreValue,
            pattern: pattern,
            appliesTo: appliesTo.coreValue,
            matchedField: matchedField?.coreValue
        )
    }
}

extension AIPrivacyEvaluationReportSnapshot {
    init(_ report: AiPrivacyEvaluationReport) {
        self.init(
            decision: AIPrivacyDecisionState(report.decision),
            skippedReason: report.skippedReason.map(AIPrivacySkippedReasonState.init),
            providerGateReason: report.providerGateReason.map(AIPrivacyProviderGateReasonState.init),
            matchedRules: report.matchedRules.map(AIPrivacyRuleMatchSnapshot.init),
            matchedFieldType: report.matchedFieldType.map(AIPrivacyInputFieldState.init),
            allowedFields: report.allowedFields.map(AIPrivacyInputFieldState.init),
            blockedFields: report.blockedFields.map(AIPrivacyInputFieldState.init),
            sentFields: report.sentFields.map(AIPrivacyInputFieldState.init),
            message: report.message
        )
    }

    var coreValue: AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: decision.coreValue,
            skippedReason: skippedReason?.coreValue,
            providerGateReason: providerGateReason?.coreValue,
            matchedRules: matchedRules.map(\.coreValue),
            matchedFieldType: matchedFieldType?.coreValue,
            allowedFields: allowedFields.map(\.coreValue),
            blockedFields: blockedFields.map(\.coreValue),
            sentFields: sentFields.map(\.coreValue),
            message: message
        )
    }
}

extension AIPrivacyFieldRuleSnapshot {
    init(_ rule: AiPrivacyFieldRule) {
        self.init(field: AIPrivacyInputFieldState(rule.field), allowRemote: rule.allowRemote)
    }

    var coreValue: AiPrivacyFieldRule {
        AiPrivacyFieldRule(field: field.coreValue, allowRemote: allowRemote)
    }
}

extension AIPrivacyFieldStateSnapshot {
    init(_ state: AiPrivacyFieldState) {
        self.init(
            field: AIPrivacyInputFieldState(state.field),
            allowRemote: state.allowRemote,
            lastMatchedCount: state.lastMatchedCount
        )
    }
}

extension AIPrivacyProviderScopeSnapshot {
    init(_ scope: AiPrivacyProviderScopeSnapshot) {
        self.init(
            providerConfigured: scope.providerConfigured,
            providerVerified: scope.providerVerified,
            remoteProviderEnabled: scope.remoteProviderEnabled,
            featureScope: scope.featureScope.map(AISettingsFeatureKind.init(coreFeature:))
        )
    }

    var coreValue: AiPrivacyProviderScopeSnapshot {
        AiPrivacyProviderScopeSnapshot(
            providerConfigured: providerConfigured,
            providerVerified: providerVerified,
            remoteProviderEnabled: remoteProviderEnabled,
            featureScope: featureScope.map(AiFeatureKind.init(snapshotFeature:))
        )
    }
}

extension AIPrivacyRuleInputSnapshot {
    init(_ input: AiPrivacyRuleInput) {
        self.init(
            ruleId: input.ruleId,
            name: input.name,
            kind: AIPrivacyRuleKindState(input.kind),
            pattern: input.pattern,
            appliesTo: AIPrivacyRuleAppliesToState(input.appliesTo),
            enabled: input.enabled,
            description: input.description
        )
    }

    var coreValue: AiPrivacyRuleInput {
        AiPrivacyRuleInput(
            ruleId: ruleId,
            name: name,
            kind: kind.coreValue,
            pattern: pattern,
            appliesTo: appliesTo.coreValue,
            enabled: enabled,
            description: description
        )
    }
}

extension AIPrivacyRuleRecordSnapshot {
    init(_ record: AiPrivacyRuleRecord) {
        self.init(
            ruleId: record.ruleId,
            name: record.name,
            kind: AIPrivacyRuleKindState(record.kind),
            pattern: record.pattern,
            appliesTo: AIPrivacyRuleAppliesToState(record.appliesTo),
            enabled: record.enabled,
            description: record.description,
            matchCount: record.matchCount,
            lastMatchedAt: record.lastMatchedAt
        )
    }

    var coreValue: AiPrivacyRuleRecord {
        AiPrivacyRuleRecord(
            ruleId: ruleId,
            name: name,
            kind: kind.coreValue,
            pattern: pattern,
            appliesTo: appliesTo.coreValue,
            enabled: enabled,
            description: description,
            matchCount: matchCount,
            lastMatchedAt: lastMatchedAt
        )
    }
}

extension AIPrivacyRulesSnapshot {
    init(_ snapshot: AiPrivacyRulesSnapshot) {
        self.init(
            privacyGateEnabled: snapshot.privacyGateEnabled,
            rules: snapshot.rules.map(AIPrivacyRuleRecordSnapshot.init),
            remoteAllowedFields: snapshot.remoteAllowedFields.map(AIPrivacyFieldStateSnapshot.init),
            providerScope: AIPrivacyProviderScopeSnapshot(snapshot.providerScope),
            updatedAt: snapshot.updatedAt,
            remoteBlockedByDefault: snapshot.remoteBlockedByDefault
        )
    }

    var coreValue: AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: privacyGateEnabled,
            rules: rules.map(\.coreValue),
            remoteAllowedFields: remoteAllowedFields.map { field in
                AiPrivacyFieldState(
                    field: field.field.coreValue,
                    allowRemote: field.allowRemote,
                    lastMatchedCount: field.lastMatchedCount
                )
            },
            providerScope: providerScope.coreValue,
            updatedAt: updatedAt,
            remoteBlockedByDefault: remoteBlockedByDefault
        )
    }
}

extension AIPrivacyRulesUpdateRequestSnapshot {
    var coreValue: AiPrivacyRulesUpdateRequest {
        AiPrivacyRulesUpdateRequest(
            privacyGateEnabled: privacyGateEnabled,
            rules: rules.map(\.coreValue),
            remoteAllowedFields: remoteAllowedFields.map(\.coreValue),
            providerScope: providerScope.coreValue,
            confirmed: confirmed
        )
    }
}

extension AIPrivacyEvaluationRequestSnapshot {
    var coreValue: AiPrivacyEvaluationRequest {
        AiPrivacyEvaluationRequest(
            feature: AiFeatureKind(snapshotFeature: feature),
            route: route.coreValue,
            requestedFields: requestedFields.map(\.coreValue),
            privacyGateEnabled: privacyGateEnabled,
            providerScope: providerScope.coreValue,
            rules: rules.map(\.coreValue),
            remoteAllowedFields: remoteAllowedFields.map(\.coreValue),
            context: context.coreValue
        )
    }
}
