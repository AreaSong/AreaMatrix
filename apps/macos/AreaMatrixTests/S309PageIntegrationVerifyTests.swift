@testable import AreaMatrix
import XCTest

final class S309PageIntegrationVerifyTests: XCTestCase {
    @MainActor
    // swiftlint:disable:next function_body_length
    func testS309FullPageFlowKeepsC301C303C309OnDeclaredBridgePaths() async {
        let settingsStore = S309IntegrationAISettingsStore(snapshot: .s309IntegrationReady(repoPath: "/tmp/s309"))
        let settingsModel = AISettingsModel(
            repoPath: "/tmp/s309",
            loader: settingsStore,
            updater: settingsStore,
            errorMapper: S309IntegrationErrorMapper()
        )
        let providerBridge = RemoteProviderConfigBridge(initial: .s309IntegrationProviderReady())
        let providerModel = AIPrivacyRemoteProviderStateModel(
            repoPath: "/tmp/s309",
            providerReader: providerBridge,
            errorMapper: S309IntegrationErrorMapper()
        )
        let privacyBridge = RemotePrivacyRulesBridge(
            snapshot: .s309IntegrationRules(privacyGateEnabled: true),
            evaluationReport: .s309IntegrationProviderGateBlocked()
        )
        let privacyModel = AIPrivacyRulesModel(
            repoPath: "/tmp/s309",
            rulesManager: privacyBridge,
            evaluator: privacyBridge,
            errorMapper: S309IntegrationErrorMapper(),
            settingsSync: settingsModel
        )

        await settingsModel.load()
        await providerModel.load()
        await privacyModel.load()
        await privacyModel.setPrivacyGate(false)
        await privacyModel.setField(.noteSummary, allowRemote: false)
        let editedRule = AIPrivacyRuleEditorDraft(record: .s309IntegrationRule()).withPattern("finance/private/q2/")
        await privacyModel.saveRule(editedRule)
        await privacyModel.addRules([AIPrivacyRuleTemplate.confidentialKeywords.ruleInput])
        await privacyModel.evaluate(context: AIPrivacyRuleTestFileContext(
            repoRelativePath: "finance/private/q2/report.key",
            category: "finance",
            tags: ["client-private"]
        ))

        let settingsRequests = await settingsStore.requests()
        let providerRequests = await providerBridge.requests()
        let privacyRequests = await privacyBridge.requests()

        XCTAssertEqual(settingsRequests.count, 1)
        XCTAssertFalse(settingsRequests[0].privacyGateEnabled)
        await settingsModel.load()
        XCTAssertEqual(settingsModel.snapshot?.config.privacyGateEnabled, false)
        XCTAssertEqual(settingsModel.snapshot.map { S309AISettingsPrivacySummary(snapshot: $0).label }, "Off")
        XCTAssertEqual(providerRequests.loadCount, 1)
        XCTAssertNil(providerRequests.disable)
        XCTAssertEqual(privacyRequests.loadCount, 1)
        XCTAssertEqual(privacyRequests.updates.count, 4)
        XCTAssertFalse(privacyRequests.updates[0].privacyGateEnabled)
        XCTAssertTrue(privacyRequests.updates[0].providerScope.remoteProviderEnabled)
        XCTAssertFalse(
            privacyRequests.updates[1].remoteAllowedFields.first { $0.field == .noteSummary }?.allowRemote ?? true
        )
        XCTAssertEqual(privacyRequests.updates[2].rules.first?.pattern, "finance/private/q2/")
        XCTAssertEqual(privacyRequests.updates[3].rules.last?.name, "Confidential keywords")
        XCTAssertEqual(privacyRequests.evaluations.map(\.feature), AiFeatureKind.s309Cases)
        XCTAssertEqual(privacyRequests.evaluations.first?.context.repoRelativePath, "finance/private/q2/report.key")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.category, "finance")
        XCTAssertEqual(privacyRequests.evaluations.first?.context.tags, ["client-private"])
        XCTAssertEqual(privacyModel.evaluation?.providerGateReason, .privacyGateDisabled)
        XCTAssertEqual(privacyModel.evaluation?.sentFields, [])
        XCTAssertEqual(privacyModel.featureEvaluations.count, 4)
    }

    func testS309RouteFocusTargetsRuleAndFieldRowsForOneShotHighlight() {
        let ruleFocus = AIPrivacyRulesRouteFocus.rule(ruleID: " rule-confidential ")
        XCTAssertEqual(ruleFocus.targetID, "s309-rule-rule-confidential")
        XCTAssertEqual(ruleFocus.label, "Focused privacy rule rule-confidential")
        XCTAssertTrue(ruleFocus.matches(ruleID: "rule-confidential"))
        XCTAssertFalse(ruleFocus.matches(ruleID: "rule-other"))

        let fieldFocus = AIPrivacyRulesRouteFocus.field(.noteSummary)
        XCTAssertEqual(fieldFocus.targetID, "s309-field-noteSummary")
        XCTAssertEqual(fieldFocus.label, "Focused remote field note summary")
        XCTAssertTrue(fieldFocus.matches(field: .noteSummary))
        XCTAssertFalse(fieldFocus.matches(field: .fileName))
    }

    @MainActor
    func testS304PrivacySkippedActionBuildsS309RuleFocusedRoute() {
        let model = s304SuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 309, contextPolicy: .fileNameAndPath),
            bridge: S304SuggestionBridge(result: .success(.s304Suggested(fileID: 309)))
        )
        let panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "confidential.pdf",
            currentPath: "inbox/confidential.pdf"
        )

        let route = panel.s309PrivacyRuleRoute(ruleID: " rule-confidential ")

        XCTAssertEqual(route?.repoPath, "/tmp/repo")
        XCTAssertEqual(route?.focus, .rule(ruleID: "rule-confidential"))
        XCTAssertEqual(route?.focus?.targetID, "s309-rule-rule-confidential")
    }

    @MainActor
    func testS306PrivacySkippedNoticeBuildsS309RuleAndFieldFocusedRoutes() {
        let ruleNotice = AISummaryEditorNotice(
            title: "Skipped by privacy rule",
            detail: "A privacy rule blocked the summary input.",
            recovery: "Review privacy rules before generating this summary.",
            capability: "C3-09",
            opensAISettings: false,
            privacyRuleID: " rule-summary ",
            privacyField: nil,
            reason: .privacyBlocked(AISummaryPrivacySkip(summaryReason: .privacyRule))
        )
        let fieldNotice = AISummaryEditorNotice(
            title: "No eligible summary input",
            detail: "All remote summary fields are blocked.",
            recovery: "Review privacy rules before generating this summary.",
            capability: "C3-09",
            opensAISettings: false,
            privacyRuleID: nil,
            privacyField: .noteSummary,
            reason: .noEligibleInput(AISummaryPrivacySkip(summaryReason: .noEligibleInput))
        )

        let ruleRoute = ruleNotice.s309PrivacyRulesRoute(repoPath: "/tmp/s309")
        let fieldRoute = fieldNotice.s309PrivacyRulesRoute(repoPath: "/tmp/s309")

        XCTAssertEqual(ruleRoute?.repoPath, "/tmp/s309")
        XCTAssertEqual(ruleRoute?.focus, .rule(ruleID: "rule-summary"))
        XCTAssertEqual(ruleRoute?.focus?.targetID, "s309-rule-rule-summary")
        XCTAssertEqual(ruleNotice.s309PrivacyRulesRouteAccessibilitySuffix, "privacy-rule-rule-summary")
        XCTAssertEqual(fieldRoute?.repoPath, "/tmp/s309")
        XCTAssertEqual(fieldRoute?.focus, .field(.noteSummary))
        XCTAssertEqual(fieldRoute?.focus?.targetID, "s309-field-noteSummary")
        XCTAssertEqual(fieldNotice.s309PrivacyRulesRouteAccessibilitySuffix, "privacy-field-noteSummary")
    }

    func testS309EditorDraftValidationCoversRequiredRuleTypesAndUnsavedState() {
        var folder = AIPrivacyRuleEditorDraft()
        folder.pattern = "/absolute/path"
        XCTAssertEqual(
            folder.validationMessage(registry: .unavailable),
            "Use a path relative to the AreaMatrix repository root."
        )

        var extensionDraft = AIPrivacyRuleEditorDraft()
        extensionDraft.kind = .extension
        extensionDraft.pattern = "key"
        XCTAssertEqual(
            extensionDraft.validationMessage(registry: .unavailable),
            "Extension patterns must start with a dot."
        )

        var category = AIPrivacyRuleEditorDraft()
        category.kind = .category
        category.pattern = "finance"
        XCTAssertEqual(category.validationMessage(registry: .unavailable), "Category registry is unavailable.")
        XCTAssertEqual(
            category.validationMessage(registry: AIPrivacyRuleRegistrySnapshot(categories: ["docs"], tags: [])),
            "Choose an existing category from the registry."
        )
        XCTAssertEqual(
            category.validationMessage(registry: AIPrivacyRuleRegistrySnapshot(categories: ["finance"], tags: [])),
            "Ready to save."
        )

        var tag = AIPrivacyRuleEditorDraft()
        tag.kind = .tag
        tag.pattern = "client-private"
        XCTAssertEqual(tag.validationMessage(registry: .unavailable), "Tag registry is unavailable.")
        XCTAssertEqual(
            tag.validationMessage(registry: AIPrivacyRuleRegistrySnapshot(categories: [], tags: ["client-private"])),
            "Ready to save."
        )

        let rule = AiPrivacyRuleRecord.s309IntegrationRule()
        var edit = AIPrivacyRuleEditorDraft(record: rule)
        XCTAssertFalse(edit.hasChanges)
        edit.description = "Updated reason"
        XCTAssertTrue(edit.hasChanges)
        XCTAssertEqual(edit.validationMessage(registry: .unavailable), "Ready to save.")
    }

    @MainActor
    func testS309SaveFailuresKeepFieldPendingStateAndExposeRetryOrRevert() async {
        let bridge = RemotePrivacyRulesBridge(
            snapshot: .s309IntegrationRules(privacyGateEnabled: true),
            updateFails: true
        )
        let model = AIPrivacyRulesModel(
            repoPath: "/tmp/s309",
            rulesManager: bridge,
            evaluator: bridge,
            errorMapper: S309IntegrationErrorMapper()
        )

        await model.load()
        let didSave = await model.setField(.noteSummary, allowRemote: false)
        XCTAssertFalse(didSave)
        XCTAssertEqual(model.saveError?.message, "Privacy field settings could not be saved.")
        XCTAssertFalse(model.fields.first { $0.field == .noteSummary }?.allowRemote ?? true)

        model.revertPendingSave()
        XCTAssertTrue(model.fields.first { $0.field == .noteSummary }?.allowRemote ?? false)
    }

    @MainActor
    func testS309RegistryReaderUsesClassifierCategoriesAndTagFacets() async throws {
        let reader = CoreAIPrivacyRuleRegistryReader(
            classifierReader: S309ClassifierRegistryBridge(),
            facetReader: S309FacetRegistryBridge()
        )

        let registry = try await reader.loadRegistry(repoPath: "/tmp/s309")

        XCTAssertEqual(registry.categories, ["finance", "inbox"])
        XCTAssertEqual(registry.tags, ["client-private", "legal"])
        XCTAssertTrue(registry.containsCategory("Finance"))
        XCTAssertTrue(registry.containsTag("CLIENT-PRIVATE"))
    }
}

