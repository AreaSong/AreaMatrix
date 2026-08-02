@testable import AreaMatrix

extension AIPrivacyEvaluationReportSnapshot {
    static func remoteProviderConfigAllowedPrivacyEvaluation() -> AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
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

    static func remoteProviderConfigAIPrivacyFinanceFolderBlocked() -> AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AIPrivacyRuleMatchSnapshot(
                    ruleId: "rule-finance-folder",
                    name: "Private finance folders",
                    kind: .folder,
                    pattern: "finance/private/",
                    appliesTo: .remoteAi,
                    matchedField: .repoRelativePath
                )
            ],
            matchedFieldType: .repoRelativePath,
            allowedFields: [],
            blockedFields: [.fileName, .repoRelativePath, .extension],
            sentFields: [],
            message: "Matched by Folder: finance/private/"
        )
    }

    static func aiTagSuggestionPrivacyRuleBlocked() -> AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AIPrivacyRuleMatchSnapshot(
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

extension AIPrivacyProviderScopeSnapshot {
    static func testFixture(
        providerConfigured: Bool = true,
        providerVerified: Bool = true,
        remoteProviderEnabled: Bool = true,
        featureScope: [AISettingsFeatureKind] = [.autoSummaries]
    ) -> AIPrivacyProviderScopeSnapshot {
        AIPrivacyProviderScopeSnapshot(
            providerConfigured: providerConfigured,
            providerVerified: providerVerified,
            remoteProviderEnabled: remoteProviderEnabled,
            featureScope: featureScope
        )
    }
}

extension AIPrivacyRulesSnapshot {
    static func testFixture(
        privacyGateEnabled: Bool = true,
        rules: [AIPrivacyRuleRecordSnapshot] = [],
        remoteAllowedFields: [AIPrivacyFieldStateSnapshot] = [],
        providerScope: AIPrivacyProviderScopeSnapshot = .testFixture(),
        updatedAt: Int64? = nil,
        remoteBlockedByDefault: Bool = true
    ) -> AIPrivacyRulesSnapshot {
        AIPrivacyRulesSnapshot(
            privacyGateEnabled: privacyGateEnabled,
            rules: rules,
            remoteAllowedFields: remoteAllowedFields,
            providerScope: providerScope,
            updatedAt: updatedAt,
            remoteBlockedByDefault: remoteBlockedByDefault
        )
    }

    static func remoteProviderConfigPrivacyRules(
        privacyGateEnabled: Bool = false,
        featureScope: [AISettingsFeatureKind] = [.autoSummaries]
    ) -> AIPrivacyRulesSnapshot {
        testFixture(
            privacyGateEnabled: privacyGateEnabled,
            rules: [.remoteProviderConfigRuleRecord()],
            remoteAllowedFields: [
                .testFixture(field: .fileName),
                .testFixture(field: .extractedTextExcerpt, allowRemote: false, lastMatchedCount: 2),
                .testFixture(field: .noteSummary)
            ],
            providerScope: .testFixture(
                remoteProviderEnabled: false,
                featureScope: featureScope
            ),
            updatedAt: 901
        )
    }

    static func remoteProviderConfigAIPrivacyRules(privacyGateEnabled: Bool) -> AIPrivacyRulesSnapshot {
        testFixture(
            privacyGateEnabled: privacyGateEnabled,
            rules: [
                AIPrivacyRuleRecordSnapshot(
                    ruleId: "rule-finance-folder",
                    name: "Private finance folders",
                    kind: .folder,
                    pattern: "finance/private/",
                    appliesTo: .remoteAi,
                    enabled: true,
                    description: "Blocks finance folders from remote AI.",
                    matchCount: 42,
                    lastMatchedAt: 309
                )
            ],
            remoteAllowedFields: [
                .testFixture(field: .fileName),
                .testFixture(field: .repoRelativePath, lastMatchedCount: 1),
                .testFixture(field: .extension)
            ],
            providerScope: .testFixture(
                featureScope: [.autoSummaries]
            ),
            updatedAt: 309
        )
    }

    func applyingPrivacyGateRequest(_ request: AIPrivacyRulesUpdateRequestSnapshot) -> AIPrivacyRulesSnapshot {
        AIPrivacyRulesSnapshot.testFixture(
            privacyGateEnabled: request.privacyGateEnabled,
            rules: request.rules.map(AIPrivacyRuleRecordSnapshot.init(input:)),
            remoteAllowedFields: request.remoteAllowedFields.map(AIPrivacyFieldStateSnapshot.init(rule:)),
            providerScope: request.providerScope,
            updatedAt: 902,
            remoteBlockedByDefault: remoteBlockedByDefault
        )
    }
}

extension AIPrivacyRuleRecordSnapshot {
    static func remoteProviderConfigRuleRecord() -> AIPrivacyRuleRecordSnapshot {
        AIPrivacyRuleRecordSnapshot(
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

    init(input: AIPrivacyRuleInputSnapshot) {
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

extension AIPrivacyFieldStateSnapshot {
    static func testFixture(
        field: AIPrivacyInputFieldState,
        allowRemote: Bool = true,
        lastMatchedCount: Int64 = 0
    ) -> AIPrivacyFieldStateSnapshot {
        AIPrivacyFieldStateSnapshot(
            field: field,
            allowRemote: allowRemote,
            lastMatchedCount: lastMatchedCount
        )
    }

    init(rule: AIPrivacyFieldRuleSnapshot) {
        self.init(field: rule.field, allowRemote: rule.allowRemote, lastMatchedCount: 0)
    }
}

extension AIPrivacyRuleRegistrySnapshot {
    static func testFixture(
        categories: [String] = [],
        tags: [String] = []
    ) -> AIPrivacyRuleRegistrySnapshot {
        AIPrivacyRuleRegistrySnapshot(categories: categories, tags: tags)
    }
}
