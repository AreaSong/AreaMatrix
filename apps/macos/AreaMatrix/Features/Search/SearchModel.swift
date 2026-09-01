import AreaMatrixFeatureLibrary
import Combine
import Foundation

enum SearchResultApplication {
    case loading
    case loaded([FileEntrySnapshot])
    case failed
    case cleared
}

struct SearchModelDependencies {
    let searchQuerying: any CoreSearchQuerying
    let semanticSearching: any CoreSemanticSearching
    let semanticFallbackReader: any CoreSemanticFallbackStatusReading
    let searchFiltering: any CoreSearchFiltering
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let errorMapper: any CoreErrorMapping
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var state = MainSearchState.idle {
        didSet {
            if !semanticPrivacyGateState.isCurrent(for: state.request) {
                semanticPrivacyGateState = .idle
            }
            if !semanticFallbackState.isCurrent(for: state.request) { semanticFallbackState = .idle }
            if !semanticIndexControlState.isCurrent(for: state.request) { semanticIndexControlState = .idle }
        }
    }

    @Published var semanticIndexBuildState = SemanticIndexBuildState.idle
    @Published var semanticPrivacyGateState = SemanticPrivacyGateState.idle
    @Published var semanticFallbackState = SemanticFallbackState.idle
    @Published var semanticIndexControlState = SemanticIndexBuildControlState.idle
    @Published var semanticPagingState = SemanticSearchPagingState.idle
    @Published var showFoldedSemanticDuplicates = false
    @Published var facetsState = MainSearchFacetsState.idle
    @Published var pendingDestination: MainSearchDestination?
    @Published var lastExitContext: MainSearchExitContext?
    @Published var smartListFilterDraft: SmartListFilterDraft?
    @Published var routingState = MainRepositorySearchRoutingState()
    @Published var savedSearchesBySidebarID: [String: SavedSearchSnapshot] = [:]
    @Published var smartListLoadError: CoreErrorMappingSnapshot?
    var activeSmartListSearch: SavedSearchSnapshot?

    let repoPath: String
    let searchQuerying: any CoreSearchQuerying
    let semanticSearching: any CoreSemanticSearching
    let semanticFallbackReader: any CoreSemanticFallbackStatusReading
    let searchFiltering: any CoreSearchFiltering
    let aiPrivacyRules: any CoreAIPrivacyEvaluating
    let errorMapper: any CoreErrorMapping

    var searchGeneration = 0
    var searchFacetsGeneration = 0
    var semanticIndexBuildGeneration = 0
    var semanticIndexBuildTask: Task<SemanticIndexBuildReportSnapshot, Error>?
    private var resultHandler: (SearchResultApplication) -> Void = { _ in }

    init(repoPath: String, dependencies: SearchModelDependencies) {
        self.repoPath = repoPath
        searchQuerying = dependencies.searchQuerying
        semanticSearching = dependencies.semanticSearching
        semanticFallbackReader = dependencies.semanticFallbackReader
        searchFiltering = dependencies.searchFiltering
        aiPrivacyRules = dependencies.aiPrivacyRules
        errorMapper = dependencies.errorMapper
    }

    func setResultHandler(_ handler: @escaping (SearchResultApplication) -> Void) {
        resultHandler = handler
    }

    func applyResult(_ application: SearchResultApplication) {
        resultHandler(application)
    }

    func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }

    var searchState: MainSearchState {
        get { state }
        set { state = newValue }
    }

    var searchFacetsState: MainSearchFacetsState {
        get { facetsState }
        set { facetsState = newValue }
    }

    var pendingSearchDestination: MainSearchDestination? {
        get { pendingDestination }
        set { pendingDestination = newValue }
    }

    var lastSearchExitContext: MainSearchExitContext? {
        get { lastExitContext }
        set { lastExitContext = newValue }
    }
}