private actor S309IntegrationAISettingsStore: CoreAISettingsLoading, CoreAISettingsUpdating {
    private var snapshot: AISettingsSnapshot
    private var recorded: [AISettingsConfigSnapshot] = []

    init(snapshot: AISettingsSnapshot) {
        self.snapshot = snapshot
    }

    func loadAISettings(repoPath _: String) async throws -> AISettingsSnapshot {
        snapshot
    }

    func updateAISettings(repoPath _: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        let normalized = newConfig.normalized()
        recorded.append(normalized)
        snapshot = AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: 310
        )
        return snapshot
    }

    func requests() -> [AISettingsConfigSnapshot] {
        recorded
    }
}

private actor S309IntegrationErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "S3-09 integration bridge failed",
            severity: .medium,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "S3-09 page integration"
        )
    }
}

private struct S309AISettingsPrivacySummary {
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

private actor S309ClassifierRegistryBridge: CoreClassifierRuleEditing {
    func listClassifierRules(repoPath _: String) async throws -> ClassifierRuleEditorSnapshotState {
        ClassifierRuleEditorSnapshotState(
            rules: [
                ClassifierRuleRecordSnapshot(
                    ruleID: "inbox",
                    slug: "inbox",
                    displayName: "Inbox",
                    description: "",
                    extensions: [],
                    keywords: [],
                    priority: 0,
                    namingTemplate: nil,
                    isDefault: true
                ),
                ClassifierRuleRecordSnapshot(
                    ruleID: "finance",
                    slug: "finance",
                    displayName: "Finance",
                    description: "",
                    extensions: [],
                    keywords: [],
                    priority: 10,
                    namingTemplate: nil,
                    isDefault: false
                )
            ],
            defaultRuleID: "inbox",
            updatedRuleID: nil,
            warning: nil
        )
    }

    func createClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleCreateRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "S3-09 registry test is read-only")
    }

    func updateClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleUpdateSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "S3-09 registry test is read-only")
    }

    func deleteClassifierRule(
        repoPath _: String,
        request _: ClassifierRuleDeleteRequestSnapshot
    ) async throws -> ClassifierRuleEditorSnapshotState {
        throw CoreError.Internal(message: "S3-09 registry test is read-only")
    }
}

