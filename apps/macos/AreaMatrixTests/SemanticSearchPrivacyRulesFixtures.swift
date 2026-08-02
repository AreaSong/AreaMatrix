@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static var semanticSearchPrivacyFailure: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
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
        return .testFixture(
            query: "客户合同",
            scope: .current,
            currentPath: "finance/invoices",
            category: nil,
            filters: filters,
            mode: .semantic
        )
    }
}

extension SearchResultPageSnapshot {
    static func semanticSearchSemanticPrivacyPage(route: SemanticSearchRouteSnapshot) -> SearchResultPageSnapshot {
        let semanticPage = SemanticSearchResultPageSnapshot.testFixture(
            query: "客户合同",
            semanticTotalCount: 0,
            normalTotalCount: 0,
            indexStatus: .notReady,
            route: route,
            fallbackReason: .semanticIndexNotReady,
            callLogID: nil,
            lowConfidence: false
        )
        return .testFixture(
            query: "客户合同",
            totalCount: 0,
            indexStatus: .unavailable,
            semanticPage: semanticPage
        )
    }
}

extension AIPrivacyRulesSnapshot {
    static func semanticSearchPrivacyRules() -> AIPrivacyRulesSnapshot {
        testFixture(
            remoteAllowedFields: [
                .testFixture(field: .fileName),
                .testFixture(field: .repoRelativePath),
                .testFixture(field: .extension)
            ],
            providerScope: .testFixture(
                featureScope: [.semanticSearch]
            ),
            updatedAt: 1_700_000_300
        )
    }
}

extension AIPrivacyEvaluationReportSnapshot {
    static func semanticSearchAllowed() -> AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
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

    static func semanticSearchBlocked() -> AIPrivacyEvaluationReportSnapshot {
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
            message: "A privacy rule blocked semantic index input."
        )
    }
}
