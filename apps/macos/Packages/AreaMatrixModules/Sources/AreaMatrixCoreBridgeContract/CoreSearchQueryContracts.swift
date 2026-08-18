public protocol CoreSmartListRunning: Sendable {
    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot
}

public protocol CoreSearchQuerying: CoreSmartListRunning, Sendable {
    func searchFiles(repoPath: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot
}

public enum CoreSearchCapabilityUnavailableError: Error, Equatable, Sendable {
    case smartListRunning
}

public extension CoreSearchQuerying {
    func runSmartList(
        repoPath _: String,
        savedSearchID _: Int64,
        limit _: Int64,
        offset _: Int64
    ) async throws -> SearchResultPageSnapshot {
        throw CoreSearchCapabilityUnavailableError.smartListRunning
    }
}

public enum SearchSortSnapshot: String, CaseIterable, Equatable, Identifiable, Sendable {
    case relevance
    case newestImported
    case newestModified
    case nameAsc

    public var id: String {
        rawValue
    }
}

public enum SearchIndexStatusSnapshot: Equatable, Sendable {
    case ready
    case indexing
    case unavailable
}

public enum SearchModeSnapshot: String, CaseIterable, Equatable, Identifiable, Sendable {
    case normal
    case semantic

    public var id: String {
        rawValue
    }
}

public struct SearchQueryPageContext: Equatable, Sendable {
    public let currentPath: String?
    public let category: String?
    public let filters: SearchFilterStateSnapshot

    public init(currentPath: String?, category: String?, filters: SearchFilterStateSnapshot) {
        self.currentPath = currentPath
        self.category = category
        self.filters = filters
    }
}

public struct SearchQueryRequestSnapshot: Equatable, Sendable {
    public var query: String
    public var scope: SearchScopeSnapshot
    public var currentPath: String?
    public var category: String?
    public var filters: SearchFilterStateSnapshot
    public var sort: SearchSortSnapshot
    public var limit: Int64
    public var offset: Int64
    public var mode: SearchModeSnapshot

    public init(
        query: String,
        scope: SearchScopeSnapshot,
        currentPath: String?,
        category: String?,
        filters: SearchFilterStateSnapshot,
        sort: SearchSortSnapshot,
        limit: Int64,
        offset: Int64,
        mode: SearchModeSnapshot = .normal
    ) {
        self.query = query
        self.scope = scope
        self.currentPath = currentPath
        self.category = category
        self.filters = filters
        self.sort = sort
        self.limit = limit
        self.offset = offset
        self.mode = mode
    }

    public static func pageFeature(
        query: String,
        scope: SearchScopeSnapshot,
        sort: SearchSortSnapshot,
        context: SearchQueryPageContext,
        mode: SearchModeSnapshot = .normal
    ) -> Self {
        Self(
            query: query,
            scope: scope,
            currentPath: scope == .current ? context.currentPath : nil,
            category: scope == .current ? context.category : nil,
            filters: context.filters,
            sort: sort,
            limit: 50,
            offset: 0,
            mode: mode
        )
    }
}

public struct SearchMatchSnapshot: Equatable, Sendable {
    public var fieldDisplayName: String
    public var kindDisplayName: String
    public var snippet: String

    public init(fieldDisplayName: String, kindDisplayName: String, snippet: String) {
        self.fieldDisplayName = fieldDisplayName
        self.kindDisplayName = kindDisplayName
        self.snippet = snippet
    }
}

public struct SearchFileResultSnapshot: Equatable, Identifiable, Sendable {
    public var file: FileEntrySnapshot
    public var score: Float
    public var matches: [SearchMatchSnapshot]
    public var noteSnippet: String?

    public init(file: FileEntrySnapshot, score: Float, matches: [SearchMatchSnapshot], noteSnippet: String?) {
        self.file = file
        self.score = score
        self.matches = matches
        self.noteSnippet = noteSnippet
    }

