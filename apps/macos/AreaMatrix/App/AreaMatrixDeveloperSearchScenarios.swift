import SwiftUI

#if DEBUG
@MainActor
struct DeveloperSearchScenarioView: View {
    let scenario: AreaMatrixDeveloperScenario

    var body: some View {
        switch scenario {
        case .searchQueryError:
            QueryErrorRouteView(
                request: DeveloperSearchScenarioFixture.queryErrorRequest,
                diagnostic: DeveloperSearchScenarioFixture.queryDiagnostic,
                onApplySuggestion: { _ in },
                onClear: {}
            )
        case .searchSavedSearch:
            DeveloperSavedSearchScenario()
        case .searchEmpty:
            SearchEmptyRouteView(
                request: DeveloperSearchScenarioFixture.filteredRequest,
                indexStatus: .ready,
                onClearSearch: {},
                onClearFilters: {},
                onRemoveFilter: { _ in },
                onSearchAllFileTypes: {}
            )
        case .searchIndexStatus:
            SearchIndexingStatusRouteView(
                request: DeveloperSearchScenarioFixture.filteredRequest,
                indexStatus: .unavailable,
                onRetry: {},
                onClose: {}
            )
        case .searchSemanticResults:
            DeveloperSemanticSearchScenario()
        case .searchSmartList:
            DeveloperSmartListScenario()
        default:
            EmptyView()
        }
    }
}

@MainActor
private struct DeveloperSavedSearchScenario: View {
    private let core = DeveloperSearchCoreFixture()

    var body: some View {
        SavedSearchSheetRouteView(
            request: DeveloperSearchScenarioFixture.filteredRequest,
            repoPath: DeveloperSearchScenarioFixture.repoPath,
            resultCountState: .loaded(12),
            savedSearchStore: core,
            errorMapper: CoreErrorSnapshotMapper(),
            onCancel: {}
        )
        .background(.background)
    }
}

@MainActor
private struct DeveloperSemanticSearchScenario: View {
    @State private var selectedFileIDs = Set<Int64>()
    @State private var showFoldedDuplicates = false

    var body: some View {
        SemanticSearchResultsView(
            page: DeveloperSearchScenarioFixture.semanticPage,
            selectedFileIDs: $selectedFileIDs,
            showFoldedDuplicates: showFoldedDuplicates,
            pagingState: .idle,
            onToggleDuplicates: { showFoldedDuplicates.toggle() },
            onLoadMoreSemantic: {},
            onLoadMoreNormal: {},
            onRetrySemanticPage: {},
            onRetryNormalPage: {},
            contextMenu: { _ in AnyView(EmptyView()) },
            onPrimaryAction: { _ in }
        )
        .padding(20)
        .background(.background)
    }
}

@MainActor
private struct DeveloperSmartListScenario: View {
    private let core = DeveloperSearchCoreFixture()
    private let savedSearch = DeveloperSearchScenarioFixture.savedSearch

    var body: some View {
        SmartListManagementSheet(
            route: SmartListManagementRoute(
                mode: .editQuery,
                savedSearch: savedSearch,
                draftFilters: nil
            ),
            repoPath: DeveloperSearchScenarioFixture.repoPath,
            savedSearches: [savedSearch],
            resultCountState: .loaded(12),
            savedSearchStore: core,
            searchQuerying: core,
            errorMapper: CoreErrorSnapshotMapper(),
            onCancel: {},
            onSaved: { _ in },
            onDeleted: { _ in },
            onEditFilters: { _, _ in }
        )
        .background(.background)
    }
}
#endif
