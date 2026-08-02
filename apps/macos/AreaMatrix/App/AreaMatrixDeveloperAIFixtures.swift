import Foundation

#if DEBUG
enum DeveloperAIScenarioFixture {
    static let repoPath = AreaMatrixPreviewFixtures.repositoryPath
    static let fileID: Int64 = 910

    static var file: FileEntrySnapshot {
        FileEntrySnapshot(
            id: fileID,
            path: "inbox/invoice-q2.pdf",
            originalName: "invoice-q2.pdf",
            currentName: "invoice-q2.pdf",
            category: "inbox",
            sizeBytes: 48312,
            hashSha256: "developer-ai-file-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_778_738_400,
            updatedAt: 1_778_738_400
        )
    }

    static var settings: AISettingsSnapshot {
        let toggles = AISettingsFeatureKind.allCases.map {
            AISettingsFeatureConfigSnapshot(feature: $0, enabled: true, allowRemote: true)
        }
        let config = AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: true,
            providerPreference: .localFirst,
            localAIEnabled: true,
            remoteAIAllowed: true,
            privacyGateEnabled: true,
            privacyPolicyRef: "developer-policy",
            featureToggles: toggles
        )
        return AISettingsSnapshot(
            config: config,
            capabilities: AISettingsCapabilitySnapshot.derived(from: config),
            updatedAt: 1_778_738_400
        )
    }

    static var remoteProvider: RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: .openAi,
            modelID: "gpt-4.1-mini",
            endpointURL: nil,
            credentialConfigured: true,
            featureScope: [.autoSummaries, .semanticSearch],
            updatedAt: 1_778_738_400,
            disabledReason: nil
        )
    }

    static var privacyRules: AIPrivacyRulesSnapshot {
        AIPrivacyRulesSnapshot(
            privacyGateEnabled: true,
            rules: [
                AIPrivacyRuleRecordSnapshot(
                    ruleId: "rule-confidential",
                    name: "Confidential material",
                    kind: .keyword,
                    pattern: "confidential",
                    appliesTo: .remoteAi,
                    enabled: true,
                    description: L10n.resolve(L10n.verbatim(
                        "Blocks confidential material from remote AI.",
                        reason: .userContent
                    )),
                    matchCount: 4,
                    lastMatchedAt: 1_778_738_300
                )
            ],
            remoteAllowedFields: [
                AIPrivacyFieldStateSnapshot(field: .fileName, allowRemote: true, lastMatchedCount: 2),
                AIPrivacyFieldStateSnapshot(field: .repoRelativePath, allowRemote: true, lastMatchedCount: 1),
                AIPrivacyFieldStateSnapshot(field: .extractedTextExcerpt, allowRemote: false, lastMatchedCount: 3)
            ],
            providerScope: AIPrivacyProviderScopeSnapshot(
                providerConfigured: true,
                providerVerified: true,
                remoteProviderEnabled: true,
                featureScope: [.autoSummaries, .semanticSearch]
            ),
            updatedAt: 1_778_738_400,
            remoteBlockedByDefault: true
        )
    }

    static var privacyAllowed: AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
            decision: .allowed,
            skippedReason: nil,
            providerGateReason: nil,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [.fileName, .repoRelativePath],
            blockedFields: [.extractedTextExcerpt],
            sentFields: [.fileName, .repoRelativePath],
            message: L10n.resolve(L10n.verbatim(
                "Developer scenario privacy evaluation allowed metadata only.",
                reason: .technicalDetail
            ))
        )
    }

    static var callLogPage: AICallLogPageSnapshot {
        AICallLogPageSnapshot(
            totalCount: 2,
            records: [
                callLogRecord(
                    id: 920,
                    feature: .summary,
                    route: .local,
                    status: .success,
                    result: "Generated a local summary"
                ),
                callLogRecord(
                    id: 921,
                    feature: .semanticSearch,
                    route: .remote,
                    status: .skipped,
                    result: "Blocked before remote transmission"
                )
            ],
            limit: 100,
            offset: 0,
            hasMore: false,
            retentionDays: 90,
            redactionPolicy: "Secrets, prompts, outputs, notes, and file contents are redacted."
        )
    }

    static var categorySuggestion: AIClassificationSuggestionState {
        AIClassificationSuggestionState(
            fileID: fileID,
            status: .suggested,
            currentCategory: "inbox",
            suggestedCategory: "finance",
            confidence: 0.91,
            reason: "Filename and metadata match invoice records.",
            route: .local,
            usedContext: [.fileName, .extension, .repoRelativePath],
            skippedReason: nil,
            privacyRuleID: nil,
            callLogID: nil,
            requiresUserConfirmation: true
        )
    }

    static var localModelStatus: LocalModelStatusState {
        LocalModelStatusState(
            modelID: LocalModelStatusModel.defaultModelID,
            storageLocation: "/Users/example/Library/Application Support/AreaMatrix/Models",
            availability: .ready,
            version: "1.0.0",
            sizeBytes: 268_435_456,
            lastError: nil,
            recommendedAction: .openModelLocation,
            lastCheckedAt: 1_778_738_400,
            diagnosticsSummary: "manifest: valid; runtime: ready; network: unused",
            featureStatuses: AISettingsFeatureKind.allCases.map {
                LocalModelFeatureStatusState(feature: $0, available: true, unavailableReason: nil)
            }
        )
    }

    static var savedSummary: AISummarySavedSnapshot {
        let summary = "Quarterly invoice summary generated locally for review."
        return AISummarySavedSnapshot(
            fileID: fileID,
            summaryText: summary,
            savedAt: 1_778_738_400,
            draftID: "developer-summary-draft",
            route: .local,
            modelName: "AreaMatrix Local",
            generatedAt: 1_778_738_300,
            usedContext: [.fileName, .repoRelativePath],
            privacyRuleID: nil,
            callLogID: nil,
            editedByUser: false,
            contentRevision: 3,
            ownership: .generated,
            operationID: "developer-summary-operation",
            contentLocale: .en,
            formatContractVersion: 1,
            characterCount: Int64(summary.count)
        )
    }

    static var tagReport: AITagSuggestionReportSnapshot {
        AITagSuggestionReportSnapshot(
            fileId: fileID,
            status: .suggested,
            suggestions: [
                tagSuggestion(id: "finance", confidence: 0.94),
                tagSuggestion(id: "quarterly", confidence: 0.87),
                tagSuggestion(id: "review", confidence: 0.72, selected: false)
            ],
            route: .local,
            modelName: "AreaMatrix Local",
            generatedAt: 1_778_738_400,
            usedContext: [.fileName, .tagRegistry],
            skippedReason: nil,
            privacyRuleId: nil,
            callLogId: nil,
            requiresUserConfirmation: true,
            confidenceThreshold: 0.8,
            contentsRead: false,
            aiUsed: true,
            networkUsed: false
        )
    }

    static var existingTags: [TagRecordSnapshot] {
        [
            TagRecordSnapshot(
                value: "invoice",
                label: L10n.resolve(L10n.verbatim("Invoice", reason: .userContent)),
                fileCount: 8,
                selected: true,
                disabled: false,
                updatedAt: 1_778_738_400
            )
        ]
    }

    private static func callLogRecord(
        id: Int64,
        feature: AICallLogFeatureSnapshot,
        route: AICallLogRouteSnapshot,
        status: AICallLogStatusSnapshot,
        result: String
    ) -> AICallLogRecordSnapshot {
        AICallLogRecordSnapshot(
            id: id,
            occurredAt: 1_778_738_400 - id,
            feature: feature,
            fileId: fileID,
            fileDisplayName: "invoice-q2.pdf",
            batchId: nil,
            scope: "single file",
            route: route,
            providerName: route == .local ? "AreaMatrix Local" : "Remote provider",
            modelName: route == .local ? "local-model" : "remote-model",
            status: status,
            durationMs: 84,
            sentFields: route == .local ? [.fileName] : [],
            privacyRulesChecked: true,
            privacyRuleId: status == .skipped ? "rule-confidential" : nil,
            privacyRuleName: status == .skipped ? "Confidential material" : nil,
            matchedFieldType: status == .skipped ? .fileName : nil,
            resultSummary: result,
            errorCode: nil
        )
    }

    private static func tagSuggestion(id: String, confidence: Float, selected: Bool = true) -> AITagSuggestionSnapshot {
        AITagSuggestionSnapshot(
            suggestionId: "developer-tag-\(id)",
            slug: id,
            displayName: id.capitalized,
            confidence: confidence,
            reason: "Local metadata pattern",
            status: .suggested,
            mergeAction: .createTag,
            matchedExistingSlug: nil,
            selectedByDefault: selected,
            disabledReason: nil
        )
    }
}

#endif
