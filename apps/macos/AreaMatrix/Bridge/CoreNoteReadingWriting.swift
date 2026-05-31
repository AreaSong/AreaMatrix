import Combine
import Foundation

struct TagSuggestionContextSnapshot: Equatable {
    var sourceFolder: String?
    var sourceKeywords: [String]
}

struct TagSuggestionRequestSnapshot: Equatable {
    var fileID: Int64
    var context: TagSuggestionContextSnapshot?
    var limit: Int64
}

enum TagSuggestionSourceSnapshot: String, Equatable {
    case fileName = "File name"
    case path = "Path"
    case sourceFolder = "Source folder"
    case existingTagPattern = "Existing tag pattern"
}

enum TagSuggestionMatchSnapshot: String, Equatable {
    case strong = "Strong match"
    case weak = "Weak match"
}

enum TagSuggestionStatusSnapshot: String, Equatable {
    case newTag = "New tag"
    case alreadyAdded = "Already added"
    case invalid = "Invalid"
    case blocked = "Blocked"
}

struct TagSuggestionSnapshot: Equatable, Identifiable {
    var suggestionID: String
    var slug: String
    var displayName: String
    var reason: String
    var source: TagSuggestionSourceSnapshot
    var matchStrength: TagSuggestionMatchSnapshot
    var alreadyExists: Bool
    var needsCreate: Bool
    var status: TagSuggestionStatusSnapshot
    var selectedByDefault: Bool
    var disabledReason: String?

    var id: String {
        suggestionID
    }

    var canApply: Bool {
        status == .newTag && disabledReason == nil
    }
}

struct TagSuggestionReportSnapshot: Equatable {
    var fileID: Int64
    var suggestions: [TagSuggestionSnapshot]
    var tagSet: TagSetSnapshot
    var contentsRead: Bool
    var aiUsed: Bool
    var networkUsed: Bool
}

struct ApplyTagSuggestionItemSnapshot: Equatable, Identifiable {
    var suggestionID: String
    var slug: String
    var displayName: String

    var id: String {
        suggestionID
    }
}

struct ApplyTagSuggestionsRequestSnapshot: Equatable {
    var fileID: Int64
    var suggestions: [ApplyTagSuggestionItemSnapshot]
}

enum TagSuggestionApplyStatusSnapshot: String, Equatable {
    case applied = "Applied"
    case alreadyAdded = "Already added"
    case failed = "Failed"
}

struct TagSuggestionApplyItemResultSnapshot: Equatable, Identifiable {
    var suggestionID: String
    var slug: String
    var status: TagSuggestionApplyStatusSnapshot
    var error: String?

    var id: String {
        suggestionID
    }
}

struct TagSuggestionApplyReportSnapshot: Equatable {
    var fileID: Int64
    var requestedCount: Int64
    var appliedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [TagSuggestionApplyItemResultSnapshot]
    var tagSet: TagSetSnapshot
    var undoToken: String?
    var refreshTargets: [String]
}

enum AISummaryEditorOperation: Equatable {
    case idle, loading, generating, saving, clearing, failed(AISettingsError)

    var isBusy: Bool {
        self == .loading || self == .generating || self == .saving || self == .clearing
    }

    var progressText: String? {
        switch self {
        case .loading:
            "Loading summary..."
        case .generating:
            "Generating..."
        case .saving:
            "Saving summary..."
        case .clearing:
            "Clearing summary..."
        case .idle, .failed:
            nil
        }
    }
}

enum AISummaryEditorFailedAction: Equatable {
    case load, generate, save, clear
}

enum AISummaryEditorStatus: Equatable {
    case empty, draft, saved, dirty
    case skipped(AiSummarySkipReason?)
    case unavailable(AiSummarySkipReason?)

    var label: String {
        switch self {
        case .empty: "No AI summary yet."
        case .draft: "Draft"
        case .saved: "Saved"
        case .dirty: "Unsaved changes"
        case let .skipped(reason): reason.map(aiSummarySkipReasonLabel) ?? "Skipped"
        case .unavailable: "Summary unavailable"
        }
    }
}

