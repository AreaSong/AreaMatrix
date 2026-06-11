import Foundation

struct SemanticSearchResultPageSnapshot: Equatable {
    var query: String
    var semanticTotalCount: Int64
    var normalTotalCount: Int64
    var semanticMatches: [SemanticSearchMatchSnapshot]
    var normalMatches: [SemanticNormalSearchMatchSnapshot]
    var dedupedNormalCount: Int64
    var indexStatus: SemanticIndexStatusSnapshot
    var route: SemanticSearchRouteSnapshot?
    var fallbackReason: SemanticSearchFallbackReasonSnapshot?
    var fallbackMessage: String?
    var callLogID: Int64?
    var privacyRuleID: String?
    var lowConfidence: Bool

    var visibleResults: [SearchFileResultSnapshot] {
        semanticMatches.map(\.result) + normalMatches.filter { !$0.dedupedBySemantic }.map(\.result)
    }

    var visibleTotalCount: Int64 {
        semanticTotalCount + max(0, normalTotalCount - dedupedNormalCount)
    }

    var canBuildIndex: Bool {
        indexStatus == .notReady || fallbackReason == .semanticIndexNotReady
    }

    func result(for fileID: Int64) -> SemanticResultPresentation? {
        if let match = semanticMatches.first(where: { $0.result.file.id == fileID }) {
            return .semantic(match)
        }
        if let match = normalMatches.first(where: { $0.result.file.id == fileID && !$0.dedupedBySemantic }) {
            return .normal(match)
        }
        return nil
    }
}

enum SemanticResultPresentation: Equatable {
    case semantic(SemanticSearchMatchSnapshot)
    case normal(SemanticNormalSearchMatchSnapshot)
}

struct SemanticSearchMatchSnapshot: Equatable {
    var result: SearchFileResultSnapshot
    var relevance: Float
    var matchedReason: String
    var usedFields: [SemanticSearchInputFieldSnapshot]
    var route: SemanticSearchRouteSnapshot
    var alsoMatchedNormalSearch: Bool
    var callLogID: Int64?
    var privacyRuleID: String?
}

struct SemanticNormalSearchMatchSnapshot: Equatable {
    var result: SearchFileResultSnapshot
    var dedupedBySemantic: Bool
}

struct SemanticIndexBuildReportSnapshot: Equatable {
    var status: SemanticIndexStatusSnapshot
    var route: SemanticSearchRouteSnapshot?
    var totalCount: Int64
    var processedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var privacySkippedCount: Int64
    var providerName: String?
    var callLogID: Int64?
    var fallbackReason: SemanticSearchFallbackReasonSnapshot?
    var message: String?
}

enum SemanticIndexStatusSnapshot: Equatable {
    case ready, notReady, building, paused, canceled, failed, partial
}

enum SemanticSearchRouteSnapshot: String, Equatable {
    case local = "Local"
    case remote = "Remote"
}

enum SemanticSearchInputFieldSnapshot: String, Equatable {
    case fileName = "File name"
    case repoRelativePath = "Path"
    case category = "Category"
    case noteSummary = "Note summary"
    case aiSummary = "AI summary"
    case extractedTextExcerpt = "Extracted text"
}

