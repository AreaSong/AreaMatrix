@testable import AreaMatrix

struct CommandPaletteCommandIndexRequest: Equatable {
    var repoPath: String
    var context: CommandIndexContext
}

actor CommandPaletteCommandIndexStore: CoreCommandIndexing {
    enum Result { case success(CommandIndex), failure(Error) }

    private var results: [Result]
    private var requests: [CommandPaletteCommandIndexRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listCommandTargets(repoPath: String, context: CommandIndexContext) async throws -> CommandIndex {
        requests.append(.init(repoPath: repoPath, context: context))
        guard !results.isEmpty else { return .commandPaletteFixture() }
        switch results.removeFirst() {
        case let .success(index):
            return index
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [CommandPaletteCommandIndexRequest] {
        requests
    }
}

actor CommandPaletteCommandErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

struct CommandPaletteSmartListRunRequest: Equatable {
    var repoPath: String
    var savedSearchID: Int64
    var limit: Int64
    var offset: Int64
}

actor CommandPaletteSmartListRunner: CoreSearchQuerying {
    enum Result { case success(SearchResultPageSnapshot), failure(Error) }

    private var results: [Result]
    private var runRequests: [CommandPaletteSmartListRunRequest] = []
    private var searchRequests: [SearchQueryRequestSnapshot] = []

    init(results: [Result]) {
        self.results = results
    }

    func searchFiles(repoPath _: String, request: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        searchRequests.append(request)
        throw CoreError.Internal(message: "search_files must not run command-palette smart-list Smart List execution")
    }

    func runSmartList(
        repoPath: String,
        savedSearchID: Int64,
        limit: Int64,
        offset: Int64
    ) async throws -> SearchResultPageSnapshot {
        runRequests.append(CommandPaletteSmartListRunRequest(
            repoPath: repoPath,
            savedSearchID: savedSearchID,
            limit: limit,
            offset: offset
        ))
        guard !results.isEmpty else {
            return SearchResultPageSnapshot(query: "", totalCount: 0, results: [], diagnostics: [], indexStatus: .ready)
        }
        switch results.removeFirst() {
        case let .success(page):
            return page
        case let .failure(error):
            throw error
        }
    }

    func recordedRunRequests() -> [CommandPaletteSmartListRunRequest] {
        runRequests
    }

    func recordedSearchRequests() -> [SearchQueryRequestSnapshot] {
        searchRequests
    }
}
