import Foundation

enum AICallLogClearScopeSnapshot: Equatable {
    case all
    case selectedEntries
    case olderThan
}

enum AICallLogFeatureSnapshot: Equatable {
    case classification
    case summary
    case tags
    case semanticSearch
    case providerTest
}

enum AICallLogRouteSnapshot: Equatable {
    case local
    case remote
}

enum AICallLogSentFieldSnapshot: Equatable {
    case fileName
    case repoRelativePath
    case `extension`
    case extractedTextExcerpt
    case aiSummary
    case noteSummary
    case tagCategoryContext
}

enum AICallLogStatusSnapshot: Equatable {
    case success
    case failed
    case skipped
    case unavailable
}

struct AICallLogFilterSnapshot: Equatable {
    var feature: AICallLogFeatureSnapshot?
    var route: AICallLogRouteSnapshot?
    var status: AICallLogStatusSnapshot?
    var occurredAfter: Int64?
    var occurredBefore: Int64?
    var searchQuery: String?
}

struct AICallLogPaginationSnapshot: Equatable {
    var limit: Int64
    var offset: Int64
}

struct AICallLogRecordSnapshot: Equatable {
    var id: Int64
    var occurredAt: Int64
    var feature: AICallLogFeatureSnapshot
    var fileId: Int64?
    var fileDisplayName: String?
    var batchId: String?
    var scope: String?
    var route: AICallLogRouteSnapshot?
    var providerName: String?
    var modelName: String?
    var status: AICallLogStatusSnapshot
    var durationMs: Int64?
    var sentFields: [AICallLogSentFieldSnapshot]
    var privacyRulesChecked: Bool
    var privacyRuleId: String?
    var privacyRuleName: String?
    var matchedFieldType: AICallLogSentFieldSnapshot?
    var resultSummary: String
    var errorCode: String?
}

struct AICallLogPageSnapshot: Equatable {
    var totalCount: Int64
    var records: [AICallLogRecordSnapshot]
    var limit: Int64
    var offset: Int64
    var hasMore: Bool
    var retentionDays: Int64
    var redactionPolicy: String
}

struct AICallLogClearRequestSnapshot: Equatable {
    var scope: AICallLogClearScopeSnapshot
    var entryIds: [Int64]
    var olderThan: Int64?
}

struct AICallLogClearReportSnapshot: Equatable {
    var deletedCount: Int64
    var remainingCount: Int64
    var clearedAt: Int64
}

extension CoreBridge: CoreAICallLogListing {
    func listAICalls(
        repoPath: String,
        filter: AICallLogFilterSnapshot,
        pagination: AICallLogPaginationSnapshot
    ) async throws -> AICallLogPageSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AICallLogPageSnapshot(listAiCalls(
                repoPath: repoPath,
                filter: AiCallLogFilter(filter),
                pagination: AiCallLogPagination(pagination)
            ))
        }.value
    }
}

extension CoreBridge: CoreAICallLogClearing {
    func clearAICallLog(
        repoPath: String,
        request: AICallLogClearRequestSnapshot
    ) async throws -> AICallLogClearReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AICallLogClearReportSnapshot(clearAiCallLog(
                repoPath: repoPath,
                request: AiCallLogClearRequest(request)
            ))
        }.value
    }
}

extension AICallLogPageSnapshot {
    init(_ page: AiCallLogPage) {
        self.init(
            totalCount: page.totalCount,
            records: page.records.map(AICallLogRecordSnapshot.init),
            limit: page.limit,
            offset: page.offset,
            hasMore: page.hasMore,
            retentionDays: page.retentionDays,
            redactionPolicy: page.redactionPolicy
        )
    }
}

extension AICallLogRecordSnapshot {
    init(_ record: AiCallLogRecord) {
        self.init(
            id: record.id,
            occurredAt: record.occurredAt,
            feature: AICallLogFeatureSnapshot(record.feature),
            fileId: record.fileId,
            fileDisplayName: record.fileDisplayName,
            batchId: record.batchId,
            scope: record.scope,
            route: record.route.map(AICallLogRouteSnapshot.init),
            providerName: record.providerName,
            modelName: record.modelName,
            status: AICallLogStatusSnapshot(record.status),
            durationMs: record.durationMs,
            sentFields: record.sentFields.map(AICallLogSentFieldSnapshot.init),
            privacyRulesChecked: record.privacyRulesChecked,
            privacyRuleId: record.privacyRuleId,
            privacyRuleName: record.privacyRuleName,
            matchedFieldType: record.matchedFieldType.map(AICallLogSentFieldSnapshot.init),
            resultSummary: record.resultSummary,
            errorCode: record.errorCode
        )
    }
}

extension AICallLogFeatureSnapshot {
    init(_ feature: AiCallLogFeature) {
        switch feature {
        case .classification: self = .classification
        case .summary: self = .summary
        case .tags: self = .tags
        case .semanticSearch: self = .semanticSearch
        case .providerTest: self = .providerTest
        }
    }

    var coreValue: AiCallLogFeature {
        switch self {
        case .classification: .classification
        case .summary: .summary
        case .tags: .tags
        case .semanticSearch: .semanticSearch
        case .providerTest: .providerTest
        }
    }
}

extension AICallLogRouteSnapshot {
    init(_ route: AiCallLogRoute) {
        switch route {
        case .local: self = .local
        case .remote: self = .remote
        }
    }

    var coreValue: AiCallLogRoute {
        switch self {
        case .local: .local
        case .remote: .remote
        }
    }
}

extension AICallLogStatusSnapshot {
    init(_ status: AiCallLogStatus) {
        switch status {
        case .success: self = .success
        case .failed: self = .failed
        case .skipped: self = .skipped
        case .unavailable: self = .unavailable
        }
    }

    var coreValue: AiCallLogStatus {
        switch self {
        case .success: .success
        case .failed: .failed
        case .skipped: .skipped
        case .unavailable: .unavailable
        }
    }
}

extension AICallLogSentFieldSnapshot {
    init(_ field: AiCallLogSentField) {
        switch field {
        case .fileName: self = .fileName
        case .repoRelativePath: self = .repoRelativePath
        case .extension: self = .extension
        case .extractedTextExcerpt: self = .extractedTextExcerpt
        case .aiSummary: self = .aiSummary
        case .noteSummary: self = .noteSummary
        case .tagCategoryContext: self = .tagCategoryContext
        }
    }
}

extension AiCallLogFilter {
    init(_ filter: AICallLogFilterSnapshot) {
        self.init(
            feature: filter.feature?.coreValue,
            route: filter.route?.coreValue,
            status: filter.status?.coreValue,
            occurredAfter: filter.occurredAfter,
            occurredBefore: filter.occurredBefore,
            searchQuery: filter.searchQuery
        )
    }
}

extension AiCallLogPagination {
    init(_ pagination: AICallLogPaginationSnapshot) {
        self.init(limit: pagination.limit, offset: pagination.offset)
    }
}

extension AiCallLogClearRequest {
    init(_ request: AICallLogClearRequestSnapshot) {
        self.init(
            scope: request.scope.coreValue,
            entryIds: request.entryIds,
            olderThan: request.olderThan
        )
    }
}

extension AICallLogClearScopeSnapshot {
    var coreValue: AiCallLogClearScope {
        switch self {
        case .all: .all
        case .selectedEntries: .selectedEntries
        case .olderThan: .olderThan
        }
    }
}

extension AICallLogClearReportSnapshot {
    init(_ report: AiCallLogClearReport) {
        self.init(
            deletedCount: report.deletedCount,
            remainingCount: report.remainingCount,
            clearedAt: report.clearedAt
        )
    }
}
