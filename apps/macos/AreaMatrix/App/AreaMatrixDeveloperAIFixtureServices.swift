import Foundation

#if DEBUG
actor DeveloperAISettingsStore: CoreAISettingsLoading, CoreAISettingsUpdating {
    private var snapshot = DeveloperAIScenarioFixture.settings

    func loadAISettings(repoPath _: String) async throws -> AISettingsSnapshot {
        snapshot
    }

    func updateAISettings(repoPath _: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        snapshot = AISettingsSnapshot(
            config: newConfig,
            capabilities: AISettingsCapabilitySnapshot.derived(from: newConfig),
            updatedAt: 1_778_738_401
        )
        return snapshot
    }
}

actor DeveloperRemoteProviderFixture: CoreRemoteProviderConfiguring {
    private var snapshot = DeveloperAIScenarioFixture.remoteProvider

    func loadRemoteProviderConfig(repoPath _: String) async throws -> RemoteProviderConfigState {
        snapshot
    }

    func testRemoteProvider(
        repoPath _: String,
        request: RemoteProviderTestRequestState
    ) async throws -> RemoteProviderTestResultState {
        RemoteProviderTestResultState(
            provider: request.provider,
            modelID: request.modelID,
            endpointURL: request.endpointURL,
            status: .succeeded,
            providerVerified: true,
            verificationToken: "developer-verified",
            sanitizedMessage: "Connection verified by the in-memory developer fixture."
        )
    }

    func enableRemoteProvider(
        repoPath _: String,
        request: RemoteProviderEnableRequestState
    ) async throws -> RemoteProviderConfigState {
        snapshot = RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: request.provider,
            modelID: request.modelID,
            endpointURL: request.endpointURL,
            credentialConfigured: true,
            featureScope: request.featureScope,
            updatedAt: 1_778_738_402,
            disabledReason: nil
        )
        return snapshot
    }

    func disableRemoteProvider(
        repoPath _: String,
        request: RemoteProviderDisableRequestState
    ) async throws -> RemoteProviderConfigState {
        snapshot.remoteProviderEnabled = false
        if request.removeStoredCredential {
            snapshot.providerConfigured = false
            snapshot.providerVerified = false
            snapshot.credentialConfigured = false
            snapshot.featureScope = []
        }
        return snapshot
    }
}

actor DeveloperAIPrivacyFixture: CoreAIPrivacyRulesManaging, CoreAIPrivacyEvaluating {
    private var snapshot = DeveloperAIScenarioFixture.privacyRules

    func loadAIPrivacyRules(repoPath _: String) async throws -> AIPrivacyRulesSnapshot {
        snapshot
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request: AIPrivacyRulesUpdateRequestSnapshot
    ) async throws -> AIPrivacyRulesSnapshot {
        snapshot = AIPrivacyRulesSnapshot(
            privacyGateEnabled: request.privacyGateEnabled,
            rules: request.rules.enumerated().map { index, rule in
                AIPrivacyRuleRecordSnapshot(
                    ruleId: rule.ruleId ?? "developer-rule-\(index)",
                    name: rule.name,
                    kind: rule.kind,
                    pattern: rule.pattern,
                    appliesTo: rule.appliesTo,
                    enabled: rule.enabled,
                    description: rule.description,
                    matchCount: 0,
                    lastMatchedAt: nil
                )
            },
            remoteAllowedFields: request.remoteAllowedFields.map {
                AIPrivacyFieldStateSnapshot(field: $0.field, allowRemote: $0.allowRemote, lastMatchedCount: 0)
            },
            providerScope: request.providerScope,
            updatedAt: 1_778_738_403,
            remoteBlockedByDefault: true
        )
        return snapshot
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request _: AIPrivacyEvaluationRequestSnapshot
    ) async throws -> AIPrivacyEvaluationReportSnapshot {
        DeveloperAIScenarioFixture.privacyAllowed
    }
}

struct DeveloperAIPrivacyRegistryReader: AIPrivacyRuleRegistryReading {
    func loadRegistry(repoPath _: String) async throws -> AIPrivacyRuleRegistrySnapshot {
        AIPrivacyRuleRegistrySnapshot(
            categories: ["docs", "finance", "inbox"],
            tags: ["invoice", "quarterly", "review"]
        )
    }
}