private actor S309FacetRegistryBridge: CoreSearchFiltering {
    func listFilterFacets(
        repoPath _: String,
        request: SearchFacetRequestSnapshot
    ) async throws -> SearchFacetsSnapshot {
        XCTAssertEqual(request.query, "")
        XCTAssertEqual(request.scope, .all)
        return SearchFacetsSnapshot(
            query: "",
            totalCount: 2,
            categories: [],
            fileKinds: [],
            tags: [
                SearchFacetCountSnapshot(value: "legal", label: "Legal", count: 3, selected: false, disabled: false),
                SearchFacetCountSnapshot(
                    value: "client-private",
                    label: "Client Private",
                    count: 5,
                    selected: false,
                    disabled: false
                )
            ],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: nil,
                newestImportedAt: nil,
                oldestModifiedAt: nil,
                newestModifiedAt: nil
            ),
            activeFilterCount: 0
        )
    }
}

private extension AISettingsSnapshot {
    static func s309IntegrationReady(repoPath: String) -> AISettingsSnapshot {
        let config = AISettingsConfigSnapshot(
            repoPath: repoPath,
            aiEnabled: true,
            providerPreference: .remoteFirst,
            localAIEnabled: true,
            remoteAIAllowed: true,
            privacyGateEnabled: true,
            privacyPolicyRef: "Default gate policy",
            featureToggles: [
                AISettingsFeatureConfigSnapshot(feature: .autoSummaries, enabled: true, allowRemote: true),
                AISettingsFeatureConfigSnapshot(feature: .semanticSearch, enabled: true, allowRemote: true)
            ]
        ).normalized()
        return AISettingsSnapshot(
            config: config,
            capabilities: AISettingsCapabilitySnapshot.derived(from: config),
            updatedAt: 309
        )
    }
}

