/// Stable AI call-log contracts shared by the App composition and feature models.
///
/// The live implementation remains App-owned because it consumes tracked UniFFI
/// bindings. These value types intentionally contain no platform or localization
/// dependencies so they can be used by previews, tests, and future clients.
public protocol CoreAICallLogListing: Sendable {
    func listAICalls(
        repoPath: String,
        filter: AICallLogFilterSnapshot,
        pagination: AICallLogPaginationSnapshot
    ) async throws -> AICallLogPageSnapshot
}

public protocol CoreAICallLogClearing: Sendable {
    func clearAICallLog(
        repoPath: String,
        request: AICallLogClearRequestSnapshot
    ) async throws -> AICallLogClearReportSnapshot
}

public enum AICallLogClearScopeSnapshot: Equatable, Sendable {
    case all
    case selectedEntries
    case olderThan
}

public enum AICallLogFeatureSnapshot: Equatable, Sendable {
    case classification
    case summary
    case tags
    case semanticSearch
    case providerTest
}

public enum AICallLogRouteSnapshot: Equatable, Sendable {
    case local
    case remote
}

public enum AICallLogSentFieldSnapshot: Equatable, Sendable {
    case fileName
    case repoRelativePath
    case `extension`
    case extractedTextExcerpt
    case aiSummary
    case noteSummary
    case tagCategoryContext
}

public enum AICallLogStatusSnapshot: Equatable, Sendable {
    case success
    case failed
    case skipped
    case unavailable
}

public struct AICallLogFilterSnapshot: Equatable, Sendable {
    public var feature: AICallLogFeatureSnapshot?
    public var route: AICallLogRouteSnapshot?
    public var status: AICallLogStatusSnapshot?
    public var occurredAfter: Int64?
    public var occurredBefore: Int64?
    public var searchQuery: String?

    public init(
        feature: AICallLogFeatureSnapshot?,
        route: AICallLogRouteSnapshot?,
        status: AICallLogStatusSnapshot?,
        occurredAfter: Int64?,
        occurredBefore: Int64?,
        searchQuery: String?
    ) {
        self.feature = feature
        self.route = route
        self.status = status
        self.occurredAfter = occurredAfter
        self.occurredBefore = occurredBefore
        self.searchQuery = searchQuery
    }
}

public struct AICallLogPaginationSnapshot: Equatable, Sendable {
    public var limit: Int64
    public var offset: Int64

    public init(limit: Int64, offset: Int64) {
        self.limit = limit
        self.offset = offset
    }
}

public struct AICallLogRecordSnapshot: Equatable, Identifiable, Sendable {
    public var id: Int64
    public var occurredAt: Int64
    public var feature: AICallLogFeatureSnapshot
    public var fileId: Int64?
    public var fileDisplayName: String?
    public var batchId: String?
    public var scope: String?
    public var route: AICallLogRouteSnapshot?
    public var providerName: String?
    public var modelName: String?
    public var status: AICallLogStatusSnapshot
    public var durationMs: Int64?
    public var sentFields: [AICallLogSentFieldSnapshot]
    public var privacyRulesChecked: Bool
    public var privacyRuleId: String?
    public var privacyRuleName: String?
    public var matchedFieldType: AICallLogSentFieldSnapshot?
    public var resultSummary: String
    public var errorCode: String?

    public init(
        id: Int64,
        occurredAt: Int64,
        feature: AICallLogFeatureSnapshot,
        fileId: Int64?,
        fileDisplayName: String?,
        batchId: String?,
        scope: String?,
        route: AICallLogRouteSnapshot?,
        providerName: String?,
        modelName: String?,
        status: AICallLogStatusSnapshot,
        durationMs: Int64?,
        sentFields: [AICallLogSentFieldSnapshot],
        privacyRulesChecked: Bool,
        privacyRuleId: String?,
        privacyRuleName: String?,
        matchedFieldType: AICallLogSentFieldSnapshot?,
        resultSummary: String,
        errorCode: String?
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.feature = feature
        self.fileId = fileId
        self.fileDisplayName = fileDisplayName
        self.batchId = batchId
        self.scope = scope
        self.route = route
        self.providerName = providerName
        self.modelName = modelName
        self.status = status
        self.durationMs = durationMs
        self.sentFields = sentFields
        self.privacyRulesChecked = privacyRulesChecked
        self.privacyRuleId = privacyRuleId
        self.privacyRuleName = privacyRuleName
        self.matchedFieldType = matchedFieldType
        self.resultSummary = resultSummary
        self.errorCode = errorCode
    }
}

public struct AICallLogPageSnapshot: Equatable, Sendable {
    public var totalCount: Int64
    public var records: [AICallLogRecordSnapshot]
    public var limit: Int64
    public var offset: Int64
    public var hasMore: Bool
    public var retentionDays: Int64
    public var redactionPolicy: String

    public init(
        totalCount: Int64,
        records: [AICallLogRecordSnapshot],
        limit: Int64,
        offset: Int64,
        hasMore: Bool,
        retentionDays: Int64,
        redactionPolicy: String
    ) {
        self.totalCount = totalCount
        self.records = records
        self.limit = limit
        self.offset = offset
        self.hasMore = hasMore
        self.retentionDays = retentionDays
        self.redactionPolicy = redactionPolicy
    }
}

public struct AICallLogClearRequestSnapshot: Equatable, Sendable {
    public var scope: AICallLogClearScopeSnapshot
    public var entryIds: [Int64]
    public var olderThan: Int64?

    public init(scope: AICallLogClearScopeSnapshot, entryIds: [Int64], olderThan: Int64?) {
        self.scope = scope
        self.entryIds = entryIds
        self.olderThan = olderThan
    }
}

public struct AICallLogClearReportSnapshot: Equatable, Sendable {
    public var deletedCount: Int64
    public var remainingCount: Int64
    public var clearedAt: Int64

    public init(deletedCount: Int64, remainingCount: Int64, clearedAt: Int64) {
        self.deletedCount = deletedCount
        self.remainingCount = remainingCount
        self.clearedAt = clearedAt
    }
}