actor DeveloperAICallLogFixture: CoreAICallLogListing, CoreAICallLogClearing {
    private var records = DeveloperAIScenarioFixture.callLogPage.records

    func listAICalls(
        repoPath _: String,
        filter _: AICallLogFilterSnapshot,
        pagination: AICallLogPaginationSnapshot
    ) async throws -> AICallLogPageSnapshot {
        AICallLogPageSnapshot(
            totalCount: Int64(records.count),
            records: records,
            limit: pagination.limit,
            offset: pagination.offset,
            hasMore: false,
            retentionDays: 90,
            redactionPolicy: DeveloperAIScenarioFixture.callLogPage.redactionPolicy
        )
    }

    func clearAICallLog(
        repoPath _: String,
        request: AICallLogClearRequestSnapshot
    ) async throws -> AICallLogClearReportSnapshot {
        let before = records.count
        switch request.scope {
        case .all:
            records = []
        case .selectedEntries:
            records.removeAll { request.entryIds.contains($0.id) }
        case .olderThan:
            if let threshold = request.olderThan {
                records.removeAll { $0.occurredAt < threshold }
            }
        }
        return AICallLogClearReportSnapshot(
            deletedCount: Int64(before - records.count),
            remainingCount: Int64(records.count),
            clearedAt: 1_778_738_404
        )
    }
}

actor DeveloperAIClassificationFixture: CoreAIClassificationSuggesting,
    CoreAIClassificationFallbackStatusReading {
    func suggestCategoryWithAI(
        repoPath _: String,
        request _: AIClassificationSuggestionRequestState
    ) async throws -> AIClassificationSuggestionState {
        DeveloperAIScenarioFixture.categorySuggestion
    }

    func classificationFallbackStatus(
        repoPath _: String,
        request _: AIFallbackStatusRequestSnapshot
    ) async throws -> AIFallbackStatusSnapshot {
        AIFallbackStatusSnapshot(
            operation: .classificationSuggestion,
            kind: .providerUnavailable,
            category: .unavailable,
            title: L10n.string("AI provider is unavailable"),
            message: L10n.string("Retry or classify manually."),
            retryable: true,
            retryDisabledReason: nil,
            primaryAction: .retry,
            secondaryAction: nil,
            nonAIFallbackAction: .classifyManually,
            route: .local,
            callLogID: nil,
            privacyRuleID: nil,
            retryAfter: nil
        )
    }
}

actor DeveloperLocalModelFixture: CoreLocalModelStatusReading {
    func getLocalModelStatus(
        repoPath _: String,
        request _: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        DeveloperAIScenarioFixture.localModelStatus
    }

    func locateLocalModelFolder(
        repoPath _: String,
        request _: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        LocalModelFolderLocationState(
            modelID: LocalModelStatusModel.defaultModelID,
            folderPath: DeveloperAIScenarioFixture.localModelStatus.storageLocation,
            exists: true,
            readable: true,
            openable: true,
            unavailableReason: nil
        )
    }
}

struct DeveloperLocalModelPlatformActions: LocalModelInstallHelpOpening,
    LocalModelFolderOpening,
    LocalModelDiagnosticsCopying,
    LocalModelStorageLocationProviding {
    func defaultStorageLocation() -> String {
        DeveloperAIScenarioFixture.localModelStatus.storageLocation
    }

    @MainActor
    func openLocalModelInstallHelp() throws {}

    @MainActor
    func openLocalModelFolder(_: LocalModelFolderLocationState) throws {}

    @MainActor
    func copyLocalModelDiagnostics(_: String) throws {}
}

@MainActor
final class DeveloperRemoteCredentialStore: RemoteProviderCredentialStoring {
    private var values: [String: String] = [:]

    func storeCredential(
        provider: RemoteProviderKindState,
        endpointURL: String?,
        apiKey: String
    ) throws -> RemoteProviderCredentialDraft {
        let reference = storedCredentialReference(provider: provider, endpointURL: endpointURL)
        values[reference] = apiKey
        return RemoteProviderCredentialDraft(reference: reference)
    }

