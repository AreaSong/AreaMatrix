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

    var displayName: String {
        switch self {
        case .fileName: L10n.string("File name")
        case .path: L10n.string("Path")
        case .sourceFolder: L10n.string("Source folder")
        case .existingTagPattern: L10n.string("Existing tag pattern")
        }
    }
}

enum TagSuggestionMatchSnapshot: String, Equatable {
    case strong = "Strong match"
    case weak = "Weak match"

    var displayName: String {
        switch self {
        case .strong: L10n.string("Strong match")
        case .weak: L10n.string("Weak match")
        }
    }
}

enum TagSuggestionStatusSnapshot: String, Equatable {
    case newTag = "New tag"
    case alreadyAdded = "Already added"
    case invalid = "Invalid"
    case blocked = "Blocked"

    var displayName: String {
        switch self {
        case .newTag: L10n.string("New tag")
        case .alreadyAdded: L10n.string("Already added")
        case .invalid: L10n.string("Invalid")
        case .blocked: L10n.string("Blocked")
        }
    }
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

struct AISummarySavedSnapshot: Equatable {
    var fileID: Int64
    var summaryText: String
    var savedAt: Int64
    var draftID: String?
    var route: AiSummaryRoute?
    var modelName: String?
    var generatedAt: Int64?
    var usedContext: [AiSummaryInputField]
    var privacyRuleID: String?
    var callLogID: Int64?
    var editedByUser: Bool
    var contentRevision: Int64
    var ownership: AiContentOwnership
    var operationID: String?
    var contentLocale: ContentLocale?
    var formatContractVersion: Int64?
    var characterCount: Int64
}

struct AISummaryPersistedStateSnapshot: Equatable {
    var summary: AISummarySavedSnapshot?
    var contentRevision: Int64
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

protocol CoreAIPrivacyEvaluating: Sendable {
    func loadAIPrivacyRules(repoPath: String) async throws -> AiPrivacyRulesSnapshot
    func evaluateAIPrivacy(
        repoPath: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport
}

protocol RepositoryContentLocaleSnapshotting: Sendable {
    func repositoryContentLocaleSnapshot(repoPath: String) async throws -> String
}

protocol CoreNoteReadingWriting: Sendable {
    func readNote(repoPath: String, fileID: Int64) async throws -> String?
    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws
}

protocol CoreAISummaryManaging: Sendable {
    func loadAISummaryState(repoPath: String, fileID: Int64) async throws -> AISummaryPersistedStateSnapshot
    func loadSavedAISummary(repoPath: String, fileID: Int64) async throws -> AISummarySavedSnapshot?
    func generateAISummary(repoPath: String, request: AiSummaryGenerationRequest) async throws -> AiSummaryDraft
    func saveAISummary(repoPath: String, request: AiSummarySaveRequest) async throws -> AiSummarySaveReport
    func clearAISummary(repoPath: String, request: AiSummaryClearRequest) async throws -> AiSummaryClearReport
}

extension CoreAISummaryManaging {
    func loadAISummaryState(repoPath: String, fileID: Int64) async throws -> AISummaryPersistedStateSnapshot {
        let summary = try await loadSavedAISummary(repoPath: repoPath, fileID: fileID)
        return AISummaryPersistedStateSnapshot(
            summary: summary,
            contentRevision: summary?.contentRevision ?? 0
        )
    }
}

extension CoreBridge: RepositoryContentLocaleSnapshotting {}

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
    func loadAISummaryState(repoPath: String, fileID: Int64) async throws -> AISummaryPersistedStateSnapshot {
        try await SQLiteAISummaryMetadataReader().persistedState(repoPath: repoPath, fileID: fileID)
    }

    func loadSavedAISummary(repoPath: String, fileID: Int64) async throws -> AISummarySavedSnapshot? {
        try await loadAISummaryState(repoPath: repoPath, fileID: fileID).summary
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
