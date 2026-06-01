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

    var evaluationContext: AiPrivacyEvaluationContext {
        let path = normalizedPath
        return AiPrivacyEvaluationContext(
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
    var feature: AiFeatureKind
    var report: AiPrivacyEvaluationReport

    var id: String {
        feature.s309Label
    }
}

enum AIPrivacyRuleExitAction: Equatable {
    case close
    case cancelEditor
    case openAddEditor
    case switchRule(AiPrivacyRuleRecord)
}

enum AIPrivacyRuleEditorMode: Equatable {
    case hidden
    case visible
}

struct AIPrivacyRuleEditorDraft: Equatable {
    var originalRuleID: String?
    var originalName: String?
    var originalKind = AiPrivacyRuleKind.folder
    var originalPattern = ""
    var originalAppliesTo = AiPrivacyRuleAppliesTo.remoteAi
    var originalDescription: String?
    var originalEnabled = true
    var kind = AiPrivacyRuleKind.folder
    var pattern = ""
    var appliesTo = AiPrivacyRuleAppliesTo.remoteAi
    var description = ""
    var enabled = true

    init() {}

    init(record: AiPrivacyRuleRecord) {
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

    var input: AiPrivacyRuleInput {
        AiPrivacyRuleInput(
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
        validationMessage(registry: registry) == "Ready to save." && hasChanges
    }

    func validationMessage(registry: AIPrivacyRuleRegistrySnapshot) -> String {
        if trimmedPattern.isEmpty { return "Pattern is required." }
        if kind == .folder, trimmedPattern.hasPrefix("/") {
            return "Use a path relative to the AreaMatrix repository root."
        }
        if kind == .extension, !trimmedPattern.hasPrefix(".") {
            return "Extension patterns must start with a dot."
        }
        if kind == .category, registry.categories.isEmpty {
            return "Category registry is unavailable."
        }
        if kind == .category, !registry.categories.isEmpty, !registry.containsCategory(trimmedPattern) {
            return "Choose an existing category from the registry."
        }
        if kind == .tag, registry.tags.isEmpty {
            return "Tag registry is unavailable."
        }
        if kind == .tag, !registry.tags.isEmpty, !registry.containsTag(trimmedPattern) {
            return "Choose an existing tag from the registry."
        }
        if !hasChanges { return "No changes to save." }
        return "Ready to save."
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
        guard !pattern.isEmpty else { return kind.s309Label }
        return "\(kind.s309Label) \(pattern)"
    }
}

enum AIPrivacyRuleTemplate: String, CaseIterable, Identifiable {
    case privateFinanceFolders
    case secretsAndKeyFiles
    case confidentialKeywords

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privateFinanceFolders: "Private finance folders"
        case .secretsAndKeyFiles: "Secrets and key files"
        case .confidentialKeywords: "Confidential keywords"
        }
    }

    var ruleInput: AiPrivacyRuleInput {
        switch self {
        case .privateFinanceFolders:
            AiPrivacyRuleInput(
                ruleId: nil,
                name: title,
                kind: .folder,
                pattern: "finance/private/",
                appliesTo: .remoteAi,
                enabled: true,
                description: "Blocks finance/private from remote AI."
            )
        case .secretsAndKeyFiles:
            AiPrivacyRuleInput(
                ruleId: nil,
                name: title,
                kind: .extension,
                pattern: ".key",
                appliesTo: .remoteAi,
                enabled: true,
                description: "Blocks key files from remote AI."
            )
        case .confidentialKeywords:
            AiPrivacyRuleInput(
                ruleId: nil,
                name: title,
                kind: .keyword,
                pattern: "confidential",
                appliesTo: .localAndRemoteAi,
                enabled: true,
                description: "Blocks confidential metadata and derived text."
            )
        }
    }
}

extension AiPrivacyRuleInput {
    init(s309Record record: AiPrivacyRuleRecord) {
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

extension AiPrivacyRuleRecord {
    var s309LastMatchedText: String {
        lastMatchedAt.map { "last matched \($0)" } ?? "last matched unknown"
    }

    var s309AccessibilityLabel: String {
        [
            enabled ? "Enabled" : "Disabled",
            kind.s309Label,
            pattern,
            appliesTo.s309Label,
            "\(matchCount) matches",
            s309LastMatchedText
        ].joined(separator: ", ")
    }
}

extension AiPrivacyRulesSnapshot {
    var ruleInputs: [AiPrivacyRuleInput] {
        rules.map(AiPrivacyRuleInput.init(s309Record:))
    }

    var fieldRules: [AiPrivacyFieldRule] {
        remoteAllowedFields.map(AiPrivacyFieldRule.init(state:))
    }

    func s309EvaluationRequests(
        context: AIPrivacyRuleTestFileContext
    ) -> [AiPrivacyEvaluationRequest] {
        AiFeatureKind.s309Cases.map { feature in
            s309EvaluationRequest(feature: feature, context: context)
        }
    }

    private func s309EvaluationRequest(
        feature: AiFeatureKind,
        context: AIPrivacyRuleTestFileContext
    ) -> AiPrivacyEvaluationRequest {
        AiPrivacyEvaluationRequest(
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

extension AiFeatureKind {
    static let s309Cases: [AiFeatureKind] = [
        .classificationSuggestions,
        .autoSummaries,
        .autoTags,
        .semanticSearch
    ]

    var s309Label: String {
        switch self {
        case .classificationSuggestions: "Classification suggestions"
        case .autoSummaries: "Remote summary"
        case .autoTags: "Local tags"
        case .semanticSearch: "Semantic search"
        }
    }
}

extension AiPrivacyRuleKind {
    static let s309Cases: [AiPrivacyRuleKind] = [.folder, .category, .keyword, .extension, .tag]

    var s309Label: String {
        switch self {
        case .folder: "Folder"
        case .category: "Category"
        case .keyword: "Keyword"
        case .extension: "Extension"
        case .tag: "Tag"
        }
    }
}

extension AiPrivacyRuleAppliesTo {
    var s309Label: String {
        switch self {
        case .remoteAi: "Remote AI"
        case .localAndRemoteAi: "Local and remote AI"
        }
    }
}

extension AiPrivacyDecision {
    var s309Label: String {
        switch self {
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .skipped: "Skipped"
        }
    }
}

extension AiPrivacySkippedReason {
    var s309Label: String {
        switch self {
        case .privacyGateDisabled: "privacy gate disabled"
        case .scopeNotAllowed: "scope not allowed"
        case .providerNotConfigured: "provider not configured"
        case .providerNotVerified: "provider not verified"
        case .providerDisabled: "provider disabled"
        case .privacyRule: "privacy rule"
        case .fieldRule: "field rule"
        case .noEligibleInput: "no eligible input"
        }
    }
}

extension AiPrivacyProviderGateReason {
    var s309Label: String {
        switch self {
        case .privacyGateDisabled: "privacy_gate_disabled"
        case .scopeNotAllowed: "scope_not_allowed"
        case .providerNotConfigured: "provider_not_configured"
        case .providerNotVerified: "provider_not_verified"
        case .providerDisabled: "provider_disabled"
        }
    }
}