    func discardCredentialDraft(_ draft: RemoteProviderCredentialDraft) throws {
        values.removeValue(forKey: draft.reference)
    }

    func commitCredentialDraft(_: RemoteProviderCredentialDraft) {}

    func removeCredential(reference: String) throws {
        values.removeValue(forKey: reference)
    }

    func storedCredentialReference(provider: RemoteProviderKindState, endpointURL: String?) -> String {
        "developer-memory:\(provider.rawValue):\(endpointURL ?? "managed")"
    }
}

actor DeveloperAISummaryFixture: CoreAISummaryManaging {
    private var state = AISummaryPersistedStateSnapshot(
        summary: DeveloperAIScenarioFixture.savedSummary,
        contentRevision: DeveloperAIScenarioFixture.savedSummary.contentRevision
    )

    func loadAISummaryState(repoPath _: String, fileID _: Int64) async throws -> AISummaryPersistedStateSnapshot {
        state
    }

    func loadSavedAISummary(repoPath _: String, fileID _: Int64) async throws -> AISummarySavedSnapshot? {
        state.summary
    }

    func generateAISummary(repoPath _: String,
                           request: AISummaryGenerationRequestSnapshot) async throws -> AISummaryDraftSnapshot {
        let summary = "Fresh local summary draft ready for review."
        return AISummaryDraftSnapshot(
            operationID: request.operationID,
            contentLocale: request.contentLocale,
            formatContractVersion: 1,
            fileID: request.fileID,
            draftID: "developer-generated-draft",
            status: .draft,
            summaryText: summary,
            route: .local,
            modelName: "AreaMatrix Local",
            generatedAt: 1_778_738_405,
            usedContext: [.fileName, .repoRelativePath],
            skippedReason: nil,
            privacyRuleID: nil,
            callLogID: nil,
            requiresUserSave: true,
            characterCount: Int64(summary.count)
        )
    }

    func saveAISummary(repoPath _: String,
                       request: AISummarySaveRequestSnapshot) async throws -> AISummarySaveReportSnapshot {
        let revision = request.expectedContentRevision + 1
        let report = AISummarySaveReportSnapshot(
            fileID: request.fileID,
            contentRevision: revision,
            ownership: request.ownership,
            savedSummary: request.summaryText,
            savedAt: 1_778_738_406,
            route: request.route,
            modelName: request.modelName,
            generatedAt: request.generatedAt,
            usedContext: request.usedContext,
            privacyRuleID: request.privacyRuleID,
            callLogID: request.callLogID,
            operationID: request.operationID,
            contentLocale: request.contentLocale,
            formatContractVersion: request.formatContractVersion,
            characterCount: Int64(request.summaryText.count)
        )
        state = AISummaryPersistedStateSnapshot(
            summary: AISummarySavedSnapshot(
                fileID: report.fileID,
                summaryText: report.savedSummary,
                savedAt: report.savedAt,
                draftID: request.draftID,
                route: report.route,
                modelName: report.modelName,
                generatedAt: report.generatedAt,
                usedContext: report.usedContext,
                privacyRuleID: report.privacyRuleID,
                callLogID: report.callLogID,
                editedByUser: report.ownership == .userOwned,
                contentRevision: revision,
                ownership: report.ownership,
                operationID: report.operationID,
                contentLocale: report.contentLocale,
                formatContractVersion: report.formatContractVersion,
                characterCount: report.characterCount
            ),
            contentRevision: revision
        )
        return report
    }

    func clearAISummary(repoPath _: String,
                        request: AISummaryClearRequestSnapshot) async throws -> AISummaryClearReportSnapshot {
        let revision = request.expectedContentRevision + 1
        state = AISummaryPersistedStateSnapshot(summary: nil, contentRevision: revision)
        return AISummaryClearReportSnapshot(
            fileID: request.fileID,
            cleared: true,
            contentRevision: revision,
            clearedAt: 1_778_738_407
        )
    }
}

struct DeveloperContentLocaleSnapshotter: RepositoryContentLocaleSnapshotting {
    func repositoryContentLocaleSnapshot(repoPath _: String) async throws -> String {
        "en"
    }
}
#endif
