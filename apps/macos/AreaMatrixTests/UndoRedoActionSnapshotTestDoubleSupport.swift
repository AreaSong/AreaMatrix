@testable import AreaMatrix
import XCTest

actor NoopUndoActionStore: CoreUndoActionLogging {
    func listUndoActions(repoPath _: String) async throws -> [UndoActionRecordSnapshot] {
        []
    }

    func undoAction(repoPath _: String, actionID _: String) async throws -> UndoActionResultSnapshot {
        throw CoreError.Internal(message: "noop undo action store does not execute undo actions")
    }
}

actor UndoActionRecordingTestStore: CoreUndoActionLogging, UndoActionRequestRecording {
    enum Step {
        case list(Swift.Result<[UndoActionRecordSnapshot], Error>)
        case undo(Swift.Result<UndoActionResultSnapshot, Error>)
    }

    private var results: [Step]
    private var recordedListRequests: [String] = []
    private var recordedUndoRequests: [String] = []

    init(results: [Step]) {
        self.results = results
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        do {
            guard case let .list(result) = try consumeResult() else {
                throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
            }
            return try result.get()
        } catch UndoActionRecordingTestStoreError.missingResult {
            throw CoreError.Db(message: "missing undo action result")
        }
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        do {
            guard case let .undo(result) = try consumeResult() else {
                throw CoreError.Internal(message: "expected undo_action result")
            }
            return try result.get()
        } catch UndoActionRecordingTestStoreError.missingResult {
            throw CoreError.Db(message: "missing undo action result")
        }
    }

    var undoActionListRequestsForAssertions: [String] {
        recordedListRequests
    }

    var undoActionRequestsForAssertions: [String] {
        recordedUndoRequests
    }

    fileprivate func listUndoActionsLenient(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard case let .list(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected list_undo_actions before undo_action")
        }
        return try result.get()
    }

    fileprivate func undoActionLenient(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        recordedUndoRequests.append("\(repoPath)|\(actionID)")
        guard case let .undo(result) = try consumeResult() else {
            throw CoreError.Internal(message: "expected undo_action result")
        }
        return try result.get()
    }

    private func consumeResult() throws -> Step {
        guard !results.isEmpty else { throw UndoActionRecordingTestStoreError.missingResult }
        return results.removeFirst()
    }
}

private enum UndoActionRecordingTestStoreError: Error {
    case missingResult
}

actor LenientUndoActionRecordingTestStore: CoreUndoActionLogging {
    private let store: UndoActionRecordingTestStore

    init(results: [UndoActionRecordingTestStore.Step]) {
        store = UndoActionRecordingTestStore(results: results)
    }

    init(actions: [UndoActionRecordSnapshot]) {
        store = UndoActionRecordingTestStore(results: [.list(.success(actions))])
    }

    init(
        actions: Swift.Result<[UndoActionRecordSnapshot], Error> = .success([]),
        undoResult: Swift.Result<UndoActionResultSnapshot, Error>? = nil
    ) {
        var results: [UndoActionRecordingTestStore.Step] = [.list(actions)]
        if let undoResult {
            results.append(.undo(undoResult))
        }
        store = UndoActionRecordingTestStore(results: results)
    }

    func listUndoActions(repoPath: String) async throws -> [UndoActionRecordSnapshot] {
        do {
            return try await store.listUndoActionsLenient(repoPath: repoPath)
        } catch UndoActionRecordingTestStoreError.missingResult {
            return []
        }
    }

    func undoAction(repoPath: String, actionID: String) async throws -> UndoActionResultSnapshot {
        do {
            return try await store.undoActionLenient(repoPath: repoPath, actionID: actionID)
        } catch UndoActionRecordingTestStoreError.missingResult {
            throw CoreError.FileNotFound(path: actionID)
        }
    }

    func assertUndoActionListRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await store.assertUndoActionListRequests(expectedRequests, file: file, line: line)
    }

    func assertUndoActionRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await store.assertUndoActionRequests(expectedRequests, file: file, line: line)
    }
}

typealias UndoToastRecordingUndoStore = LenientUndoActionRecordingTestStore
typealias BatchAddTagsRecordingUndoStore = UndoActionRecordingTestStore

actor RedoActionLogRecordingRedoStore: CoreRedoActionLogging, RedoActionRequestRecording {
    enum Step {
        case list(Swift.Result<[RedoActionRecordSnapshot], Error>)
        case redo(Swift.Result<RedoActionResultSnapshot, Error>)
    }

    private var results: [Step]
    private var recordedListRequests: [String] = []
    private var recordedRedoRequests: [String] = []

    init(results: [Step]) {
        self.results = results
    }

    func listRedoActions(repoPath: String) async throws -> [RedoActionRecordSnapshot] {
        recordedListRequests.append(repoPath)
        guard !results.isEmpty else { return [] }
        guard case let .list(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected listRedoActions")
        }
        return try result.get()
    }

    func redoAction(repoPath: String, actionID: String) async throws -> RedoActionResultSnapshot {
        recordedRedoRequests.append("\(repoPath)|\(actionID)")
        guard !results.isEmpty else {
            throw CoreError.FileNotFound(path: actionID)
        }
        guard case let .redo(result) = results.removeFirst() else {
            throw CoreError.Internal(message: "Expected redoAction")
        }
        return try result.get()
    }

    var redoActionListRequestsForAssertions: [String] {
        recordedListRequests
    }

    var redoActionRequestsForAssertions: [String] {
        recordedRedoRequests
    }
}

protocol UndoActionListRequestRecording: Actor {
    var undoActionListRequestsForAssertions: [String] { get }
}

extension UndoActionListRequestRecording {
    func assertUndoActionListRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(undoActionListRequestsForAssertions, expectedRequests, file: file, line: line)
    }
}

protocol UndoActionRequestRecording: UndoActionListRequestRecording {
    var undoActionRequestsForAssertions: [String] { get }
}

extension UndoActionRequestRecording {
    func assertUndoActionRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(undoActionRequestsForAssertions, expectedRequests, file: file, line: line)
    }
}

protocol RedoActionListRequestRecording: Actor {
    var redoActionListRequestsForAssertions: [String] { get }
}

extension RedoActionListRequestRecording {
    func assertRedoActionListRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(redoActionListRequestsForAssertions, expectedRequests, file: file, line: line)
    }
}

protocol RedoActionRequestRecording: RedoActionListRequestRecording {
    var redoActionRequestsForAssertions: [String] { get }
}

extension RedoActionRequestRecording {
    func assertRedoActionRequests(
        _ expectedRequests: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(redoActionRequestsForAssertions, expectedRequests, file: file, line: line)
    }
}
