import SwiftUI

struct SearchRouteStatusView: View {
    let destination: MainSearchDestination
    let indexStatus: SearchIndexStatusSnapshot?
    let onClearSearchQuery: () -> Void
    let onClearFilters: () -> Void
    let onRemoveFilter: (SearchFilterChipKind) -> Void
    let onSearchAllFileTypes: () -> Void
    let onApplyQuerySuggestion: (String) -> Void
    let onClearSearch: () -> Void

    var body: some View {
        switch destination {
        case let .searchEmpty(request):
            SearchEmptyRouteView(
                request: request,
                indexStatus: indexStatus,
                onClearSearch: onClearSearchQuery,
                onClearFilters: onClearFilters,
                onRemoveFilter: onRemoveFilter,
                onSearchAllFileTypes: onSearchAllFileTypes
            )
        case let .queryError(request, diagnostic):
            QueryErrorRouteView(
                request: request,
                diagnostic: diagnostic,
                onApplySuggestion: onApplyQuerySuggestion,
                onClear: onClearSearch
            )
        case .savedSearchSheet, .indexingStatus, .commandPalette, .classifierRuleEditor:
            EmptyView()
        }
    }
}
