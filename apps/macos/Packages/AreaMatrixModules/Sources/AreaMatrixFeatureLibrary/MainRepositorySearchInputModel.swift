import AreaMatrixCoreBridgeContract
import Combine

/// Window-local search controls owned by the Library surface.
///
/// This model intentionally contains only user input and value contracts. Search
/// requests, privacy gates, indexing tasks, and results remain in `SearchModel`.
@MainActor
public final class MainRepositorySearchInputModel: ObservableObject {
    @Published public var filterText = ""
    @Published public var searchScope: SearchScopeSnapshot = .all
    @Published public var searchMode: SearchModeSnapshot = .normal
    @Published public var searchSort: SearchSortSnapshot = .newestImported
    @Published public var searchFilters: SearchFilterStateSnapshot = .empty

    public init() {}
}
