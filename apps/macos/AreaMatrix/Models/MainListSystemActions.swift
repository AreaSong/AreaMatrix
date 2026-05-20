import Foundation

enum SavedSearchResultCountState: Equatable {
    case loading
    case loaded(Int64)
    case failed

    var summary: String {
        switch self {
        case .loading:
            "Counting results..."
        case let .loaded(count):
            count == 1 ? "1 file" : "\(count) files"
        case .failed:
            "Result count unavailable"
        }
    }

    var emptyResultWarning: String? {
        guard case .loaded(0) = self else { return nil }
        return "This Smart List is currently empty."
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
        if trimmed.isEmpty { return "Name is required." }
        if trimmed.count > 64 { return "Name must be 64 characters or fewer." }
        if existingNames.contains(trimmed.lowercased()) {
            return "A Smart List named \"\(trimmed)\" already exists."
        }
        return nil
    }

    var canSave: Bool {
        validationMessage == nil && !isSaving
    }

    var primaryActionTitle: String {
        isSaving ? "Saving..." : "Save"
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
        request.query.isEmpty ? "Filtered search" : request.query
    }

    var filterSummary: String {
        request.filters.isEmpty ? "None" : "\(request.filters.activeFilterCount) active"
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
        return request.filters.isEmpty ? "Saved Search" : "Filtered Search"
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
            "Rename Smart List"
        case .duplicate:
            "Duplicate Smart List"
        case .editQuery:
            "Edit Smart List"
        case .delete:
            "Delete Smart List"
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
    static let deleteSafetyMessage = "This only removes the Smart List. Files will not be deleted or moved."

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
        if trimmed.isEmpty { return "Name is required." }
        if trimmed.count > 64 { return "Name must be 64 characters or fewer." }
        if isDuplicate(trimmed) { return "A Smart List named \"\(trimmed)\" already exists." }
        if mode == .editQuery, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, filters.isEmpty {
            return "Query or filters are required."
        }
        if mode == .editQuery, isQueryDiagnosticCurrent, queryDiagnostic?.isError == true {
            return "Fix query syntax before saving changes."
        }
        return nil
    }

    var canSubmit: Bool {
        validationMessage == nil && !isSaving && !isCheckingQuery && isQueryDiagnosticCurrent
    }

    var primaryActionTitle: String {
        if isSaving { return savingTitle }
        switch mode {
        case .rename, .editQuery:
            return "Save changes"
        case .duplicate:
            return "Create"
        case .delete:
            return "Delete Smart List"
        }
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
        filters.isEmpty ? "None" : "\(filters.activeFilterCount) active"
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
            "Deleting..."
        case .duplicate:
            "Creating..."
        case .rename, .editQuery:
            "Saving..."
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
        "\(name) Copy"
    }
}

extension OnboardingModel {
    @MainActor
    func openLearnMore() {
        do {
            try helpOpener.openWelcomeHelp()
        } catch {
            toastMessage = "Learn more is unavailable right now."
        }
    }

    @MainActor
    func showMainListFileInFinder(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileRevealer.revealFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = "File cannot be shown in Finder."
        }
    }

    @MainActor
    func openMainListFile(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try fileOpener.openFile(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = "File cannot be opened."
        }
    }

    @MainActor
    func copyMainListPath(opening: RepositoryOpeningResult, relativePath: String) {
        do {
            try pathCopier.copyPath(repoPath: opening.config.repoPath, relativePath: relativePath)
            toastMessage = "Path copied."
            accessibilityAnnouncer.announce("Path copied.")
        } catch {
            toastMessage = "Path cannot be copied."
            accessibilityAnnouncer.announce("Path cannot be copied.")
        }
    }

    @MainActor
    func copyMainListPaths(opening: RepositoryOpeningResult, relativePaths: [String]) {
        do {
            try pathCopier.copyPaths(repoPath: opening.config.repoPath, relativePaths: relativePaths)
            toastMessage = "\(relativePaths.count) paths copied."
            accessibilityAnnouncer.announce("\(relativePaths.count) paths copied.")
        } catch {
            toastMessage = "Paths cannot be copied."
            accessibilityAnnouncer.announce("Paths cannot be copied.")
        }
    }

    @MainActor
    func collectMainListDiagnostics(opening: RepositoryOpeningResult) async {
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: opening.config.repoPath)
            toastMessage = "Diagnostics collected at \(snapshot.snapshotPath)."
        } catch {
            let mapping = await openingFailureMapping(for: error)
            toastMessage = mapping.userMessage
        }
    }
}
