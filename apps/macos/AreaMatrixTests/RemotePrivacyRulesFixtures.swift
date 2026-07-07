@testable import AreaMatrix

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

    static func remoteProviderConfigAIPrivacyFinanceFolderBlocked() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AiPrivacyRuleMatch(
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

extension AiPrivacyProviderScopeSnapshot {
    static func testFixture(
        providerConfigured: Bool = true,
        providerVerified: Bool = true,
        remoteProviderEnabled: Bool = true,
        featureScope: [AiFeatureKind] = [.autoSummaries]
    ) -> AiPrivacyProviderScopeSnapshot {
        AiPrivacyProviderScopeSnapshot(
            providerConfigured: providerConfigured,
            providerVerified: providerVerified,
            remoteProviderEnabled: remoteProviderEnabled,
            featureScope: featureScope
        )
    }
}

extension AiPrivacyRulesSnapshot {
    static func testFixture(
        privacyGateEnabled: Bool = true,
        rules: [AiPrivacyRuleRecord] = [],
        remoteAllowedFields: [AiPrivacyFieldState] = [],
        providerScope: AiPrivacyProviderScopeSnapshot = .testFixture(),
        updatedAt: Int64? = nil,
        remoteBlockedByDefault: Bool = true
    ) -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
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
        featureScope: [AiFeatureKind] = [.autoSummaries]
    ) -> AiPrivacyRulesSnapshot {
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

    static func remoteProviderConfigAIPrivacyRules(privacyGateEnabled: Bool) -> AiPrivacyRulesSnapshot {
        testFixture(
            privacyGateEnabled: privacyGateEnabled,
            rules: [
                AiPrivacyRuleRecord(
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

    func applyingPrivacyGateRequest(_ request: AiPrivacyRulesUpdateRequest) -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot.testFixture(
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
    static func testFixture(
        field: AiPrivacyInputField,
        allowRemote: Bool = true,
        lastMatchedCount: Int64 = 0
    ) -> AiPrivacyFieldState {
        AiPrivacyFieldState(
            field: field,
            allowRemote: allowRemote,
            lastMatchedCount: lastMatchedCount
        )
    }

    init(rule: AiPrivacyFieldRule) {
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