    public var id: Int64 {
        file.id
    }
}

public struct SearchQueryDiagnosticSnapshot: Equatable, Sendable {
    public var kindDisplayName: String
    public var severityDisplayName: String
    public var message: String
    public var token: String?
    public var start: Int64?
    public var end: Int64?
    public var suggestion: String?
    public private(set) var isError: Bool

    public init(
        kindDisplayName: String = "unknown",
        severityDisplayName: String,
        message: String,
        token: String? = nil,
        start: Int64? = nil,
        end: Int64? = nil,
        suggestion: String? = nil,
        isErrorSeverity: Bool = false
    ) {
        self.kindDisplayName = kindDisplayName
        self.severityDisplayName = severityDisplayName
        self.message = message
        self.token = token
        self.start = start
        self.end = end
        self.suggestion = suggestion
        isError = isErrorSeverity
    }
}

public struct SearchResultPageSnapshot: Equatable, Sendable {
    public var query: String
    public var totalCount: Int64
    public var results: [SearchFileResultSnapshot]
    public var diagnostics: [SearchQueryDiagnosticSnapshot]
    public var indexStatus: SearchIndexStatusSnapshot
    public var semanticPage: SemanticSearchResultPageSnapshot?

    public init(
        query: String,
        totalCount: Int64,
        results: [SearchFileResultSnapshot],
        diagnostics: [SearchQueryDiagnosticSnapshot],
        indexStatus: SearchIndexStatusSnapshot,
        semanticPage: SemanticSearchResultPageSnapshot? = nil
    ) {
        self.query = query
        self.totalCount = totalCount
        self.results = results
        self.diagnostics = diagnostics
        self.indexStatus = indexStatus
        self.semanticPage = semanticPage
    }

    public var hasDiagnosticError: Bool {
        diagnostics.contains(where: \.isError)
    }
}

public struct SemanticSearchResultPageSnapshot: Equatable, Sendable {
    public var query: String
    public var semanticTotalCount: Int64
    public var normalTotalCount: Int64
    public var semanticMatches: [SemanticSearchMatchSnapshot]
    public var normalMatches: [SemanticNormalSearchMatchSnapshot]
    public var dedupedNormalCount: Int64
    public var indexStatus: SemanticIndexStatusSnapshot
    public var route: SemanticSearchRouteSnapshot?
    public var fallbackReason: SemanticSearchFallbackReasonSnapshot?
    public var fallbackMessage: String?
    public var callLogID: Int64?
    public var privacyRuleID: String?
    public var lowConfidence: Bool

    public init(
        query: String,
        semanticTotalCount: Int64,
        normalTotalCount: Int64,
        semanticMatches: [SemanticSearchMatchSnapshot],
        normalMatches: [SemanticNormalSearchMatchSnapshot],
        dedupedNormalCount: Int64,
        indexStatus: SemanticIndexStatusSnapshot,
        route: SemanticSearchRouteSnapshot?,
        fallbackReason: SemanticSearchFallbackReasonSnapshot?,
        fallbackMessage: String?,
        callLogID: Int64?,
        privacyRuleID: String?,
        lowConfidence: Bool
    ) {
        self.query = query
        self.semanticTotalCount = semanticTotalCount
        self.normalTotalCount = normalTotalCount
        self.semanticMatches = semanticMatches
        self.normalMatches = normalMatches
        self.dedupedNormalCount = dedupedNormalCount
        self.indexStatus = indexStatus
        self.route = route
        self.fallbackReason = fallbackReason
        self.fallbackMessage = fallbackMessage
        self.callLogID = callLogID
        self.privacyRuleID = privacyRuleID
        self.lowConfidence = lowConfidence
    }

    public var visibleResults: [SearchFileResultSnapshot] {
        semanticMatches.map(\.result) + normalMatches.filter { !$0.dedupedBySemantic }.map(\.result)
    }

    public var visibleTotalCount: Int64 {
        semanticTotalCount + max(0, normalTotalCount - dedupedNormalCount)
    }

