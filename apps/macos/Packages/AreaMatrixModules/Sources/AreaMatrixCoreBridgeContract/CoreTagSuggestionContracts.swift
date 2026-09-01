/// Stable rule-based and AI tag-suggestion contracts consumed by feature models.
///
/// Generated Core conversion remains App-owned. These values and capability
/// protocols contain no platform, localization, or UniFFI dependency.
public struct TagSuggestionContextSnapshot: Equatable, Sendable {
    public var sourceFolder: String?
    public var sourceKeywords: [String]

    public init(sourceFolder: String?, sourceKeywords: [String]) {
        self.sourceFolder = sourceFolder
        self.sourceKeywords = sourceKeywords
    }
}

public struct TagSuggestionRequestSnapshot: Equatable, Sendable {
    public var fileID: Int64
    public var context: TagSuggestionContextSnapshot?
    public var limit: Int64

    public init(fileID: Int64, context: TagSuggestionContextSnapshot?, limit: Int64) {
        self.fileID = fileID
        self.context = context
        self.limit = limit
    }
}

public enum TagSuggestionSourceSnapshot: String, Equatable, Sendable {
    case fileName = "File name"
    case path = "Path"
    case sourceFolder = "Source folder"
    case existingTagPattern = "Existing tag pattern"
}

public enum TagSuggestionMatchSnapshot: String, Equatable, Sendable {
    case strong = "Strong match"
    case weak = "Weak match"
}

public enum TagSuggestionStatusSnapshot: String, Equatable, Sendable {
    case newTag = "New tag"
    case alreadyAdded = "Already added"
    case invalid = "Invalid"
    case blocked = "Blocked"
}

public struct TagSuggestionSnapshot: Equatable, Identifiable, Sendable {
    public var suggestionID: String
    public var slug: String
    public var displayName: String
    public var reason: String
    public var source: TagSuggestionSourceSnapshot
    public var matchStrength: TagSuggestionMatchSnapshot
    public var alreadyExists: Bool
    public var needsCreate: Bool
    public var status: TagSuggestionStatusSnapshot
    public var selectedByDefault: Bool
    public var disabledReason: String?

    public init(
        suggestionID: String,
        slug: String,
        displayName: String,
        reason: String,
        source: TagSuggestionSourceSnapshot,
        matchStrength: TagSuggestionMatchSnapshot,
        alreadyExists: Bool,
        needsCreate: Bool,
        status: TagSuggestionStatusSnapshot,
        selectedByDefault: Bool,
        disabledReason: String?
    ) {
        self.suggestionID = suggestionID
        self.slug = slug
        self.displayName = displayName
        self.reason = reason
        self.source = source
        self.matchStrength = matchStrength
        self.alreadyExists = alreadyExists
        self.needsCreate = needsCreate
        self.status = status
        self.selectedByDefault = selectedByDefault
        self.disabledReason = disabledReason
    }

    public var id: String {
        suggestionID
    }

    public var canApply: Bool {
        status == .newTag && disabledReason == nil
    }
}

public struct TagSuggestionReportSnapshot: Equatable, Sendable {
    public var fileID: Int64
    public var suggestions: [TagSuggestionSnapshot]
    public var tagSet: TagSetSnapshot
    public var contentsRead: Bool
    public var aiUsed: Bool
    public var networkUsed: Bool

    public init(
        fileID: Int64,
        suggestions: [TagSuggestionSnapshot],
        tagSet: TagSetSnapshot,
        contentsRead: Bool,
        aiUsed: Bool,
        networkUsed: Bool
    ) {
        self.fileID = fileID
        self.suggestions = suggestions
        self.tagSet = tagSet
        self.contentsRead = contentsRead
        self.aiUsed = aiUsed
        self.networkUsed = networkUsed
    }
}

public struct ApplyTagSuggestionItemSnapshot: Equatable, Identifiable, Sendable {
    public var suggestionID: String
    public var slug: String
    public var displayName: String

    public init(suggestionID: String, slug: String, displayName: String) {
        self.suggestionID = suggestionID
        self.slug = slug
        self.displayName = displayName
    }

    public var id: String {
        suggestionID
    }
}

public struct ApplyTagSuggestionsRequestSnapshot: Equatable, Sendable {
    public var fileID: Int64
    public var suggestions: [ApplyTagSuggestionItemSnapshot]

    public init(fileID: Int64, suggestions: [ApplyTagSuggestionItemSnapshot]) {
        self.fileID = fileID
        self.suggestions = suggestions
    }
}

public enum TagSuggestionApplyStatusSnapshot: String, Equatable, Sendable {
    case applied = "Applied"
    case alreadyAdded = "Already added"
    case failed = "Failed"
}

public struct TagSuggestionApplyItemResultSnapshot: Equatable, Identifiable, Sendable {
    public var suggestionID: String
    public var slug: String
    public var status: TagSuggestionApplyStatusSnapshot
    public var error: String?

    public init(
        suggestionID: String,
        slug: String,
        status: TagSuggestionApplyStatusSnapshot,
        error: String?
    ) {
        self.suggestionID = suggestionID
        self.slug = slug
        self.status = status
        self.error = error
    }

    public var id: String {
        suggestionID
    }
}

public struct TagSuggestionApplyReportSnapshot: Equatable, Sendable {
    public var fileID: Int64
    public var requestedCount: Int64
    public var appliedCount: Int64
    public var skippedCount: Int64
    public var failedCount: Int64
    public var itemResults: [TagSuggestionApplyItemResultSnapshot]
    public var tagSet: TagSetSnapshot
    public var undoToken: String?
    public var refreshTargets: [String]

    public init(
        fileID: Int64,
        requestedCount: Int64,
        appliedCount: Int64,
        skippedCount: Int64,
        failedCount: Int64,
        itemResults: [TagSuggestionApplyItemResultSnapshot],
        tagSet: TagSetSnapshot,
        undoToken: String?,
        refreshTargets: [String]
    ) {
        self.fileID = fileID
        self.requestedCount = requestedCount
        self.appliedCount = appliedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.itemResults = itemResults
        self.tagSet = tagSet
        self.undoToken = undoToken
        self.refreshTargets = refreshTargets
    }
}

public protocol CoreTagCRUD: Sendable {
    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot
    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot
    func batchAddTags(repoPath: String, fileIDs: [Int64], tags: [String]) async throws -> BatchMutationReportSnapshot
    func suggestTagsForFile(
        repoPath: String,
        request: TagSuggestionRequestSnapshot
    ) async throws -> TagSuggestionReportSnapshot
    func applyTagSuggestions(
        repoPath: String,
        request: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot
}

public protocol CoreAITagSuggestionManaging: Sendable {
    func suggestTagsWithAI(
        repoPath: String,
        request: AITagSuggestionRequestSnapshot
    ) async throws -> AITagSuggestionReportSnapshot
    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAITagSuggestionsRequestSnapshot
    ) async throws -> AITagSuggestionApplyReportSnapshot
}
