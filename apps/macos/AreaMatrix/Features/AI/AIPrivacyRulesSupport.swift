import Foundation

struct AIPrivacyRuleRegistrySnapshot: Equatable {
    var categories: [String]
    var tags: [String]

    static let unavailable = AIPrivacyRuleRegistrySnapshot(categories: [], tags: [])

    var isUnavailable: Bool {
        categories.isEmpty && tags.isEmpty
    }

    func containsCategory(_ value: String) -> Bool {
        categories.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }

    func containsTag(_ value: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}

struct AIPrivacyRuleTestFileContext: Equatable {
    var repoRelativePath: String
    var category: String?
    var tags: [String]

    var normalizedPath: String {
        repoRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        normalizedPath.isEmpty
    }

    var evaluationContext: AIPrivacyEvaluationContextSnapshot {
        let path = normalizedPath
        return AIPrivacyEvaluationContextSnapshot(
            fileId: nil,
            repoRelativePath: path,
            fileName: (path as NSString).lastPathComponent,
            category: clean(category),
            extension: (path as NSString).pathExtension,
            tags: tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AIPrivacyRuleFeatureEvaluation: Equatable, Identifiable {
    var feature: AISettingsFeatureKind
    var report: AIPrivacyEvaluationReportSnapshot

    var id: String {
        feature.aiPrivacyRulesLabel
    }
}

enum AIPrivacyRuleExitAction: Equatable {
    case close
    case cancelEditor
    case openAddEditor
    case switchRule(AIPrivacyRuleRecordSnapshot)
}

enum AIPrivacyRuleEditorMode: Equatable {
    case hidden
    case visible
}

struct AIPrivacyRuleEditorDraft: Equatable {
    var originalRuleID: String?
    var originalName: String?
    var originalKind = AIPrivacyRuleKindState.folder
    var originalPattern = ""
    var originalAppliesTo = AIPrivacyRuleAppliesToState.remoteAi
    var originalDescription: String?
    var originalEnabled = true
    var kind = AIPrivacyRuleKindState.folder
    var pattern = ""
    var appliesTo = AIPrivacyRuleAppliesToState.remoteAi
    var description = ""
    var enabled = true

    init() {}

    init(record: AIPrivacyRuleRecordSnapshot) {
        originalRuleID = record.ruleId
        originalName = record.name
        originalKind = record.kind
        originalPattern = record.pattern
        originalAppliesTo = record.appliesTo
        originalDescription = record.description
        originalEnabled = record.enabled
        kind = record.kind
        pattern = record.pattern
        appliesTo = record.appliesTo
        description = record.description ?? ""
        enabled = record.enabled
    }

    var isEditing: Bool {
        originalRuleID != nil
    }

    var hasChanges: Bool {
        originalRuleID == nil
            ? !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            kind != .folder || appliesTo != .remoteAi || !description.isEmpty || !enabled
            : kind != originalKind || trimmedPattern != originalPattern || appliesTo != originalAppliesTo ||
            trimmedDescription != originalDescription || enabled != originalEnabled
    }

    var input: AIPrivacyRuleInputSnapshot {
        AIPrivacyRuleInputSnapshot(
            ruleId: originalRuleID,
            name: generatedName,
            kind: kind,
            pattern: trimmedPattern,
            appliesTo: appliesTo,
            enabled: enabled,
            description: trimmedDescription
        )
    }

    func canSave(registry: AIPrivacyRuleRegistrySnapshot) -> Bool {
        validationMessage(registry: registry) == L10n.string("Ready to save.") && hasChanges
    }

    func validationMessage(registry: AIPrivacyRuleRegistrySnapshot) -> String {
        if trimmedPattern.isEmpty { return L10n.string("Pattern is required.") }
        if kind == .folder, trimmedPattern.hasPrefix("/") {
            return L10n.string("Use a path relative to the AreaMatrix repository root.")
        }
        if kind == .extension, !trimmedPattern.hasPrefix(".") {
            return L10n.string("Extension patterns must start with a dot.")
        }
        if kind == .category, registry.categories.isEmpty {
            return L10n.string("Category registry is unavailable.")
        }
        if kind == .category, !registry.categories.isEmpty, !registry.containsCategory(trimmedPattern) {
            return L10n.string("Choose an existing category from the registry.")
        }
        if kind == .tag, registry.tags.isEmpty {
            return L10n.string("Tag registry is unavailable.")
        }
        if kind == .tag, !registry.tags.isEmpty, !registry.containsTag(trimmedPattern) {
            return L10n.string("Choose an existing tag from the registry.")
        }
        if !hasChanges { return L10n.string("No changes to save.") }
        return L10n.string("Ready to save.")
    }

    private var trimmedPattern: String {
        pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String? {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var generatedName: String {
        let pattern = trimmedPattern
        guard !pattern.isEmpty else { return kind.aiPrivacyRulesLabel }
        return "\(kind.aiPrivacyRulesLabel) \(pattern)"
    }
}

enum AIPrivacyRuleTemplate: String, CaseIterable, Identifiable {
    case privateFinanceFolders
    case secretsAndKeyFiles
    case confidentialKeywords

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .privateFinanceFolders: L10n.string("Private finance folders")
        case .secretsAndKeyFiles: L10n.string("Secrets and key files")
        case .confidentialKeywords: L10n.string("Confidential keywords")
        }
    }

    var ruleInput: AIPrivacyRuleInputSnapshot {
        switch self {
        case .privateFinanceFolders:
            AIPrivacyRuleInputSnapshot(
                ruleId: nil,
                name: title,
                kind: .folder,
                pattern: "finance/private/",
                appliesTo: .remoteAi,
                enabled: true,
                description: L10n.string("Blocks finance/private from remote AI.")
            )
        case .secretsAndKeyFiles:
            AIPrivacyRuleInputSnapshot(
                ruleId: nil,
                name: title,
                kind: .extension,
                pattern: ".key",
                appliesTo: .remoteAi,
                enabled: true,
                description: L10n.string("Blocks key files from remote AI.")
            )
        case .confidentialKeywords:
            AIPrivacyRuleInputSnapshot(
                ruleId: nil,
                name: title,
                kind: .keyword,
                pattern: "confidential",
                appliesTo: .localAndRemoteAi,
                enabled: true,
                description: L10n.string("Blocks confidential metadata and derived text.")
            )
        }
    }
}

extension AIPrivacyRuleInputSnapshot {
    init(aiPrivacyRulesRecord record: AIPrivacyRuleRecordSnapshot) {
        self.init(
            ruleId: record.ruleId,
            name: record.name,
            kind: record.kind,
            pattern: record.pattern,
            appliesTo: record.appliesTo,
            enabled: record.enabled,
            description: record.description
        )
    }
}

extension AIPrivacyRuleRecordSnapshot {
    var aiPrivacyRulesLastMatchedText: String {
        lastMatchedAt.map { L10n.format("ai.privacy.lastMatched", $0) }
            ?? L10n.string("ai.privacy.lastMatchedUnknown")
    }

    var aiPrivacyRulesAccessibilityLabel: String {
        [
            enabled ? L10n.string("Enabled") : L10n.string("Disabled"),
            kind.aiPrivacyRulesLabel,
            pattern,
            appliesTo.aiPrivacyRulesLabel,
            L10n.plural("ai.privacy.matchCount", count: matchCount),
            aiPrivacyRulesLastMatchedText
        ].joined(separator: ", ")
    }
}

extension AIPrivacyRulesSnapshot {
    var ruleInputs: [AIPrivacyRuleInputSnapshot] {
        rules.map(AIPrivacyRuleInputSnapshot.init(aiPrivacyRulesRecord:))
    }

    var fieldRules: [AIPrivacyFieldRuleSnapshot] {
        remoteAllowedFields.map(AIPrivacyFieldRuleSnapshot.init(state:))
    }

    func aiPrivacyRulesEvaluationRequests(
        context: AIPrivacyRuleTestFileContext
    ) -> [AIPrivacyEvaluationRequestSnapshot] {
        AISettingsFeatureKind.aiPrivacyRulesCases.map { feature in
            aiPrivacyRulesEvaluationRequest(feature: feature, context: context)
        }
    }

    private func aiPrivacyRulesEvaluationRequest(
        feature: AISettingsFeatureKind,
        context: AIPrivacyRuleTestFileContext
    ) -> AIPrivacyEvaluationRequestSnapshot {
        AIPrivacyEvaluationRequestSnapshot(
            feature: feature,
            route: .remote,
            requestedFields: remoteAllowedFields.map(\.field),
            privacyGateEnabled: privacyGateEnabled,
            providerScope: providerScope,
            rules: ruleInputs,
            remoteAllowedFields: fieldRules,
            context: context.evaluationContext
        )
    }
}

extension AISettingsFeatureKind {
    static let aiPrivacyRulesCases: [AISettingsFeatureKind] = [
        .classificationSuggestions,
        .autoSummaries,
        .autoTags,
        .semanticSearch
    ]

    var aiPrivacyRulesLabel: String {
        switch self {
        case .classificationSuggestions: L10n.string("Classification suggestions")
        case .autoSummaries: L10n.string("Remote summary")
        case .autoTags: L10n.string("Local tags")
        case .semanticSearch: L10n.string("Semantic search")
        }
    }
}

extension AIPrivacyRuleKindState {
    static let aiPrivacyRulesCases: [AIPrivacyRuleKindState] = [.folder, .category, .keyword, .extension, .tag]

    var aiPrivacyRulesLabel: String {
        switch self {
        case .folder: L10n.string("Folder")
        case .category: L10n.string("Category")
        case .keyword: L10n.string("Keyword")
        case .extension: L10n.string("Extension")
        case .tag: L10n.string("Tag")
        }
    }
}

extension AIPrivacyRuleAppliesToState {
    var aiPrivacyRulesLabel: String {
        switch self {
        case .remoteAi: L10n.string("Remote AI")
        case .localAndRemoteAi: L10n.string("Local and remote AI")
        }
    }
}

extension AIPrivacyDecisionState {
    var aiPrivacyRulesLabel: String {
        switch self {
        case .allowed: L10n.string("Allowed")
        case .denied: L10n.string("Denied")
        case .skipped: L10n.string("Skipped")
        }
    }
}

extension AIPrivacySkippedReasonState {
    var aiPrivacyRulesLabel: String {
        switch self {
        case .privacyGateDisabled: L10n.string("privacy gate disabled")
        case .scopeNotAllowed: L10n.string("scope not allowed")
        case .providerNotConfigured: L10n.string("provider not configured")
        case .providerNotVerified: L10n.string("provider not verified")
        case .providerDisabled: L10n.string("provider disabled")
        case .privacyRule: L10n.string("privacy rule")
        case .fieldRule: L10n.string("field rule")
        case .noEligibleInput: L10n.string("no eligible input")
        }
    }
}

extension AIPrivacyProviderGateReasonState {
    var aiPrivacyRulesLabel: String {
        switch self {
        case .privacyGateDisabled: "privacy_gate_disabled"
        case .scopeNotAllowed: "scope_not_allowed"
        case .providerNotConfigured: "provider_not_configured"
        case .providerNotVerified: "provider_not_verified"
        case .providerDisabled: "provider_disabled"
        }
    }
}
