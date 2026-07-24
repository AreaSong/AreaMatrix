import Foundation

extension AiPrivacyFieldRule {
    init(state: AiPrivacyFieldState) {
        self.init(field: state.field, allowRemote: state.allowRemote)
    }
}

func aiPrivacyInputFieldLabel(_ field: AiPrivacyInputField) -> String {
    switch field {
    case .fileName: L10n.string("filename")
    case .repoRelativePath: L10n.string("repo-relative path")
    case .extension: L10n.string("extension")
    case .extractedTextExcerpt: L10n.string("extracted text")
    case .aiSummary: L10n.string("AI summary")
    case .noteSummary: L10n.string("note summary")
    case .tagCategoryContext: L10n.string("tag/category context")
    }
}

func privacySentFields(_ fields: [AiPrivacyInputField]) -> String {
    fields.isEmpty ? L10n.string("none") : fields.map(aiPrivacyInputFieldLabel).joined(separator: ", ")
}

func summaryUsedFields(_ fields: [AiSummaryInputField]) -> String {
    fields.isEmpty ? L10n.string("none") : fields.map(aiSummaryInputFieldLabel).joined(separator: ", ")
}

func aiSummaryRouteLabel(_ route: AiSummaryRoute) -> String {
    switch route {
    case .local: L10n.string("Generated locally")
    case .remote: L10n.string("Generated remotely")
    }
}

func aiSummaryInputFieldLabel(_ field: AiSummaryInputField) -> String {
    switch field {
    case .fileName: L10n.string("filename")
    case .repoRelativePath: L10n.string("repo-relative path")
    case .extractedTextExcerpt: L10n.string("extracted text")
    case .existingAiSummary: L10n.string("existing AI summary")
    case .noteSummary: L10n.string("note summary")
    case .tagCategoryContext: L10n.string("tag/category context")
    }
}

func aiSummarySkipReasonLabel(_ reason: AiSummarySkipReason) -> String {
    switch reason {
    case .aiDisabled: L10n.string("AI summaries are off")
    case .featureDisabled: L10n.string("Auto summaries are off")
    case .providerUnavailable: L10n.string("AI provider is unavailable")
    case .privacyRule: L10n.string("Skipped by privacy rule")
    case .noEligibleInput: L10n.string("No eligible summary input")
    case .callLogUnavailable: L10n.string("AI call log is unavailable")
    }
}

struct AISummaryPrivacyContext: Equatable {
    var repoRelativePath: String?
    var fileName: String?
    var category: String?
    var fileExtension: String?
    var tags: [String]

