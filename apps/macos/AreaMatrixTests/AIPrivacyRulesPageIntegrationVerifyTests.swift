@testable import AreaMatrix
import AreaMatrixFeatureAI
import XCTest

final class AIPrivacyRulesPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    // swiftlint:disable:next function_body_length
    func testAIPrivacyRulesFullPageFlowKeepsDeclaredBridgePaths() async {
        let settingsStore = AIPrivacyRulesIntegrationAISettingsStore(
            snapshot: .aiPrivacyRulesIntegrationReady(repoPath: "/tmp/aiPrivacyRules")
        )
        let settingsModel = AISettingsModel(
            repoPath: "/tmp/aiPrivacyRules",
            loader: settingsStore,
            updater: settingsStore,
            errorMapper: aiPrivacyRulesIntegrationErrorMapper()
        )
        let providerBridge = RemoteProviderConfigBridge(initial: .aiPrivacyRulesIntegrationProviderReady())
        let providerModel = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/aiPrivacyRules",
            providerReader: providerBridge,
            errorMapper: aiPrivacyRulesIntegrationErrorMapper()
        )
        let privacyBridge = RemotePrivacyRulesBridge(
            snapshot: .aiPrivacyRulesIntegrationRules(privacyGateEnabled: true),
            evaluationReport: .aiPrivacyRulesIntegrationProviderGateBlocked()
        )
        let privacyModel = AIPrivacyRulesModel(
            repoPath: "/tmp/aiPrivacyRules",
            rulesManager: privacyBridge,
            evaluator: privacyBridge,
            errorMapper: aiPrivacyRulesIntegrationErrorMapper(),
            settingsSync: settingsModel
        )

        await settingsModel.load()
        await providerModel.load()
        await privacyModel.load()
        await privacyModel.setPrivacyGate(false)
        await privacyModel.setField(.noteSummary, allowRemote: false)
        let editedRule = AIPrivacyRuleEditorDraft(record: .aiPrivacyRulesIntegrationRule())
            .withPattern("finance/private/q2/")
        await privacyModel.saveRule(editedRule)
        await privacyModel.addRules([AIPrivacyRuleTemplate.confidentialKeywords.ruleInput])
        await privacyModel.evaluate(context: AIPrivacyRuleTestFileContext(
            repoRelativePath: "finance/private/q2/report.key",
            category: "finance",
            tags: ["client-private"]
        ))

        await settingsStore.assertUpdateCount(1)
        await settingsStore.assertUpdatedConfigValue(at: 0, \.privacyGateEnabled, false)
        await settingsModel.load()
        XCTAssertEqual(settingsModel.snapshot?.config.privacyGateEnabled, false)
        XCTAssertEqual(settingsModel.snapshot.map { AIPrivacyRulesAISettingsPrivacySummary(snapshot: $0).label }, "Off")
        await providerBridge.assertLoadCount(1)
        await providerBridge.assertNoDisableRequest()
        await privacyBridge.assertLoadCount(1)
        await privacyBridge.assertUpdateCount(4)
        await privacyBridge.assertUpdate(at: 0, privacyGateEnabled: false)
        await privacyBridge.assertProviderScope(at: 0, remoteProviderEnabled: true)
        await privacyBridge.assertUpdateFieldPolicy(at: 1, field: .noteSummary, allowRemote: false)
        await privacyBridge.assertUpdateRule(at: 2, position: .first, pattern: "finance/private/q2/")
        await privacyBridge.assertUpdateRule(at: 3, position: .last, name: L10n.string("Confidential keywords"))
        await privacyBridge.assertEvaluationFeatures(AISettingsFeatureKind.aiPrivacyRulesCases)
        await privacyBridge.assertEvaluation(
            at: 0,
            repoRelativePath: "finance/private/q2/report.key",
            category: "finance",
            tags: ["client-private"]
        )
        XCTAssertEqual(privacyModel.evaluation?.providerGateReason, .privacyGateDisabled)
        XCTAssertEqual(privacyModel.evaluation?.sentFields, [])
        XCTAssertEqual(privacyModel.featureEvaluations.count, 4)
    }

    func testAIPrivacyRulesEditorDraftValidationCoversRequiredRuleTypesAndUnsavedState() {
        var folder = AIPrivacyRuleEditorDraft()
        folder.pattern = "/absolute/path"
        XCTAssertEqual(
            folder.validationMessage(registry: .unavailable),
            L10n.string("Use a path relative to the AreaMatrix repository root.")
        )

        var extensionDraft = AIPrivacyRuleEditorDraft()
        extensionDraft.kind = .extension
        extensionDraft.pattern = "key"
        XCTAssertEqual(
            extensionDraft.validationMessage(registry: .unavailable),
            L10n.string("Extension patterns must start with a dot.")
        )

        var category = AIPrivacyRuleEditorDraft()
        category.kind = .category
        category.pattern = "finance"
        XCTAssertEqual(
            category.validationMessage(registry: .unavailable),
            L10n.string("Category registry is unavailable.")
        )
        XCTAssertEqual(
            category.validationMessage(registry: .testFixture(categories: ["docs"])),
            L10n.string("Choose an existing category from the registry.")
        )
        XCTAssertEqual(
            category.validationMessage(registry: .testFixture(categories: ["finance"])),
            L10n.string("Ready to save.")
        )

        var tag = AIPrivacyRuleEditorDraft()
        tag.kind = .tag
        tag.pattern = "client-private"
        XCTAssertEqual(tag.validationMessage(registry: .unavailable), L10n.string("Tag registry is unavailable."))
        XCTAssertEqual(
            tag.validationMessage(registry: .testFixture(tags: ["client-private"])),
            L10n.string("Ready to save.")
        )

        let rule = AIPrivacyRuleRecordSnapshot.aiPrivacyRulesIntegrationRule()
        var edit = AIPrivacyRuleEditorDraft(record: rule)
        XCTAssertFalse(edit.hasChanges)
        edit.description = "Updated reason"
        XCTAssertTrue(edit.hasChanges)
        XCTAssertEqual(edit.validationMessage(registry: .unavailable), L10n.string("Ready to save."))
    }

    @MainActor
    func testAIPrivacyRulesSaveFailuresKeepFieldPendingStateAndExposeRetryOrRevert() async {
        let bridge = RemotePrivacyRulesBridge(
            snapshot: .aiPrivacyRulesIntegrationRules(privacyGateEnabled: true),
            updateFails: true
        )
        let model = AIPrivacyRulesModel(
            repoPath: "/tmp/aiPrivacyRules",
            rulesManager: bridge,
            evaluator: bridge,
            errorMapper: aiPrivacyRulesIntegrationErrorMapper()
        )

        await model.load()
        let didSave = await model.setField(.noteSummary, allowRemote: false)
        XCTAssertFalse(didSave)
        XCTAssertEqual(model.saveError?.message, L10n.message("Privacy field settings could not be saved."))
        XCTAssertFalse(model.fields.first { $0.field == .noteSummary }?.allowRemote ?? true)

        model.revertPendingSave()
        XCTAssertTrue(model.fields.first { $0.field == .noteSummary }?.allowRemote ?? false)
    }

    @MainActor
    func testAIPrivacyRulesRegistryReaderUsesClassifierCategoriesAndTagFacets() async throws {
        let reader = CoreAIPrivacyRuleRegistryReader(
            classifierReader: AIPrivacyRulesClassifierRegistryBridge(),
            facetReader: AIPrivacyRulesFacetRegistryBridge()
        )

        let registry = try await reader.loadRegistry(repoPath: "/tmp/aiPrivacyRules")

        XCTAssertEqual(registry.categories, ["finance", "inbox"])
        XCTAssertEqual(registry.tags, ["client-private", "legal"])
        XCTAssertTrue(registry.containsCategory("Finance"))
        XCTAssertTrue(registry.containsTag("CLIENT-PRIVATE"))
    }
}

