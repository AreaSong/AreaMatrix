import SwiftUI

struct SmartListManagementSheet: View {
    let route: SmartListManagementRoute
    let repoPath: String
    let savedSearches: [SavedSearchSnapshot]
    let resultCountState: SavedSearchResultCountState
    let savedSearchStore: any CoreSavedSearchCRUD
    let searchQuerying: any CoreSearchQuerying
    let errorMapper: any CoreErrorMapping
    let onCancel: () -> Void
    let onSaved: (SavedSearchSnapshot) -> Void
    let onDeleted: (SavedSearchSnapshot) -> Void
    let onEditFilters: (SavedSearchSnapshot, SearchFilterStateSnapshot) -> Void
    @State var model: SmartListEditorModel

    init(
        route: SmartListManagementRoute,
        repoPath: String,
        savedSearches: [SavedSearchSnapshot],
        resultCountState: SavedSearchResultCountState = .loading,
        savedSearchStore: any CoreSavedSearchCRUD,
        searchQuerying: any CoreSearchQuerying,
        errorMapper: any CoreErrorMapping,
        onCancel: @escaping () -> Void,
        onSaved: @escaping (SavedSearchSnapshot) -> Void,
        onDeleted: @escaping (SavedSearchSnapshot) -> Void,
        onEditFilters: @escaping (SavedSearchSnapshot, SearchFilterStateSnapshot) -> Void
    ) {
        self.route = route
        self.repoPath = repoPath
        self.savedSearches = savedSearches
        self.resultCountState = resultCountState
        self.savedSearchStore = savedSearchStore
        self.searchQuerying = searchQuerying
        self.errorMapper = errorMapper
        self.onCancel = onCancel
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onEditFilters = onEditFilters
        _model = State(initialValue: SmartListEditorModel(
            mode: route.mode,
            savedSearch: route.savedSearch,
            existingNames: Set(savedSearches.map { $0.name.lowercased() }),
            resultCountState: resultCountState,
            draftFilters: route.draftFilters
        ))
    }

    var body: some View {
        MainFileActionSheetContainer(title: route.mode.title, pageID: "smart-list-management", content: { content })
            .accessibilityIdentifier("smart-list-management-smart-list-management")
            .task(id: model.queryDiagnosticTaskKey) {
                await refreshQueryDiagnostic()
            }
    }

    @MainActor
    func submit() async {
        guard model.canSubmit else { return }
        model.isSaving = true
        model.failure = nil
        do {
            switch model.mode {
            case .rename, .editQuery:
                let request = model.updateRequest
                let saved = try await savedSearchStore.updateSavedSearch(repoPath: repoPath, request: request)
                model.isSaving = false
                onSaved(saved)
            case .duplicate:
                let request = model.createRequest
                let saved = try await savedSearchStore.createSavedSearch(repoPath: repoPath, request: request)
                model.isSaving = false
                onSaved(saved)
            case .delete:
                try await savedSearchStore.deleteSavedSearch(repoPath: repoPath, savedSearchID: model.original.id)
                model.isSaving = false
                onDeleted(model.original)
            }
        } catch {
            model.isSaving = false
            model.failure = await errorMapper.mapError(error)
        }
    }

    @MainActor
    private func refreshQueryDiagnostic() async {
        guard model.mode == .editQuery else { return }
        model.clearQueryDiagnostic()
        let request = model.queryDiagnosticRequest
        guard !request.query.isEmpty || !request.filters.isEmpty else { return }

        model.isCheckingQuery = true
        defer { model.isCheckingQuery = false }
        do {
            let page = try await searchQuerying.searchFiles(repoPath: repoPath, request: request)
            guard !Task.isCancelled else { return }
            model.applyQueryDiagnosticPage(page)
        } catch {
            guard !Task.isCancelled else { return }
            model.markQueryDiagnosticUnavailable()
        }
    }
}