struct AISummaryProvenance: Equatable {
    var draftID: String?
    var route: AiSummaryRoute?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AiSummaryInputField]
    var privacyRuleID: String?
    var callLogID: Int64?
    var characterCount: Int64

    init(draft: AiSummaryDraft) {
        draftID = draft.draftId
        route = draft.route
        modelName = draft.modelName
        generatedAt = draft.generatedAt
        usedContext = draft.usedContext
        privacyRuleID = draft.privacyRuleId
        callLogID = draft.callLogId
        characterCount = draft.characterCount
    }

    init(report: AiSummarySaveReport) {
        draftID = nil
        route = report.route
        modelName = report.modelName
        generatedAt = report.generatedAt
        usedContext = report.usedContext
        privacyRuleID = report.privacyRuleId
        callLogID = report.callLogId
        characterCount = report.characterCount
    }

    init(saved: AISummarySavedSnapshot) {
        draftID = saved.draftID
        route = saved.route
        modelName = saved.modelName
        generatedAt = saved.generatedAt
        usedContext = saved.usedContext
        privacyRuleID = saved.privacyRuleID
        callLogID = saved.callLogID
        characterCount = saved.characterCount
    }
}

struct AISummaryEditorSnapshot {
    var draftText: String
    var savedText: String?
    var savedProvenance: AISummaryProvenance?
    var baselineText: String?
    var provenance: AISummaryProvenance?
    var status: AISummaryEditorStatus
}

struct AISummaryEditorIdentity: Equatable {
    var fileID: Int64
    var privacyContext: AISummaryPrivacyContext
}

@MainActor
final class AISummaryEditorExitController: ObservableObject {
    @Published private(set) var needsConfirmation = false

    private var saveHandler: (@MainActor () async -> Bool)?
    private var discardHandler: (@MainActor () -> Void)?

    func update(
        needsConfirmation: Bool,
        saveHandler: @escaping @MainActor () async -> Bool,
        discardHandler: @escaping @MainActor () -> Void
    ) {
        self.needsConfirmation = needsConfirmation
        self.saveHandler = saveHandler
        self.discardHandler = discardHandler
    }

    func saveChanges() async -> Bool {
        guard let saveHandler else { return true }
        let saved = await saveHandler()
        needsConfirmation = !saved
        return saved
    }

    func discardChanges() {
        discardHandler?()
        needsConfirmation = false
    }
}

enum AISummaryConfirmation {
    case regenerate, clear

    var title: String {
        switch self {
        case .regenerate: "Regenerate AI summary?"
        case .clear: "Clear AI summary?"
        }
    }

    var message: String {
        switch self {
        case .regenerate:
            """
            This replaces the current draft or unsaved edits with a new AI-generated draft. \
            Saved notes and the original file will not be changed.
            """
        case .clear:
            """
            This clears the AI-derived summary for this file. It will not delete your note, \
            original file, extracted text, tags, or AI call log.
            """
        }
    }

    var actionTitle: String {
        switch self {
        case .regenerate: "Regenerate"
        case .clear: "Clear summary"
        }
    }

    var isDestructive: Bool {
        self == .clear
    }
}

struct AISummaryCallLogRoute: Identifiable, Equatable {
    var callLogID: Int64
    var id: Int64 { callLogID }
}

protocol CoreAIPrivacyEvaluating: Sendable {
    func loadAIPrivacyRules(repoPath: String) async throws -> AiPrivacyRulesSnapshot
    func evaluateAIPrivacy(
        repoPath: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport
}

protocol CoreNoteReadingWriting: Sendable {
    func readNote(repoPath: String, fileID: Int64) async throws -> String?
    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws
}

protocol CoreAISummaryManaging: Sendable {
    func loadSavedAISummary(repoPath: String, fileID: Int64) async throws -> AISummarySavedSnapshot?
    func generateAISummary(repoPath: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft
    func saveAISummary(repoPath: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport
    func clearAISummary(repoPath: String, request: AiSummaryClearRequest) async throws -> AiSummaryClearReport
}

extension CoreBridge: CoreNoteReadingWriting {
    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            try readCoreNote(repoPath: repoPath, fileID: fileID)
        }.value
    }

    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try writeCoreNote(repoPath: repoPath, fileID: fileID, contentMarkdown: contentMarkdown)
        }.value
    }
}

extension CoreBridge: CoreAISummaryManaging {
    func loadSavedAISummary(repoPath: String, fileID: Int64) async throws -> AISummarySavedSnapshot? {
        try await SQLiteAISummaryMetadataReader().savedSummary(repoPath: repoPath, fileID: fileID)
    }

