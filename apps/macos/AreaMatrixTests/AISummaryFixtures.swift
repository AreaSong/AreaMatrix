@testable import AreaMatrix

extension AISummarySavedSnapshot {
    static func aiSummarySavedSummary(
        fileID: Int64,
        text: String,
        ownership: AiContentOwnership = .generated
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

extension AiPrivacyEvaluationReport {
    static func aiSummaryAllowed() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
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

    static func aiSummaryDeniedPrivacyRule() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AiPrivacyRuleMatch(
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

extension AiSummaryDraft {
    static func aiSummaryIntegrationDraft(
        fileID: Int64,
        text: String,
        draftID: String,
        callLogID: Int64
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            operationId: "operation-\(fileID)-\(draftID)",
            contentLocale: .en,
            formatContractVersion: 1,
            fileId: fileID,
            draftId: draftID,
            status: .draft,
            summaryText: text,
            route: .remote,
            modelName: "Remote summary provider",
            generatedAt: 1_700_000_000,
            usedContext: [.fileName, .extractedTextExcerpt],
            skippedReason: nil,
            privacyRuleId: nil,
            callLogId: callLogID,
            requiresUserSave: true,
            characterCount: Int64(text.count)
        )
    }

    static func aiSummaryIntegrationUnavailableDraft(
        fileID: Int64,
        reason: AiSummarySkipReason
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            operationId: "operation-\(fileID)-unavailable",
            contentLocale: .en,
            formatContractVersion: 1,
            fileId: fileID,
            draftId: nil,
            status: .unavailable,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: reason,
            privacyRuleId: nil,
            callLogId: nil,
            requiresUserSave: false,
            characterCount: 0
        )
    }

    static func aiSummaryIntegrationPrivacySkippedDraft(
        fileID: Int64,
        privacyRuleID: String,
        callLogID: Int64
    ) -> AiSummaryDraft {
        AiSummaryDraft(
            operationId: "operation-\(fileID)-privacy",
            contentLocale: .en,
            formatContractVersion: 1,
            fileId: fileID,
            draftId: nil,
            status: .skipped,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: .privacyRule,
            privacyRuleId: privacyRuleID,
            callLogId: callLogID,
            requiresUserSave: false,
            characterCount: 0
        )
    }
}
