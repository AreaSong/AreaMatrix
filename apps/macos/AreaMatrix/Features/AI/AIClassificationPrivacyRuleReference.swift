import SwiftUI

enum AIClassificationPrivacyRuleReferenceState: Equatable {
    case idle
    case loading
    case loaded(AIClassificationPrivacyRuleReference)
    case notFound(String)
    case failed(AISettingsError)
}

struct AIClassificationPrivacyRuleReference: Equatable {
    var ruleID: String
    var name: String
    var kind: AiPrivacyRuleKind
    var pattern: String
    var appliesTo: AiPrivacyRuleAppliesTo
    var enabled: Bool
    var description: String?
    var matchCount: Int64
    var lastMatchedAt: Int64?

    init(record: AiPrivacyRuleRecord) {
        ruleID = record.ruleId
        name = record.name
        kind = record.kind
        pattern = record.pattern
        appliesTo = record.appliesTo
        enabled = record.enabled
        description = record.description
        matchCount = record.matchCount
        lastMatchedAt = record.lastMatchedAt
    }
}

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
    var sentFields: [AiPrivacyInputField]

    init(report: AiPrivacyEvaluationReport) {
        decision = report.decision
        message = report.message
        skippedReason = report.skippedReason
        providerGateReason = report.providerGateReason
        ruleID = report.matchedRules.first?.ruleId
        sentFields = report.sentFields
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
        case .privacyGateDisabled:
            "Privacy gate is disabled for remote summaries."
        case .scopeNotAllowed:
            "Remote summaries are outside the allowed provider scope."
        case .providerNotConfigured:
            "Remote provider is not configured."
        case .providerNotVerified:
            "Remote provider has not been verified."
        case .providerDisabled:
            "Remote provider is disabled."
        }
    }
}

private extension AiPrivacySkippedReason {
    var summaryPrivacyReasonLabel: String {
        switch self {
        case .privacyGateDisabled:
            "Privacy gate is disabled for remote summaries."
        case .scopeNotAllowed:
            "Remote summaries are outside the allowed provider scope."
        case .providerNotConfigured:
            "Remote provider is not configured."
        case .providerNotVerified:
            "Remote provider has not been verified."
        case .providerDisabled:
            "Remote provider is disabled."
        case .privacyRule:
            "A privacy rule blocked the summary input."
        case .fieldRule:
            "Field-level privacy rules blocked all summary input."
        case .noEligibleInput:
            "No eligible summary input remains after privacy checks."
        }
    }
}

@MainActor
final class AIClassificationPrivacyRuleReferenceModel: ObservableObject {
    @Published private(set) var state: AIClassificationPrivacyRuleReferenceState = .idle

    let repoPath: String
    let ruleID: String
    private let bridge: any CoreAIPrivacyRulesManaging
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        ruleID: String,
        bridge: any CoreAIPrivacyRulesManaging = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.ruleID = ruleID
        self.bridge = bridge
        self.errorMapper = errorMapper
    }

    var reference: AIClassificationPrivacyRuleReference? {
        guard case let .loaded(reference) = state else { return nil }
        return reference
    }

    func load() async {
        guard state != .loading else { return }
        state = .loading
        do {
            let snapshot = try await bridge.loadAIPrivacyRules(repoPath: repoPath)
            if let record = snapshot.rules.first(where: { $0.ruleId == ruleID }) {
                state = .loaded(AIClassificationPrivacyRuleReference(record: record))
            } else {
                state = .notFound(ruleID)
            }
        } catch {
            state = .failed(await privacyRuleError(for: error))
        }
    }

    private func privacyRuleError(for error: Error) async -> AISettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return AISettingsError(
                message: "AI privacy rule could not be loaded.",
                recovery: mapping.suggestedAction.isEmpty ? "Retry" : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return AISettingsError(
            message: "AI privacy rule could not be loaded.",
            recovery: "Retry",
            detail: error.localizedDescription
        )
    }
}

struct AIClassificationPrivacyRuleReferenceSheet: View {
    @StateObject private var model: AIClassificationPrivacyRuleReferenceModel
    let onClose: () -> Void

    init(
        repoPath: String,
        ruleID: String,
        bridge: any CoreAIPrivacyRulesManaging = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: AIClassificationPrivacyRuleReferenceModel(
            repoPath: repoPath,
            ruleID: ruleID,
            bridge: bridge,
            errorMapper: errorMapper
        ))
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            bodyContent
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 540, alignment: .topLeading)
        .task { await model.load() }
        .accessibilityIdentifier("S3-04-C3-09-privacy-rule-reference")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Privacy Rule")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(model.ruleID)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("Loading privacy rule...")
        case let .loaded(reference):
            loadedContent(reference)
        case let .notFound(ruleID):
            notFoundContent(ruleID)
        case let .failed(error):
            failureContent(error)
        }
    }

    private func loadedContent(_ reference: AIClassificationPrivacyRuleReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            referenceRow("Name", reference.name)
            referenceRow("Type", kindLabel(reference.kind))
            referenceRow("Pattern", reference.pattern)
            referenceRow("Applies to", appliesToLabel(reference.appliesTo))
            referenceRow("Status", reference.enabled ? "Enabled" : "Disabled")
            referenceRow("Matches", "\(reference.matchCount)")
            if let lastMatchedAt = reference.lastMatchedAt {
                referenceRow("Last matched", "\(lastMatchedAt)")
            }
            if let description = reference.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("S3-04-C3-09-privacy-rule-loaded")
    }

    private func notFoundContent(_ ruleID: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Privacy rule could not be found.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text("Rule \(ruleID) is not present in the current C3-09 privacy rules snapshot.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await model.load() } }
        }
        .accessibilityIdentifier("S3-04-C3-09-privacy-rule-not-found")
    }

    private func failureContent(_ error: AISettingsError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Retry") { Task { await model.load() } }
        }
        .accessibilityIdentifier("S3-04-C3-09-privacy-rule-error")
    }

    private func referenceRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func kindLabel(_ kind: AiPrivacyRuleKind) -> String {
        switch kind {
        case .folder: "Folder"
        case .category: "Category"
        case .keyword: "Keyword"
        case .extension: "Extension"
        case .tag: "Tag"
        }
    }

    private func appliesToLabel(_ appliesTo: AiPrivacyRuleAppliesTo) -> String {
        switch appliesTo {
        case .remoteAi: "Remote AI"
        case .localAndRemoteAi: "Local and remote AI"
        }
    }
}
