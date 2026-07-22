import Foundation

enum SavedSearchResultCountState: Equatable {
    case loading
    case loaded(Int64)
    case failed

    var summary: String {
        switch self {
        case .loading:
            L10n.string("Counting results...")
        case let .loaded(count):
            L10n.plural("common.fileCount", count: count)
        case .failed:
            L10n.string("Result count unavailable")
        }
    }

    var emptyResultWarning: String? {
        guard case .loaded(0) = self else { return nil }
        return L10n.string("This Smart List is currently empty.")
    }
}

struct SavedSearchSheetModel {
    static let icons = ["magnifyingglass", "doc.text.magnifyingglass", "folder"]

    var request: SearchQueryRequestSnapshot
    var resultCountState: SavedSearchResultCountState
    var name: String
    var icon = "magnifyingglass"
    var pinned = true
    var existingNames: Set<String> = []
    var isSaving = false
    var saveFailure: CoreErrorMappingSnapshot?

    init(request: SearchQueryRequestSnapshot, resultCountState: SavedSearchResultCountState) {
        self.request = request
        self.resultCountState = resultCountState
        name = Self.defaultName(for: request)
    }

    init(request: SearchQueryRequestSnapshot, resultCount: Int64?) {
        self.init(
            request: request,
            resultCountState: resultCount.map(SavedSearchResultCountState.loaded) ?? .loading
        )
    }

    var validationMessage: String? {
        let trimmed = trimmedName
        if trimmed.isEmpty { return L10n.string("Name is required.") }
        if trimmed.count > 64 { return L10n.string("Name must be 64 characters or fewer.") }
        if existingNames.contains(trimmed.lowercased()) {
            return L10n.format("A Smart List named \"%@\" already exists.", trimmed)
        }
        return nil
    }

    var canSave: Bool {
        validationMessage == nil && !isSaving
    }

    var primaryActionTitle: String {
        isSaving ? L10n.string("Saving...") : L10n.string("Save")
    }

    var createRequest: CreateSavedSearchRequestSnapshot {
        CreateSavedSearchRequestSnapshot(
            name: trimmedName,
            query: SavedSearchQuerySnapshot(request: request),
            icon: icon,
            color: nil,
            pinned: pinned
        )
    }

    var querySummary: String {
        request.query.isEmpty ? L10n.string("Filtered search") : request.query
    }

    var filterSummary: String {
        request.filters.isEmpty
            ? L10n.string("None")
            : L10n.format("%d active", request.filters.activeFilterCount)
    }

    var resultCountSummary: String {
        resultCountState.summary
    }

    var emptyResultWarning: String? {
        resultCountState.emptyResultWarning
    }

    var showsRetry: Bool {
        saveFailure != nil && !isSaving
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultName(for request: SearchQueryRequestSnapshot) -> String {
        let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed.prefix(64).description }
        return request.filters.isEmpty ? L10n.string("Saved Search") : L10n.string("Filtered Search")
    }
}

struct SmartListSidebarRowStatus: Equatable {
    var badgeText: String
    var badgeAccessibilityText: String
    var warningMessage: String?
    var pinned: Bool

    var accessibilityValue: String {
        [
            badgeAccessibilityText,
            pinned ? L10n.string("Pinned") : L10n.string("Not pinned"),
            warningMessage.map { L10n.format("warning: %@", $0) }
        ].compactMap { $0 }.joined(separator: ", ")
    }

    static func make(
        savedSearch: SavedSearchSnapshot?,
        isCurrent: Bool,
        searchState: MainSearchState
    ) -> SmartListSidebarRowStatus {
        guard let savedSearch else {
            return make(
                "--",
                L10n.string("Result count unavailable"),
                L10n.string("Smart List metadata unavailable."),
                false
            )
        }
        let pinned = savedSearch.pinned
        guard isCurrent else { return make(L10n.string("Ready"), L10n.string("Ready"), nil, pinned) }
        switch searchState {
        case .idle:
            return make(L10n.string("Ready"), L10n.string("Ready"), nil, pinned)
        case .loading:
            return make("...", L10n.string("Counting results"), nil, pinned)
        case let .failed(_, error):
            return make("--", L10n.string("Result count unavailable"), error.userMessage, pinned)
        case let .loaded(_, page):
            return loaded(page, pinned: pinned)
        }
    }