private typealias AIPrivacyRulesIntegrationAISettingsStore = RecordingAISettingsStore

private func aiPrivacyRulesIntegrationErrorMapper() -> StaticCoreErrorMapper {
    StaticCoreErrorMapper(mapping: CoreErrorMappingSnapshot.testFixture(
        kind: .db,
        userMessage: "ai-privacy-rules integration bridge failed",
        severity: .medium,
        suggestedAction: "Retry",
        recoverability: .retryable,
        rawContext: "ai-privacy-rules page integration"
    ))
}

private struct AIPrivacyRulesAISettingsPrivacySummary {
    let label: String

    init(snapshot: AISettingsSnapshot) {
        let config = snapshot.config
        if config.privacyGateEnabled {
            label = config.privacyPolicyRef ?? "Default gate enabled"
        } else {
            label = "Off"
        }
    }
}

private actor AIPrivacyRulesClassifierRegistryBridge: CoreClassifierRuleEditing {
    func listClassifierRules(
        repoPath _: String,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        ClassifierRuleEditorSnapshotState(
            rules: [
                ClassifierRuleRecordSnapshot.testFixture(
                    ruleID: "inbox",
                    displayName: "Inbox",
                    isDefault: true
                ),
                ClassifierRuleRecordSnapshot.testFixture(
                    ruleID: "finance",
                    displayName: "Finance"
                ) {
                    $0.priority = 10
                }
            ],
            defaultRuleID: "inbox",
            updatedRuleID: nil,
            repositoryLocalePolicy: "en",
            editingLocale: .en,
            health: .valid,
            recoveryActions: [],
            warning: nil
        )
    }

    func createClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "ai-privacy-rules registry test is read-only")
    }

    func updateClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "ai-privacy-rules registry test is read-only")
    }

    func deleteClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "ai-privacy-rules registry test is read-only")
    }

    func createDefaultClassifier(
        repoPath _: String,
        confirmed _: Bool,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "ai-privacy-rules registry test is read-only")
    }

    func restoreDefaultClassifier(
        repoPath _: String,
        confirmed _: Bool,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "ai-privacy-rules registry test is read-only")
    }

    func restoreLastValidClassifier(
        repoPath _: String,
        confirmed _: Bool,
        editingLocale _: ClassifierEditingLocale?
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "ai-privacy-rules registry test is read-only")
    }
}

