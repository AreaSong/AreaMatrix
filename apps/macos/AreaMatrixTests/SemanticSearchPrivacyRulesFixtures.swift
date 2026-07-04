@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static var semanticSearchPrivacyFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "Semantic privacy rules could not be checked.",
            severity: .high,
            suggestedAction: "Retry privacy check.",
            recoverability: .retryable,
            rawContext: "semantic-search ai-privacy-rules-core"
        )
    }
}

extension SearchQueryRequestSnapshot {
    static func semanticSearchSemanticPrivacyFixture() -> SearchQueryRequestSnapshot {
        var filters = SearchFilterStateSnapshot.empty
        filters.category = "finance"
        filters.fileKind = ".pdf"
        filters.tags = [" confidential ", ""]
        return SearchQueryRequestSnapshot(
            query: "客户合同",
            scope: .current,
            currentPath: "finance/invoices",
            category: nil,
            filters: filters,
            sort: .relevance,
            limit: 50,
            offset: 0,
            mode: .semantic
        )
    }
}

extension SearchResultPageSnapshot {
    static func semanticSearchSemanticPrivacyPage(route: SemanticSearchRouteSnapshot) -> SearchResultPageSnapshot {
        let semanticPage = SemanticSearchResultPageSnapshot(
            query: "客户合同",
            semanticTotalCount: 0,
            normalTotalCount: 0,
            semanticMatches: [],
            normalMatches: [],
            dedupedNormalCount: 0,
            indexStatus: .notReady,
            route: route,
            fallbackReason: .semanticIndexNotReady,
            fallbackMessage: nil,
            callLogID: nil,
            privacyRuleID: nil,
            lowConfidence: false
        )
        return SearchResultPageSnapshot(
            query: "客户合同",
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .unavailable,
            semanticPage: semanticPage
        )
    }
}

extension AiPrivacyRulesSnapshot {
    static func semanticSearchPrivacyRules() -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: true,
            rules: [],
            remoteAllowedFields: [
                AiPrivacyFieldState(field: .fileName, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .repoRelativePath, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .extension, allowRemote: true, lastMatchedCount: 0)
            ],
            providerScope: AiPrivacyProviderScopeSnapshot(
                providerConfigured: true,
                providerVerified: true,
                remoteProviderEnabled: true,
                featureScope: [.semanticSearch]
            ),
            updatedAt: 1_700_000_300,
            remoteBlockedByDefault: true
        )
    }
}

extension AiPrivacyEvaluationReport {
    static func semanticSearchAllowed() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .allowed,
            skippedReason: nil,
            providerGateReason: nil,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [.fileName, .repoRelativePath, .extension],
            blockedFields: [.extractedTextExcerpt],
            sentFields: [.fileName, .repoRelativePath],
            message: "Privacy rules allow semantic index metadata."
        )
    }

    static func semanticSearchBlocked() -> AiPrivacyEvaluationReport {
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
            message: "A privacy rule blocked semantic index input."
        )
    }
}