    private static func loaded(_ page: SearchResultPageSnapshot, pinned: Bool) -> SmartListSidebarRowStatus {
        if let diagnostic = page.diagnostics.first(where: \.isError) {
            return make(L10n.string("Invalid query"), L10n.string("Invalid query"), diagnostic.message, pinned)
        }
        switch page.indexStatus {
        case .ready:
            let resultText = page.totalCount == 1
                ? L10n.string("1 result")
                : L10n.format("%d results", page.totalCount)
            return make("\(page.totalCount)", resultText, nil, pinned)
        case .indexing:
            return make("...", L10n.string("Counting results"), nil, pinned)
        case .unavailable:
            return make(
                "--",
                L10n.string("Result count unavailable"),
                L10n.string("Search index unavailable."),
                pinned
            )
        }
    }

    private static func make(
        _ badgeText: String,
        _ badgeAccessibilityText: String,
        _ warningMessage: String?,
        _ pinned: Bool
    ) -> SmartListSidebarRowStatus {
        SmartListSidebarRowStatus(
            badgeText: badgeText,
            badgeAccessibilityText: badgeAccessibilityText,
            warningMessage: warningMessage,
            pinned: pinned
        )
    }
}

enum SmartListManagementMode: Equatable {
    case rename
    case duplicate
    case editQuery
    case delete

    var title: String {
        switch self {
        case .rename:
            L10n.string("Rename Smart List")
        case .duplicate:
            L10n.string("Duplicate Smart List")
        case .editQuery:
            L10n.string("Edit Smart List")
        case .delete:
            L10n.string("Delete Smart List")
        }
    }
}

struct SmartListManagementRoute: Identifiable, Equatable {
    var mode: SmartListManagementMode
    var savedSearch: SavedSearchSnapshot
    var draftFilters: SearchFilterStateSnapshot?

    var id: String {
        "\(mode)-\(savedSearch.id)"
    }
}

struct SmartListEditorModel {
    static var deleteSafetyMessage: String {
        L10n.string("This only removes the Smart List. Files will not be deleted or moved.")
    }

    var mode: SmartListManagementMode
    var original: SavedSearchSnapshot
    var name: String
    var query: String
    var scope: SearchScopeSnapshot
    var filters: SearchFilterStateSnapshot
    var sort: SearchSortSnapshot
    var pinned: Bool
    var existingNames: Set<String>
    var resultCountState: SavedSearchResultCountState
    var queryDiagnostic: SearchQueryDiagnosticSnapshot?
    var validatedQueryDiagnosticTaskKey: String?
    var isCheckingQuery = false
    var isSaving = false
    var failure: CoreErrorMappingSnapshot?

    init(
        mode: SmartListManagementMode,
        savedSearch: SavedSearchSnapshot,
        existingNames: Set<String>,
        resultCountState: SavedSearchResultCountState,
        draftFilters: SearchFilterStateSnapshot? = nil
    ) {
        self.mode = mode
        original = savedSearch
        name = mode == .duplicate ? Self.copyName(for: savedSearch.name) : savedSearch.name
        query = savedSearch.query.query
        scope = savedSearch.query.scope
        filters = draftFilters ?? savedSearch.query.filter
        sort = savedSearch.query.sort
        pinned = mode == .duplicate ? false : savedSearch.pinned
        self.existingNames = existingNames
        self.resultCountState = resultCountState
    }

