@testable import AreaMatrix

extension AISummarySavedSnapshot {
    static func aiSummarySavedSummary(
        fileID: Int64,
        text: String,
        ownership: AIContentOwnershipState = .generated
    ) -> AISummarySavedSnapshot {
        AISummarySavedSnapshot(
            fileID: fileID,
            summaryText: text,
            savedAt: 1_700_000_300,
            draftID: "saved-draft-\(fileID)",
            route: .remote,
            modelName: "Remote summary provider",
            generatedAt: 1_700_000_000,
            usedContext: [.fileName, .extractedTextExcerpt],
            privacyRuleID: nil,
            callLogID: 8000 + fileID,
            editedByUser: ownership == .userOwned,
            contentRevision: 1,
            ownership: ownership,
            operationID: "saved-operation-\(fileID)",
            contentLocale: .en,
            formatContractVersion: 1,
            characterCount: Int64(text.count)
        )
    }
}

extension AIPrivacyEvaluationReportSnapshot {
    static func aiSummaryAllowed() -> AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
            decision: .allowed,
            skippedReason: nil,
            providerGateReason: nil,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            blockedFields: [],
            sentFields: [.fileName, .repoRelativePath],
            message: "Remote summary metadata allowed."
        )
    }

    static func aiSummaryDeniedPrivacyRule() -> AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AIPrivacyRuleMatchSnapshot(
                    ruleId: "rule-confidential",
                    name: "Confidential",
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
            message: "A privacy rule blocked the summary input."
        )
    }
}

extension AISummaryDraftSnapshot {
    static func aiSummaryIntegrationDraft(
        fileID: Int64,
        text: String,
        draftID: String,
        callLogID: Int64
    ) -> AISummaryDraftSnapshot {
        AISummaryDraftSnapshot(
            operationID: "operation-\(fileID)-\(draftID)",
            contentLocale: .en,
            formatContractVersion: 1,
            fileID: fileID,
            draftID: draftID,
            status: .draft,
            summaryText: text,
            route: .remote,
            modelName: "Remote summary provider",
            generatedAt: 1_700_000_000,
            usedContext: [.fileName, .extractedTextExcerpt],
            skippedReason: nil,
            privacyRuleID: nil,
            callLogID: callLogID,
            requiresUserSave: true,
            characterCount: Int64(text.count)
        )
    }

    static func aiSummaryIntegrationUnavailableDraft(
        fileID: Int64,
        reason: AISummarySkipReasonState
    ) -> AISummaryDraftSnapshot {
        AISummaryDraftSnapshot(
            operationID: "operation-\(fileID)-unavailable",
            contentLocale: .en,
            formatContractVersion: 1,
            fileID: fileID,
            draftID: nil,
            status: .unavailable,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: reason,
            privacyRuleID: nil,
            callLogID: nil,
            requiresUserSave: false,
            characterCount: 0
        )
    }

    static func aiSummaryIntegrationPrivacySkippedDraft(
        fileID: Int64,
        privacyRuleID: String,
        callLogID: Int64
    ) -> AISummaryDraftSnapshot {
        AISummaryDraftSnapshot(
            operationID: "operation-\(fileID)-privacy",
            contentLocale: .en,
            formatContractVersion: 1,
            fileID: fileID,
            draftID: nil,
            status: .skipped,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: .privacyRule,
            privacyRuleID: privacyRuleID,
            callLogID: callLogID,
            requiresUserSave: false,
            characterCount: 0
        )
    }
}
