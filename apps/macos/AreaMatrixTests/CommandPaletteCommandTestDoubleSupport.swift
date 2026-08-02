@testable import AreaMatrix
import XCTest

struct CommandPaletteCommandIndexRequest: Equatable {
    var repoPath: String
    var context: CommandIndexRequestSnapshot
}

actor CommandPaletteCommandIndexStore: CoreCommandIndexing {
    private var resultQueue: TestResultQueue<CoreCommandIndexSnapshot>
    private var requestLog = TestRequestLog<CommandPaletteCommandIndexRequest>()

    init(results: [Swift.Result<CoreCommandIndexSnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .success(.commandPaletteFixture())
        }
    }

    func listCommandTargets(
        repoPath: String,
        context: CommandIndexRequestSnapshot
    ) async throws -> CoreCommandIndexSnapshot {
        requestLog.append(.init(repoPath: repoPath, context: context))
        return try resultQueue.next()
    }

    func assertRequestContexts(
        _ expectedContexts: [CommandIndexRequestSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestLog.requests.map(\.context), expectedContexts, file: file, line: line)
    }
}

typealias CommandPaletteSmartListRunRequest = SmartListRunRequestRecord
typealias CommandPaletteSmartListRunner = SmartListOnlyRecordingSearchQuerying