    var validationMessage: String? {
        guard mode != .delete else { return nil }
        let trimmed = trimmedName
        if trimmed.isEmpty { return L10n.string("Name is required.") }
        if trimmed.count > 64 { return L10n.string("Name must be 64 characters or fewer.") }
        if isDuplicate(trimmed) { return L10n.format("A Smart List named \"%@\" already exists.", trimmed) }
        if mode == .editQuery, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, filters.isEmpty {
            return L10n.string("Query or filters are required.")
        }
        if mode == .editQuery, isQueryDiagnosticCurrent, queryDiagnostic?.isError == true {
            return L10n.string("Fix query syntax before saving changes.")
        }
        return nil
    }

    var canSubmit: Bool {
        validationMessage == nil && !isSaving && !isCheckingQuery && isQueryDiagnosticCurrent
    }

    var primaryActionTitle: String {
        if isSaving { return savingTitle }
        switch mode {
        case .rename:
            return L10n.string("Save")
        case .editQuery:
            return L10n.string("Save changes")
        case .duplicate:
            return L10n.string("Create")
        case .delete:
            return L10n.string("Delete Smart List")
        }
    }

    var showsRetry: Bool {
        failure != nil && !isSaving
    }

    var requestSnapshot: SavedSearchQuerySnapshot {
        SavedSearchQuerySnapshot(request: request)
    }

    var createRequest: CreateSavedSearchRequestSnapshot {
        CreateSavedSearchRequestSnapshot(
            name: trimmedName,
            query: requestSnapshot,
            icon: original.icon,
            color: original.color,
            pinned: pinned
        )
    }

    var updateRequest: UpdateSavedSearchRequestSnapshot {
        UpdateSavedSearchRequestSnapshot(
            id: original.id,
            name: trimmedName,
            query: requestSnapshot,
            icon: original.icon,
            color: original.color,
            pinned: pinned
        )
    }

    var filterSummary: String {
        filters.isEmpty ? L10n.string("None") : L10n.format("%d active", filters.activeFilterCount)
    }

    var resultCountSummary: String {
        resultCountState.summary
    }

    var queryDiagnosticRequest: SearchQueryRequestSnapshot {
        request
    }

    var queryDiagnosticTaskKey: String {
        [
            mode == .editQuery ? "edit" : "skip",
            query.trimmingCharacters(in: .whitespacesAndNewlines),
            scope.rawValue,
            filters.taskKey,
            sort.rawValue
        ].joined(separator: "|")
    }

    mutating func clearQueryDiagnostic() {
        queryDiagnostic = nil
        validatedQueryDiagnosticTaskKey = nil
    }

    mutating func applyQueryDiagnosticPage(_ page: SearchResultPageSnapshot) {
        queryDiagnostic = page.diagnostics.first(where: \.isError)
        resultCountState = .loaded(page.totalCount)
        validatedQueryDiagnosticTaskKey = queryDiagnosticTaskKey
    }

    mutating func markQueryDiagnosticUnavailable() {
        resultCountState = .failed
        validatedQueryDiagnosticTaskKey = queryDiagnosticTaskKey
    }

    private var request: SearchQueryRequestSnapshot {
        SearchQueryRequestSnapshot(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            scope: scope,
            currentPath: scope == .current ? original.query.currentPath : nil,
            category: scope == .current ? original.query.category : nil,
            filters: filters,
            sort: sort,
            limit: 50,
            offset: 0
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var savingTitle: String {
        switch mode {
        case .delete:
            L10n.string("Deleting...")
        case .duplicate:
            L10n.string("Creating...")
        case .rename, .editQuery:
            L10n.string("Saving...")
        }
    }

    private var isQueryDiagnosticCurrent: Bool {
        mode != .editQuery || validatedQueryDiagnosticTaskKey == queryDiagnosticTaskKey
    }

    private func isDuplicate(_ trimmed: String) -> Bool {
        let normalized = trimmed.lowercased()
        if mode == .duplicate { return existingNames.contains(normalized) }
        return normalized != original.name.lowercased() && existingNames.contains(normalized)
    }

    private static func copyName(for name: String) -> String {
        L10n.format("%@ Copy", name)
    }
}
