import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreAICallLogListing = AreaMatrixCoreBridgeContract.CoreAICallLogListing
typealias CoreAICallLogClearing = AreaMatrixCoreBridgeContract.CoreAICallLogClearing
typealias AICallLogClearScopeSnapshot = AreaMatrixCoreBridgeContract.AICallLogClearScopeSnapshot
typealias AICallLogFeatureSnapshot = AreaMatrixCoreBridgeContract.AICallLogFeatureSnapshot
typealias AICallLogRouteSnapshot = AreaMatrixCoreBridgeContract.AICallLogRouteSnapshot
typealias AICallLogSentFieldSnapshot = AreaMatrixCoreBridgeContract.AICallLogSentFieldSnapshot
typealias AICallLogStatusSnapshot = AreaMatrixCoreBridgeContract.AICallLogStatusSnapshot
typealias AICallLogFilterSnapshot = AreaMatrixCoreBridgeContract.AICallLogFilterSnapshot
typealias AICallLogPaginationSnapshot = AreaMatrixCoreBridgeContract.AICallLogPaginationSnapshot
typealias AICallLogRecordSnapshot = AreaMatrixCoreBridgeContract.AICallLogRecordSnapshot
typealias AICallLogPageSnapshot = AreaMatrixCoreBridgeContract.AICallLogPageSnapshot
typealias AICallLogClearRequestSnapshot = AreaMatrixCoreBridgeContract.AICallLogClearRequestSnapshot
typealias AICallLogClearReportSnapshot = AreaMatrixCoreBridgeContract.AICallLogClearReportSnapshot

extension CoreBridge: CoreAICallLogListing {
    func listAICalls(
        repoPath: String,
        filter: AICallLogFilterSnapshot,
        pagination: AICallLogPaginationSnapshot
    ) async throws -> AICallLogPageSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AICallLogPageSnapshot(self.generatedAdapter.listAICalls(
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
            try AICallLogClearReportSnapshot(self.generatedAdapter.clearAICallLog(
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