enum SemanticSearchFallbackReasonSnapshot: String, Equatable {
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

extension StorageMode {
    var fileListDisplayName: String {
        switch self {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }
}

extension SearchMatchField {
    var displayName: String {
        switch self {
        case .name:
            "Name"
        case .path:
            "Path"
        case .note:
            "Note"
        case .category:
            "Category"
        case .changeLog:
            "Change log"
        }
    }
}

extension SearchMatchKind {
    var displayName: String {
        switch self {
        case .exact:
            "Exact match"
        case .fuzzy:
            "Fuzzy match"
        case .pinyinInitials:
            "Pinyin initials"
        }
    }
}

extension SearchDiagnosticKind {
    var displayName: String {
        switch self {
        case .unclosedQuote: "Unclosed quote"
        case .unknownField: "Unknown field"
        case .invalidDate: "Invalid date"
        case .unbalancedParentheses: "Unbalanced parentheses"
        case .invalidOperator: "Invalid operator"
        }
    }
}

extension SearchDiagnosticSeverity {
    var displayName: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

extension FileOrigin {
    var fileListDisplayName: String {
        switch self {
        case .imported:
            "Imported"
        case .adopted:
            "Adopted"
        case .external:
            "External"
        }
    }
}

extension SemanticSearchResultPageSnapshot {
    init(
        corePage: SemanticSearchResultPage,
        semanticMatches: [SemanticSearchMatchSnapshot],
        normalMatches: [SemanticNormalSearchMatchSnapshot]
    ) {
        query = corePage.query
        semanticTotalCount = corePage.semanticTotalCount
        normalTotalCount = corePage.normalTotalCount
        self.semanticMatches = semanticMatches
        self.normalMatches = normalMatches
        dedupedNormalCount = corePage.dedupedNormalCount
        indexStatus = SemanticIndexStatusSnapshot(coreStatus: corePage.indexStatus)
        route = corePage.route.map(SemanticSearchRouteSnapshot.init(coreRoute:))
        fallbackReason = corePage.fallbackReason.map(SemanticSearchFallbackReasonSnapshot.init(coreReason:))
        fallbackMessage = corePage.fallbackMessage
        callLogID = corePage.callLogId
        privacyRuleID = corePage.privacyRuleId
        lowConfidence = corePage.lowConfidence
    }
}

extension SearchResultPageSnapshot {
    init(
        coreSemanticPage: SemanticSearchResultPage,
        semanticMatches: [SemanticSearchMatchSnapshot],
        normalMatches: [SemanticNormalSearchMatchSnapshot]
    ) {
        let semanticPage = SemanticSearchResultPageSnapshot(
            corePage: coreSemanticPage,
            semanticMatches: semanticMatches,
            normalMatches: normalMatches
        )
        query = coreSemanticPage.query
        totalCount = semanticPage.visibleTotalCount
        results = semanticPage.visibleResults
        diagnostics = []
        indexStatus = SearchIndexStatusSnapshot(semanticStatus: semanticPage.indexStatus)
        self.semanticPage = semanticPage
    }
}

extension SearchIndexStatusSnapshot {
    init(semanticStatus: SemanticIndexStatusSnapshot) {
        switch semanticStatus {
        case .ready, .partial:
            self = .ready
        case .building, .paused:
            self = .indexing
        case .notReady, .canceled, .failed:
            self = .unavailable
        }
    }
}

extension SemanticIndexScope {
    init(_ request: SearchQueryRequestSnapshot) {
        self.init(
            filter: SearchFilter(request),
            route: nil,
            privacyPolicyRef: nil,
            confirmed: true
        )
    }
}

extension SemanticSearchMatchSnapshot {
    init(coreMatch: SemanticSearchMatch, file: FileEntrySnapshot) {
        result = SearchFileResultSnapshot(coreResult: coreMatch.result, file: file)
        relevance = coreMatch.relevance
        matchedReason = coreMatch.matchedReason
        usedFields = coreMatch.usedFields.map(SemanticSearchInputFieldSnapshot.init(coreField:))
        route = SemanticSearchRouteSnapshot(coreRoute: coreMatch.route)
        alsoMatchedNormalSearch = coreMatch.alsoMatchedNormalSearch
        callLogID = coreMatch.callLogId
        privacyRuleID = coreMatch.privacyRuleId
    }
}

extension SemanticNormalSearchMatchSnapshot {
    init(coreMatch: SemanticNormalSearchMatch, file: FileEntrySnapshot) {
        result = SearchFileResultSnapshot(coreResult: coreMatch.result, file: file)
        dedupedBySemantic = coreMatch.dedupedBySemantic
    }
}

extension SemanticIndexBuildReportSnapshot {
    init(coreReport: SemanticIndexBuildReport) {
        status = SemanticIndexStatusSnapshot(coreStatus: coreReport.status)
        route = coreReport.route.map(SemanticSearchRouteSnapshot.init(coreRoute:))
        totalCount = coreReport.totalCount
        processedCount = coreReport.processedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        privacySkippedCount = coreReport.privacySkippedCount
        providerName = coreReport.providerName
        callLogID = coreReport.callLogId
        fallbackReason = coreReport.fallbackReason.map(SemanticSearchFallbackReasonSnapshot.init(coreReason:))
        message = coreReport.message
    }
}

extension SemanticIndexStatusSnapshot {
    init(coreStatus: SemanticIndexStatus) {
        switch coreStatus {
        case .ready: self = .ready
        case .notReady: self = .notReady
        case .building: self = .building
        case .paused: self = .paused
        case .canceled: self = .canceled
        case .failed: self = .failed
        case .partial: self = .partial
        }
    }

    var displayName: String {
        switch self {
        case .ready: "Ready"
        case .notReady: "Not ready"
        case .building: "Building"
        case .paused: "Paused"
        case .canceled: "Canceled"
        case .failed: "Failed"
        case .partial: "Partial"
        }
    }
}

private extension SemanticSearchRouteSnapshot {
    init(coreRoute: SemanticSearchRoute) {
        switch coreRoute {
        case .local: self = .local
        case .remote: self = .remote
        }
    }
}

private extension SemanticSearchInputFieldSnapshot {
    init(coreField: SemanticSearchInputField) {
        switch coreField {
        case .fileName: self = .fileName
        case .repoRelativePath: self = .repoRelativePath
        case .category: self = .category
        case .noteSummary: self = .noteSummary
        case .aiSummary: self = .aiSummary
        case .extractedTextExcerpt: self = .extractedTextExcerpt
        }
    }
}

private extension SemanticSearchFallbackReasonSnapshot {
    init(coreReason: SemanticSearchFallbackReason) {
        switch coreReason {
        case .aiDisabled: self = .aiDisabled
        case .featureDisabled: self = .featureDisabled
        case .providerUnavailable: self = .providerUnavailable
        case .privacyRule: self = .privacyRule
        case .semanticIndexNotReady: self = .semanticIndexNotReady
        case .callLogUnavailable: self = .callLogUnavailable
        case .noEligibleInput: self = .noEligibleInput
        case .normalSearchUnavailable: self = .normalSearchUnavailable
        case .rateLimited: self = .rateLimited
        case .timeout: self = .timeout
        }
    }
}
