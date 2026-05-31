import Foundation

enum SemanticSearchResultGroup: Equatable {
    case semantic
    case normal
}

struct SemanticSearchRowPresentation: Identifiable, Equatable {
    var id: Int64
    var file: FileEntrySnapshot
    var group: SemanticSearchResultGroup
    var matchSource: String
    var relevance: String
    var matchedReason: String
    var whyThisMatched: String
    var routeLabel: String?
    var alsoMatchedNormalSearch: Bool
    var isFoldedDuplicate: Bool

    var categoryPath: String {
        let pathPrefix = file.path.split(separator: "/").dropLast().joined(separator: "/")
        return pathPrefix.isEmpty ? file.category : pathPrefix
    }

    var modified: String {
        SemanticSearchRowPresentation.dateFormatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(file.updatedAt))
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct SemanticSearchDetailPresentation: Equatable {
    var title: String
    var relevance: String
    var matchedReason: String
    var whyThisMatched: String
    var routeLabel: String
    var alsoMatchedNormalSearch: Bool
}

struct SemanticSearchPagingState: Equatable {
    var loadingGroup: SemanticSearchResultGroup?
    var semanticError: CoreErrorMappingSnapshot?
    var normalError: CoreErrorMappingSnapshot?

    init(
        loadingGroup: SemanticSearchResultGroup? = nil,
        semanticError: CoreErrorMappingSnapshot? = nil,
        normalError: CoreErrorMappingSnapshot? = nil
    ) {
        self.loadingGroup = loadingGroup
        self.semanticError = semanticError
        self.normalError = normalError
    }

    var isLoadingSemantic: Bool {
        loadingGroup == .semantic
    }

    var isLoadingNormal: Bool {
        loadingGroup == .normal
    }

    static let idle = SemanticSearchPagingState()
}

extension SemanticSearchResultPageSnapshot {
    var hasMoreSemanticMatches: Bool {
        Int64(semanticMatches.count) < semanticTotalCount
    }

    var hasMoreNormalMatches: Bool {
        Int64(normalMatches.count) < normalTotalCount
    }

    func semanticRows() -> [SemanticSearchRowPresentation] {
        semanticMatches.map(SemanticSearchRowPresentation.init(match:))
    }

    func normalRows(showFoldedDuplicates: Bool) -> [SemanticSearchRowPresentation] {
        normalMatches
            .filter { showFoldedDuplicates || !$0.dedupedBySemantic }
            .map(SemanticSearchRowPresentation.init(match:))
    }

    func detailPresentation(for fileID: Int64) -> SemanticSearchDetailPresentation? {
        guard let match = semanticMatches.first(where: { $0.result.file.id == fileID }) else { return nil }
        return SemanticSearchDetailPresentation(
            title: "From semantic search",
            relevance: String(format: "%.2f", match.relevance),
            matchedReason: match.matchedReason,
            whyThisMatched: match.semanticExplanationText,
            routeLabel: match.route.rawValue,
            alsoMatchedNormalSearch: match.alsoMatchedNormalSearch
        )
    }

    func mergingPage(_ next: SemanticSearchResultPageSnapshot, group: SemanticSearchResultGroup) -> SemanticSearchResultPageSnapshot {
        var merged = self
        merged.semanticTotalCount = next.semanticTotalCount
        merged.normalTotalCount = next.normalTotalCount
        merged.dedupedNormalCount = next.dedupedNormalCount
        merged.indexStatus = next.indexStatus
        merged.route = next.route
        merged.fallbackReason = next.fallbackReason
        merged.fallbackMessage = next.fallbackMessage
        merged.callLogID = next.callLogID
        merged.privacyRuleID = next.privacyRuleID
        merged.lowConfidence = next.lowConfidence
        switch group {
        case .semantic:
            merged.semanticMatches.append(contentsOf: next.semanticMatches)
        case .normal:
            merged.normalMatches.append(contentsOf: next.normalMatches)
        }
        return merged
    }
}

extension SearchResultPageSnapshot {
    func replacingSemanticPage(_ semanticPage: SemanticSearchResultPageSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: semanticPage.query,
            totalCount: semanticPage.visibleTotalCount,
            results: semanticPage.visibleResults,
            diagnostics: diagnostics,
            indexStatus: SearchIndexStatusSnapshot(semanticStatus: semanticPage.indexStatus),
            semanticPage: semanticPage
        )
    }
}

extension SemanticSearchRowPresentation {
    init(match: SemanticSearchMatchSnapshot) {
        id = match.result.file.id
        file = match.result.file
        group = .semantic
        matchSource = "Semantic"
        relevance = String(format: "%.2f", match.relevance)
        matchedReason = match.matchedReason
        whyThisMatched = match.semanticExplanationText
        routeLabel = match.route.rawValue
        alsoMatchedNormalSearch = match.alsoMatchedNormalSearch
        isFoldedDuplicate = false
    }

    init(match: SemanticNormalSearchMatchSnapshot) {
        id = match.result.file.id
        file = match.result.file
        group = .normal
        matchSource = "Normal"
        relevance = "-"
        matchedReason = match.normalReasonText
        whyThisMatched = match.normalExplanationText
        routeLabel = nil
        alsoMatchedNormalSearch = false
        isFoldedDuplicate = match.dedupedBySemantic
    }
}

private extension SemanticSearchMatchSnapshot {
    var semanticExplanationText: String {
        let fields = usedFields.map(\.rawValue).joined(separator: ", ")
        let route = "Route: \(self.route.rawValue)"
        let reason = matchedReason.isEmpty ? "Semantic result matched the query." : matchedReason
        let duplicate = alsoMatchedNormalSearch ? " Also matched normal search." : ""
        return "\(reason) Fields: \(fields). \(route).\(duplicate)"
    }
}

private extension SemanticNormalSearchMatchSnapshot {
    var normalReasonText: String {
        if let noteSnippet = result.noteSnippet, !noteSnippet.isEmpty {
            return "Note: \(noteSnippet)"
        }
        guard let match = result.matches.first else { return "Stage 2 normal search match" }
        return "\(match.kindDisplayName): \(match.fieldDisplayName) - \(match.snippet)"
    }

    var normalExplanationText: String {
        dedupedBySemantic ? "Folded because the same file is already shown in Semantic matches." : normalReasonText
    }
}
