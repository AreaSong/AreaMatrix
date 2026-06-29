import SwiftUI

extension MainRepositoryContentView {
    @ViewBuilder
    func searchRouteStatus(_ destination: MainSearchDestination) -> some View {
        switch destination {
        case let .searchEmpty(request):
            SearchEmptyRouteView(
                request: request,
                indexStatus: fileListModel.searchState.indexStatus,
                onClearSearch: clearSearchQuery,
                onClearFilters: clearSearchFiltersFromEmptyState,
                onRemoveFilter: removeSearchFilterFromEmptyState,
                onSearchAllFileTypes: searchAllFileTypesFromEmptyState
            )
        case let .queryError(request, diagnostic):
            QueryErrorRouteView(
                request: request,
                diagnostic: diagnostic,
                onApplySuggestion: applyQuerySuggestion,
                onClear: clearSearch
            )
        case .savedSearchSheet, .indexingStatus, .commandPalette, .classifierRuleEditor:
            EmptyView()
        }
    }
}