private extension RemoteProviderConfigState {
    static func s309IntegrationProviderReady() -> RemoteProviderConfigState {
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

private extension AiPrivacyRulesSnapshot {
    static func s309IntegrationRules(privacyGateEnabled: Bool) -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: privacyGateEnabled,
            rules: [.s309IntegrationRule()],
            remoteAllowedFields: [
                AiPrivacyFieldState(field: .fileName, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .repoRelativePath, allowRemote: true, lastMatchedCount: 1),
                AiPrivacyFieldState(field: .extension, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .extractedTextExcerpt, allowRemote: false, lastMatchedCount: 2),
                AiPrivacyFieldState(field: .aiSummary, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .noteSummary, allowRemote: true, lastMatchedCount: 3),
                AiPrivacyFieldState(field: .tagCategoryContext, allowRemote: false, lastMatchedCount: 4)
            ],
            providerScope: AiPrivacyProviderScopeSnapshot(
                providerConfigured: true,
                providerVerified: true,
                remoteProviderEnabled: true,
                featureScope: [.autoSummaries, .semanticSearch]
            ),
            updatedAt: 309,
            remoteBlockedByDefault: true
        )
    }
}

private extension AiPrivacyRuleRecord {
    static func s309IntegrationRule() -> AiPrivacyRuleRecord {
        AiPrivacyRuleRecord(
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
    func withPattern(_ pattern: String) -> AiPrivacyRuleInput {
        var copy = self
        copy.pattern = pattern
        return copy.input
    }
}

private extension AiPrivacyEvaluationReport {
    static func s309IntegrationProviderGateBlocked() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
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
