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

    var displayName: String {
        L10n.resolve(displayNameMessage)
    }

    var displayNameMessage: LocalizedMessage {
        switch self {
        case .local: L10n.message("Local")
        case .remote: L10n.message("Remote")
        }
    }
}

enum SemanticSearchInputFieldSnapshot: String, Equatable {
    case fileName = "File name"
    case repoRelativePath = "Path"
    case category = "Category"
    case noteSummary = "Note summary"
    case aiSummary = "AI summary"
    case extractedTextExcerpt = "Extracted text"

    var displayName: String {
        L10n.resolve(displayNameMessage)
    }

    var displayNameMessage: LocalizedMessage {
        switch self {
        case .fileName: L10n.message("File name")
        case .repoRelativePath: L10n.message("Path")
        case .category: L10n.message("Category")
        case .noteSummary: L10n.message("Note summary")
        case .aiSummary: L10n.message("AI summary")
        case .extractedTextExcerpt: L10n.message("Extracted text")
        }
    }
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

    var displayName: String {
        switch self {
        case .aiDisabled: L10n.string("AI disabled")
        case .featureDisabled: L10n.string("Semantic search disabled")
        case .providerUnavailable: L10n.string("Provider unavailable")
        case .privacyRule: L10n.string("Privacy rule")
        case .semanticIndexNotReady: L10n.string("Semantic index not ready")
        case .callLogUnavailable: L10n.string("Call log unavailable")
        case .noEligibleInput: L10n.string("No eligible input")
        case .normalSearchUnavailable: L10n.string("Normal search unavailable")
        case .rateLimited: L10n.string("Rate limited")
        case .timeout: L10n.string("Timeout")
        }
    }
}

extension StorageMode {
    var fileListDisplayName: String {
        switch self {
        case .moved:
            L10n.string("Moved")
        case .copied:
            L10n.string("Copied")
        case .indexed:
            L10n.string("Indexed")
        }
    }
}

extension SearchMatchField {
    var displayName: String {
        switch self {
        case .name:
            L10n.string("Name")
        case .path:
            L10n.string("Path")
        case .note:
            L10n.string("Note")
        case .category:
            L10n.string("Category")
        case .changeLog:
            L10n.string("Change log")
        }
    }
}

extension SearchMatchKind {
    var displayName: String {
        switch self {
        case .exact:
            L10n.string("Exact match")
        case .fuzzy:
            L10n.string("Fuzzy match")
        case .pinyinInitials:
            L10n.string("Pinyin initials")
        }
    }
}

extension SearchDiagnosticKind {
    var displayName: String {
        switch self {
        case .unclosedQuote: L10n.string("Unclosed quote")
        case .unknownField: L10n.string("Unknown field")
        case .invalidDate: L10n.string("Invalid date")
        case .unbalancedParentheses: L10n.string("Unbalanced parentheses")
        case .invalidOperator: L10n.string("Invalid operator")
        }
    }
}

extension SearchDiagnosticSeverity {
    var displayName: String {
        switch self {
        case .info: L10n.string("Info")
        case .warning: L10n.string("Warning")
        case .error: L10n.string("Error")
        }
    }
}

extension FileOrigin {
    var fileListDisplayName: String {
        switch self {
        case .imported:
            L10n.string("Imported")
        case .adopted:
            L10n.string("Adopted")
        case .external:
            L10n.string("External")
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
        case .ready: L10n.string("Ready")
        case .notReady: L10n.string("Not ready")
        case .building: L10n.string("Building")
        case .paused: L10n.string("Paused")
        case .canceled: L10n.string("Canceled")
        case .failed: L10n.string("Failed")
        case .partial: L10n.string("Partial")
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
