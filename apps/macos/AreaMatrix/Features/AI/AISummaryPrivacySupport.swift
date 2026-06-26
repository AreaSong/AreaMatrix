import Foundation

extension AiPrivacyFieldRule {
    init(state: AiPrivacyFieldState) {
        self.init(field: state.field, allowRemote: state.allowRemote)
    }
}

func aiPrivacyInputFieldLabel(_ field: AiPrivacyInputField) -> String {
    switch field {
    case .fileName: "filename"
    case .repoRelativePath: "repo-relative path"
    case .extension: "extension"
    case .extractedTextExcerpt: "extracted text"
    case .aiSummary: "AI summary"
    case .noteSummary: "note summary"
    case .tagCategoryContext: "tag/category context"
    }
}

func privacySentFields(_ fields: [AiPrivacyInputField]) -> String {
    fields.isEmpty ? "none" : fields.map(aiPrivacyInputFieldLabel).joined(separator: ", ")
}

func summaryUsedFields(_ fields: [AiSummaryInputField]) -> String {
    fields.isEmpty ? "none" : fields.map(aiSummaryInputFieldLabel).joined(separator: ", ")
}

func aiSummaryRouteLabel(_ route: AiSummaryRoute) -> String {
    switch route {
    case .local: "Generated locally"
    case .remote: "Generated remotely"
    }
}

func aiSummaryInputFieldLabel(_ field: AiSummaryInputField) -> String {
    switch field {
    case .fileName: "filename"
    case .repoRelativePath: "repo-relative path"
    case .extractedTextExcerpt: "extracted text"
    case .existingAiSummary: "existing AI summary"
    case .noteSummary: "note summary"
    case .tagCategoryContext: "tag/category context"
    }
}

func aiSummarySkipReasonLabel(_ reason: AiSummarySkipReason) -> String {
    switch reason {
    case .aiDisabled: "AI summaries are off"
    case .featureDisabled: "Auto summaries are off"
    case .providerUnavailable: "AI provider is unavailable"
    case .privacyRule: "Skipped by privacy rule"
    case .noEligibleInput: "No eligible summary input"
    case .callLogUnavailable: "AI call log is unavailable"
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
        return skippedReason?.summaryPrivacyReasonLabel ?? "Privacy gate blocked this summary."
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

    func unloggedDraft(fileID: Int64) -> AiSummaryDraft {
        AiSummaryDraft(
            fileId: fileID,
            draftId: nil,
            status: summaryDraftStatus,
            summaryText: nil,
            route: nil,
            modelName: nil,
            generatedAt: nil,
            usedContext: [],
            skippedReason: summarySkipReason,
            privacyRuleId: ruleID,
            callLogId: nil,
            requiresUserSave: false,
            characterCount: 0
        )
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
        case .privacyGateDisabled: "Privacy gate is disabled for remote summaries."
        case .scopeNotAllowed: "Remote summaries are outside the allowed provider scope."
        case .providerNotConfigured: "Remote provider is not configured."
        case .providerNotVerified: "Remote provider has not been verified."
        case .providerDisabled: "Remote provider is disabled."
        }
    }
}

private extension AiPrivacySkippedReason {
    var summaryPrivacyReasonLabel: String {
        switch self {
        case .privacyGateDisabled: "Privacy gate is disabled for remote summaries."
        case .scopeNotAllowed: "Remote summaries are outside the allowed provider scope."
        case .providerNotConfigured: "Remote provider is not configured."
        case .providerNotVerified: "Remote provider has not been verified."
        case .providerDisabled: "Remote provider is disabled."
        case .privacyRule: "A privacy rule blocked the summary input."
        case .fieldRule: "Field-level privacy rules blocked all summary input."
        case .noEligibleInput: "No eligible summary input remains after privacy checks."
        }
    }
}
