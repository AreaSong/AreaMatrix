import Foundation

enum SearchDateFilterPreset { case any, last7Days, last30Days, thisYear }

enum SearchFilterDateField {
    case imported
    case modified

    func summary(in filters: SearchFilterStateSnapshot) -> String {
        let after = afterTimestamp(in: filters)
        let before = beforeTimestamp(in: filters)
        if let after, let before {
            return "\(dateText(after)) - \(dateText(before))"
        }
        return after.map { L10n.format("search.sinceDate", dateText($0)) } ?? L10n.string("Any")
    }

    func hasCustomRange(in filters: SearchFilterStateSnapshot) -> Bool {
        afterTimestamp(in: filters) != nil && beforeTimestamp(in: filters) != nil
    }

    func afterTimestamp(in filters: SearchFilterStateSnapshot) -> Int64? {
        switch self {
        case .imported:
            filters.importedAfter
        case .modified:
            filters.modifiedAfter
        }
    }

    func beforeTimestamp(in filters: SearchFilterStateSnapshot) -> Int64? {
        switch self {
        case .imported:
            filters.importedBefore
        case .modified:
            filters.modifiedBefore
        }
    }

    func applying(
        after: Int64?,
        before: Int64? = nil,
        to filters: SearchFilterStateSnapshot
    ) -> SearchFilterStateSnapshot {
        var updated = filters
        switch self {
        case .imported:
            updated.importedAfter = after
            updated.importedBefore = before
        case .modified:
            updated.modifiedAfter = after
            updated.modifiedBefore = before
        }
        return updated
    }

    func allowedDateRange(from bounds: SearchDateFacetBoundsSnapshot?) -> ClosedRange<Date> {
        let lower = boundTimestamp(from: bounds, oldest: true)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(timeIntervalSince1970: 0)
        let upper = boundTimestamp(from: bounds, oldest: false)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(timeIntervalSince1970: 4_102_444_800)
        return min(lower, upper) ... max(lower, upper)
    }

    func clearing(in filters: SearchFilterStateSnapshot) -> SearchFilterStateSnapshot {
        applying(after: nil, before: nil, to: filters)
    }

    private func boundTimestamp(from bounds: SearchDateFacetBoundsSnapshot?, oldest: Bool) -> Int64? {
        switch (self, oldest) {
        case (.imported, true):
            bounds?.oldestImportedAt
        case (.imported, false):
            bounds?.newestImportedAt
        case (.modified, true):
            bounds?.oldestModifiedAt
        case (.modified, false):
            bounds?.newestModifiedAt
        }
    }

    private func dateText(_ timestamp: Int64) -> String {
        Self.formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum MainSearchState: Equatable {
    case idle
    case loading(request: SearchQueryRequestSnapshot, previousPage: SearchResultPageSnapshot?)
    case loaded(request: SearchQueryRequestSnapshot, page: SearchResultPageSnapshot)
    case failed(request: SearchQueryRequestSnapshot, CoreErrorMappingSnapshot)

    var isActive: Bool {
        request != nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var request: SearchQueryRequestSnapshot? {
        switch self {
        case .idle:
            nil
        case let .loading(request, _), let .loaded(request, _), let .failed(request, _):
            request
        }
    }

    var page: SearchResultPageSnapshot? {
        switch self {
        case let .loaded(_, page):
            page
        case let .loading(_, previousPage):
            previousPage
        case .idle, .failed:
            nil
        }
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        if case let .failed(_, mapping) = self { return mapping }
        return nil
    }

    var indexStatus: SearchIndexStatusSnapshot? {
        page?.indexStatus
    }
}

enum MainSearchFacetsState: Equatable {
    case idle
    case loading(request: SearchFacetRequestSnapshot, previousFacets: SearchFacetsSnapshot?)
    case loaded(request: SearchFacetRequestSnapshot, facets: SearchFacetsSnapshot)
    case failed(request: SearchFacetRequestSnapshot, CoreErrorMappingSnapshot)

    var facets: SearchFacetsSnapshot? {
        switch self {
        case let .loaded(_, facets):
            facets
        case let .loading(_, previousFacets):
            previousFacets
        case .idle, .failed:
            nil
        }
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        if case let .failed(_, mapping) = self { return mapping }
        return nil
    }
}

enum MainSearchDestination: Equatable, Identifiable {
    case savedSearchSheet(SearchQueryRequestSnapshot)
    case searchEmpty(SearchQueryRequestSnapshot)
    case queryError(SearchQueryRequestSnapshot, SearchQueryDiagnosticSnapshot)
    case indexingStatus(SearchQueryRequestSnapshot)
    case commandPalette
    case classifierRuleEditor(context: BatchChangeCategoryReturnContext?)

    var id: String {
        switch self {
        case let .savedSearchSheet(request): "saved-search-\(request.query)"
        case let .searchEmpty(request): "search-empty-\(request.query)"
        case let .queryError(request, diagnostic): "query-error-\(request.query)-\(diagnostic.message)"
        case let .indexingStatus(request): "search-index-status-indexing-\(request.query)"
        case .commandPalette: "command-palette-command-palette"
        case let .classifierRuleEditor(context):
            "classifier-rule-editor-classifier-rule-editor-\(context?.handoff.id ?? "settings")"
        }
    }

    var pageID: String {
        switch self {
        case .savedSearchSheet:
            "saved-search"
        case .searchEmpty:
            "search-empty"
        case .queryError:
            "query-error"
        case .indexingStatus:
            "search-index-status-indexing-status"
        case .commandPalette:
            "command-palette"
        case .classifierRuleEditor: "classifier-rule-editor"
        }
    }

    var isSheetRoute: Bool {
        switch self {
        case .savedSearchSheet, .indexingStatus, .commandPalette, .classifierRuleEditor:
            true
        case .searchEmpty, .queryError:
            false
        }
    }
}

enum MainSearchEntryContext: Equatable {
    case toolbar
    case commandFind
    case smartList(id: Int64, name: String)
    case commandPalette
    case sidebar(String)
}

enum MainSearchExitContext: Equatable {
    case toolbar
    case smartList(id: Int64, name: String)
    case sidebar(String)
    case list
}

struct SmartListFilterDraft: Equatable {
    var id: Int64
    var name: String
    var filters: SearchFilterStateSnapshot

    var activeFilterCount: Int64 {
        filters.activeFilterCount
    }
}
