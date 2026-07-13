@testable import AreaMatrix
import XCTest

struct CommandPaletteCommandIndexRequest: Equatable {
    var repoPath: String
    var context: CommandIndexContext
}

actor CommandPaletteCommandIndexStore: CoreCommandIndexing {
    private var resultQueue: TestResultQueue<CommandIndex>
    private var requests: [CommandPaletteCommandIndexRequest] = []

    init(results: [Swift.Result<CommandIndex, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .success(.commandPaletteFixture())
        }
    }

    func listCommandTargets(repoPath: String, context: CommandIndexContext) async throws -> CommandIndex {
        requests.append(.init(repoPath: repoPath, context: context))
        return try resultQueue.next()
    }

    func assertRequestContexts(
        _ expectedContexts: [CommandIndexContext],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requests.map(\.context), expectedContexts, file: file, line: line)
    }
}

typealias CommandPaletteSmartListRunRequest = SmartListRunRequestRecord
typealias CommandPaletteSmartListRunner = SmartListOnlyRecordingSearchQuerying
