@testable import AreaMatrix

struct CommandPaletteCommandIndexRequest: Equatable {
    var repoPath: String
    var context: CommandIndexContext
}

actor CommandPaletteCommandIndexStore: CoreCommandIndexing {
    private var results: [Swift.Result<CommandIndex, Error>]
    private var requests: [CommandPaletteCommandIndexRequest] = []

    init(results: [Swift.Result<CommandIndex, Error>]) {
        self.results = results
    }

    func listCommandTargets(repoPath: String, context: CommandIndexContext) async throws -> CommandIndex {
        requests.append(.init(repoPath: repoPath, context: context))
        guard !results.isEmpty else { return .commandPaletteFixture() }
        return try results.removeFirst().get()
    }

    func recordedRequests() -> [CommandPaletteCommandIndexRequest] {
        requests
    }
}

typealias CommandPaletteSmartListRunRequest = SmartListRunRequestRecord
typealias CommandPaletteSmartListRunner = SmartListOnlyRecordingSearchQuerying