    func generateAISummary(repoPath: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft {
        try await Task.detached(priority: .userInitiated) {
            try generateAiSummary(repoPath: repoPath, request: request)
        }.value
    }

    func saveAISummary(repoPath: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport {
        try await Task.detached(priority: .userInitiated) {
            try saveAiSummary(repoPath: repoPath, request: request)
        }.value
    }

    func clearAISummary(repoPath: String, request: AiSummaryClearRequest) async throws -> AiSummaryClearReport {
        try await Task.detached(priority: .userInitiated) {
            try clearAiSummary(repoPath: repoPath, request: request)
        }.value
    }
}

private func readCoreNote(repoPath: String, fileID: Int64) throws -> String? {
    try readNote(repoPath: repoPath, fileId: fileID)
}

private func writeCoreNote(repoPath: String, fileID: Int64, contentMarkdown: String) throws {
    try writeNote(repoPath: repoPath, fileId: fileID, contentMd: contentMarkdown)
}

extension TagSuggestionContext {
    init(snapshot: TagSuggestionContextSnapshot) {
        self.init(sourceFolder: snapshot.sourceFolder, sourceKeywords: snapshot.sourceKeywords)
    }
}

extension TagSuggestionRequest {
    init(snapshot: TagSuggestionRequestSnapshot) {
        self.init(
            fileId: snapshot.fileID,
            context: snapshot.context.map(TagSuggestionContext.init(snapshot:)),
            limit: snapshot.limit
        )
    }
}

extension ApplyTagSuggestionItem {
    init(snapshot: ApplyTagSuggestionItemSnapshot) {
        self.init(
            suggestionId: snapshot.suggestionID,
            slug: snapshot.slug,
            displayName: snapshot.displayName
        )
    }
}

extension ApplyTagSuggestionsRequest {
    init(snapshot: ApplyTagSuggestionsRequestSnapshot) {
        self.init(
            fileId: snapshot.fileID,
            suggestions: snapshot.suggestions.map(ApplyTagSuggestionItem.init(snapshot:))
        )
    }
}

extension TagSuggestionReportSnapshot {
    init(coreReport: TagSuggestionReport) {
        fileID = coreReport.fileId
        suggestions = coreReport.suggestions.map(TagSuggestionSnapshot.init(coreSuggestion:))
        tagSet = TagSetSnapshot(coreTagSet: coreReport.tagSet)
        contentsRead = coreReport.contentsRead
        aiUsed = coreReport.aiUsed
        networkUsed = coreReport.networkUsed
    }
}

private extension TagSuggestionSnapshot {
    init(coreSuggestion: TagSuggestion) {
        suggestionID = coreSuggestion.suggestionId
        slug = coreSuggestion.slug
        displayName = coreSuggestion.displayName
        reason = coreSuggestion.reason
        source = TagSuggestionSourceSnapshot(coreSource: coreSuggestion.source)
        matchStrength = TagSuggestionMatchSnapshot(coreMatch: coreSuggestion.matchStrength)
        alreadyExists = coreSuggestion.alreadyExists
        needsCreate = coreSuggestion.needsCreate
        status = TagSuggestionStatusSnapshot(coreStatus: coreSuggestion.status)
        selectedByDefault = coreSuggestion.selectedByDefault
        disabledReason = coreSuggestion.disabledReason
    }
}

private extension TagSuggestionSourceSnapshot {
    init(coreSource: TagSuggestionSource) {
        switch coreSource {
        case .fileName: self = .fileName
        case .path: self = .path
        case .sourceFolder: self = .sourceFolder
        case .existingTagPattern: self = .existingTagPattern
        }
    }
}

private extension TagSuggestionMatchSnapshot {
    init(coreMatch: TagSuggestionMatch) {
        switch coreMatch {
        case .strong: self = .strong
        case .weak: self = .weak
        }
    }
}

private extension TagSuggestionStatusSnapshot {
    init(coreStatus: TagSuggestionStatus) {
        switch coreStatus {
        case .newTag: self = .newTag
        case .alreadyAdded: self = .alreadyAdded
        case .invalid: self = .invalid
        case .blocked: self = .blocked
        }
    }
}