    public var canBuildIndex: Bool {
        indexStatus == .notReady || fallbackReason == .semanticIndexNotReady
    }
}

public struct SemanticSearchMatchSnapshot: Equatable, Sendable {
    public var result: SearchFileResultSnapshot
    public var relevance: Float
    public var matchedReason: String
    public var usedFields: [SemanticSearchInputFieldSnapshot]
    public var route: SemanticSearchRouteSnapshot
    public var alsoMatchedNormalSearch: Bool
    public var callLogID: Int64?
    public var privacyRuleID: String?

    public init(
        result: SearchFileResultSnapshot,
        relevance: Float,
        matchedReason: String,
        usedFields: [SemanticSearchInputFieldSnapshot],
        route: SemanticSearchRouteSnapshot,
        alsoMatchedNormalSearch: Bool,
        callLogID: Int64?,
        privacyRuleID: String?
    ) {
        self.result = result
        self.relevance = relevance
        self.matchedReason = matchedReason
        self.usedFields = usedFields
        self.route = route
        self.alsoMatchedNormalSearch = alsoMatchedNormalSearch
        self.callLogID = callLogID
        self.privacyRuleID = privacyRuleID
    }
}

public struct SemanticNormalSearchMatchSnapshot: Equatable, Sendable {
    public var result: SearchFileResultSnapshot
    public var dedupedBySemantic: Bool

    public init(result: SearchFileResultSnapshot, dedupedBySemantic: Bool) {
        self.result = result
        self.dedupedBySemantic = dedupedBySemantic
    }
}

public struct SemanticIndexBuildReportSnapshot: Equatable, Sendable {
    public var status: SemanticIndexStatusSnapshot
    public var route: SemanticSearchRouteSnapshot?
    public var totalCount: Int64
    public var processedCount: Int64
    public var skippedCount: Int64
    public var failedCount: Int64
    public var privacySkippedCount: Int64
    public var providerName: String?
    public var callLogID: Int64?
    public var fallbackReason: SemanticSearchFallbackReasonSnapshot?
    public var message: String?

    public init(
        status: SemanticIndexStatusSnapshot,
        route: SemanticSearchRouteSnapshot?,
        totalCount: Int64,
        processedCount: Int64,
        skippedCount: Int64,
        failedCount: Int64,
        privacySkippedCount: Int64,
        providerName: String?,
        callLogID: Int64?,
        fallbackReason: SemanticSearchFallbackReasonSnapshot?,
        message: String?
    ) {
        self.status = status
        self.route = route
        self.totalCount = totalCount
        self.processedCount = processedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.privacySkippedCount = privacySkippedCount
        self.providerName = providerName
        self.callLogID = callLogID
        self.fallbackReason = fallbackReason
        self.message = message
    }
}

public enum SemanticIndexStatusSnapshot: Equatable, Sendable {
    case ready, notReady, building, paused, canceled, failed, partial
}

public enum SemanticSearchRouteSnapshot: String, Equatable, Sendable {
    case local = "Local"
    case remote = "Remote"
}

public enum SemanticSearchInputFieldSnapshot: String, Equatable, Sendable {
    case fileName = "File name"
    case repoRelativePath = "Path"
    case category = "Category"
    case noteSummary = "Note summary"
    case aiSummary = "AI summary"
    case extractedTextExcerpt = "Extracted text"
}

public enum SemanticSearchFallbackReasonSnapshot: String, Equatable, Sendable {
    case aiDisabled = "AI disabled"
    case featureDisabled = "Semantic search disabled"
    case providerUnavailable = "Provider unavailable"
    case privacyRule = "Privacy rule"
    case semanticIndexNotReady = "Semantic index not ready"
    case callLogUnavailable = "Call log unavailable"
    case noEligibleInput = "No eligible input"
    case normalSearchUnavailable = "Normal search unavailable"
    case rateLimited = "Rate limited"
    case timeout = "Timeout"
}