private actor AIPrivacyRulesFacetRegistryBridge: CoreSearchFiltering {
    func listFilterFacets(
        repoPath _: String,
        request: SearchFacetRequestSnapshot
    ) async throws -> SearchFacetsSnapshot {
        XCTAssertEqual(request.query, "")
        XCTAssertEqual(request.scope, .all)
        return SearchFacetsSnapshot.testFixture(totalCount: 2) {
            $0.tags = [
                .testFixture(value: "legal", label: "Legal", count: 3),
                .testFixture(value: "client-private", label: "Client Private", count: 5)
            ]
        }
    }
}

private extension AISettingsSnapshot {
    static func aiPrivacyRulesIntegrationReady(repoPath: String) -> AISettingsSnapshot {
        let config = AISettingsConfigSnapshot.aiSettingsConfig(
            repoPath: repoPath,
            aiEnabled: true,
            providerPreference: .remoteFirst,
            localAIEnabled: true,
            remoteAIAllowed: true,
            privacyGateEnabled: true,
            privacyPolicyRef: "Default gate policy",
            enabledFeatures: [.autoSummaries, .semanticSearch],
            remoteAllowedFeatures: [.autoSummaries, .semanticSearch]
        )
        return AISettingsSnapshot.aiSettingsSnapshot(
            config: config,
            updatedAt: 309
        )
    }
}

private extension RemoteProviderConfigState {
    static func aiPrivacyRulesIntegrationProviderReady() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: .openAi,
            modelID: "gpt-4.1-mini",
            endpointURL: nil,
            credentialConfigured: true,
            featureScope: [.autoSummaries, .semanticSearch],
            updatedAt: 309,
            disabledReason: nil
        )
    }
}

private extension AIPrivacyRulesSnapshot {
    static func aiPrivacyRulesIntegrationRules(privacyGateEnabled: Bool) -> AIPrivacyRulesSnapshot {
        testFixture(
            privacyGateEnabled: privacyGateEnabled,
            rules: [.aiPrivacyRulesIntegrationRule()],
            remoteAllowedFields: [
                .testFixture(field: .fileName),
                .testFixture(field: .repoRelativePath, lastMatchedCount: 1),
                .testFixture(field: .extension),
                .testFixture(field: .extractedTextExcerpt, allowRemote: false, lastMatchedCount: 2),
                .testFixture(field: .aiSummary),
                .testFixture(field: .noteSummary, lastMatchedCount: 3),
                .testFixture(field: .tagCategoryContext, allowRemote: false, lastMatchedCount: 4)
            ],
            providerScope: .testFixture(
                featureScope: [.autoSummaries, .semanticSearch]
            ),
            updatedAt: 309
        )
    }
}

private extension AIPrivacyRuleRecordSnapshot {
    static func aiPrivacyRulesIntegrationRule() -> AIPrivacyRuleRecordSnapshot {
        AIPrivacyRuleRecordSnapshot(
            ruleId: "rule-finance-folder",
            name: "Folder finance/private/",
            kind: .folder,
            pattern: "finance/private/",
            appliesTo: .remoteAi,
            enabled: true,
            description: "Blocks finance folders from remote AI.",
            matchCount: 42,
            lastMatchedAt: 309
        )
    }
}

private extension AIPrivacyRuleEditorDraft {
    func withPattern(_ pattern: String) -> AIPrivacyRuleInputSnapshot {
        var copy = self
        copy.pattern = pattern
        return copy.input
    }
}

private extension AIPrivacyEvaluationReportSnapshot {
    static func aiPrivacyRulesIntegrationProviderGateBlocked() -> AIPrivacyEvaluationReportSnapshot {
        AIPrivacyEvaluationReportSnapshot(
            decision: .skipped,
            skippedReason: .privacyGateDisabled,
            providerGateReason: .privacyGateDisabled,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [],
            blockedFields: [.fileName, .repoRelativePath, .extension],
            sentFields: [],
            message: "Remote AI blocked by privacy gate"
        )
    }
}
