import Foundation

enum SemanticSearchResultGroup: Equatable {
    case semantic
    case normal
}

struct SemanticSearchRowPresentation: Identifiable, Equatable {
    var id: Int64
    var file: FileEntrySnapshot
    var group: SemanticSearchResultGroup
    var matchSource: LocalizedMessage
    var relevance: String
    var matchedReason: String
    var whyThisMatched: SemanticSearchExplanation
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
    var title: LocalizedMessage
    var relevance: String
    var matchedReason: String
    var whyThisMatched: SemanticSearchExplanation
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
            title: L10n.message("From semantic search"),
            relevance: String(format: "%.2f", match.relevance),
            matchedReason: match.matchedReason,
            whyThisMatched: .semantic(match),
            routeLabel: match.route.displayName,
            alsoMatchedNormalSearch: match.alsoMatchedNormalSearch
        )
    }

    func mergingPage(
        _ next: SemanticSearchResultPageSnapshot,
        group: SemanticSearchResultGroup
    ) -> SemanticSearchResultPageSnapshot {
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
        matchSource = L10n.message("Semantic")
        relevance = String(format: "%.2f", match.relevance)
        matchedReason = match.matchedReason
        whyThisMatched = .semantic(match)
        routeLabel = match.route.displayName
        alsoMatchedNormalSearch = match.alsoMatchedNormalSearch
        isFoldedDuplicate = false
    }

    init(match: SemanticNormalSearchMatchSnapshot) {
        id = match.result.file.id
        file = match.result.file
        group = .normal
        matchSource = L10n.message("Normal")
        relevance = "-"
        matchedReason = match.result.noteSnippet ?? match.result.matches.first?.snippet ?? ""
        whyThisMatched = .normal(match)
        routeLabel = nil
        alsoMatchedNormalSearch = false
        isFoldedDuplicate = match.dedupedBySemantic
    }
}

enum SemanticSearchExplanation: Equatable {
    case semantic(SemanticSearchMatchSnapshot)
    case normal(SemanticNormalSearchMatchSnapshot)

    @MainActor
    func resolve(using localizer: AppLocalizer) -> String {
        switch self {
        case let .semantic(match):
            let fields = match.usedFields.map { localizer.resolve($0.displayNameMessage) }.joined(separator: ", ")
            let route = localizer.format(
                "semanticSearch.route",
                arguments: [.string(localizer.resolve(match.route.displayNameMessage))]
            )
            let reason = match.matchedReason.isEmpty
                ? localizer.string("Semantic result matched the query.")
                : match.matchedReason
            let duplicate = match.alsoMatchedNormalSearch
                ? localizer.string(" Also matched normal search.")
                : ""
            return localizer.format(
                "semanticSearch.explanation",
                arguments: [.string(reason), .string(fields), .string(route), .string(duplicate)]
            )
        case let .normal(match):
            if match.dedupedBySemantic {
                return localizer.string("Folded because the same file is already shown in Semantic matches.")
            }
            if let noteSnippet = match.result.noteSnippet, !noteSnippet.isEmpty {
                return localizer.format("semanticSearch.noteSnippet", arguments: [.string(noteSnippet)])
            }
            guard let resultMatch = match.result.matches.first else {
                return localizer.string("Normal search match")
            }
            return "\(resultMatch.kindDisplayName): \(resultMatch.fieldDisplayName) - \(resultMatch.snippet)"
        }
    }
}