    init(
        repoRelativePath: String? = nil,
        fileName: String? = nil,
        category: String? = nil,
        fileExtension: String? = nil,
        tags: [String] = []
    ) {
        self.repoRelativePath = Self.nonEmpty(repoRelativePath)
        self.fileName = Self.nonEmpty(fileName)
        self.category = Self.nonEmpty(category)
        self.fileExtension = Self.nonEmpty(fileExtension)?.lowercased()
        self.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    init(file: FileEntrySnapshot, tags: [String] = []) {
        self.init(
            repoRelativePath: file.path,
            fileName: file.currentName,
            category: file.category,
            fileExtension: Self.extensionName(for: file.currentName),
            tags: tags
        )
    }

    var coreContext: AiPrivacyEvaluationContext {
        AiPrivacyEvaluationContext(
            fileId: nil,
            repoRelativePath: repoRelativePath,
            fileName: fileName,
            category: category,
            extension: fileExtension,
            tags: tags
        )
    }

    private static func extensionName(for filename: String) -> String? {
        nonEmpty((filename as NSString).pathExtension)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AISummaryPrivacySkip: Equatable {
    var decision: AiPrivacyDecision
    var message: String
    var skippedReason: AiPrivacySkippedReason?
    var providerGateReason: AiPrivacyProviderGateReason?
    var ruleID: String?
    var matchedField: AiPrivacyInputField?
    var sentFields: [AiPrivacyInputField]

    init(report: AiPrivacyEvaluationReport) {
        decision = report.decision
        message = report.message
        skippedReason = report.skippedReason
        providerGateReason = report.providerGateReason
        ruleID = report.matchedRules.first?.ruleId
        matchedField = report.matchedFieldType
        sentFields = report.sentFields
    }

    init(summaryReason: AiSummarySkipReason) {
        decision = .skipped
        message = aiSummarySkipReasonLabel(summaryReason)
        providerGateReason = summaryReason == .providerUnavailable ? .providerNotConfigured : nil
        ruleID = nil
        matchedField = nil
        sentFields = []
        switch summaryReason {
        case .privacyRule:
            skippedReason = .privacyRule
        case .noEligibleInput:
            skippedReason = .noEligibleInput
        case .providerUnavailable:
            skippedReason = .providerNotConfigured
        case .aiDisabled, .featureDisabled, .callLogUnavailable:
            skippedReason = nil
        }
    }

    var reasonLabel: String {
        if let providerGateReason {
            return providerGateReason.summaryPrivacyReasonLabel
        }
        return skippedReason?.summaryPrivacyReasonLabel ?? L10n.string("Privacy gate blocked this summary.")
    }

    var shouldRecordSkippedCall: Bool {
        skippedReason == .privacyRule || skippedReason == .fieldRule
    }

    var editorStatus: AISummaryEditorStatus {
        switch summaryDraftStatus {
        case .draft:
            .draft
        case .skipped:
            .skipped(summarySkipReason)
        case .unavailable:
            .unavailable(summarySkipReason)
        }
    }

    var privacyPolicyRefForSummaryLog: String? {
        guard shouldRecordSkippedCall else { return nil }
        let reference = ruleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reference, !reference.isEmpty {
            return "block:\(reference)"
        }
        return "block:privacy-rule"
    }

    private var summaryDraftStatus: AiSummaryDraftStatus {
        switch skippedReason {
        case .providerNotConfigured, .providerNotVerified, .providerDisabled,
             .scopeNotAllowed, .privacyGateDisabled:
            .unavailable
        case .privacyRule, .fieldRule, .noEligibleInput, nil:
            .skipped
        }
    }

    private var summarySkipReason: AiSummarySkipReason? {
        switch skippedReason {
        case .privacyRule, .fieldRule:
            skippedReason == .privacyRule ? .privacyRule : .noEligibleInput
        case .noEligibleInput:
            .noEligibleInput
        case .providerNotConfigured, .providerNotVerified, .providerDisabled,
             .scopeNotAllowed, .privacyGateDisabled:
            .providerUnavailable
        case nil:
            nil
        }
    }
}

extension AiPrivacyEvaluationRoute {
    init(summaryProviderScope: AiSummaryProviderScope) {
        switch summaryProviderScope {
        case .localOnly, .localPreferred:
            self = .local
        case .remoteAllowed:
            self = .remote
        }
    }
}

extension AiPrivacyRuleInput {
    init(summaryRule record: AiPrivacyRuleRecord) {
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

private extension AiPrivacyProviderGateReason {
    var summaryPrivacyReasonLabel: String {
        switch self {
        case .privacyGateDisabled: L10n.string("Privacy gate is disabled for remote summaries.")
        case .scopeNotAllowed: L10n.string("Remote summaries are outside the allowed provider scope.")
        case .providerNotConfigured: L10n.string("Remote provider is not configured.")
        case .providerNotVerified: L10n.string("Remote provider has not been verified.")
        case .providerDisabled: L10n.string("Remote provider is disabled.")
        }
    }
}

private extension AiPrivacySkippedReason {
    var summaryPrivacyReasonLabel: String {
        switch self {
        case .privacyGateDisabled: L10n.string("Privacy gate is disabled for remote summaries.")
        case .scopeNotAllowed: L10n.string("Remote summaries are outside the allowed provider scope.")
        case .providerNotConfigured: L10n.string("Remote provider is not configured.")
        case .providerNotVerified: L10n.string("Remote provider has not been verified.")
        case .providerDisabled: L10n.string("Remote provider is disabled.")
        case .privacyRule: L10n.string("A privacy rule blocked the summary input.")
        case .fieldRule: L10n.string("Field-level privacy rules blocked all summary input.")
        case .noEligibleInput: L10n.string("No eligible summary input remains after privacy checks.")
        }
    }
}
