@testable import AreaMatrix

enum DeleteRequest: Equatable {
    case delete(repoPath: String, fileID: Int64)
    case removeIndex(repoPath: String, fileID: Int64)
}

actor DeleteRecordingDeleter: CoreFileDeleting {
    private var deleteResults: VoidResultQueue
    private var removeIndexResults: VoidResultQueue
    private var requestLog = TestRequestLog<DeleteRequest>()

    init(
        deleteResult: Result<Void, Error> = .success(()),
        removeIndexResult: Result<Void, Error> = .success(())
    ) {
        deleteResults = VoidResultQueue(result: deleteResult)
        removeIndexResults = VoidResultQueue(result: removeIndexResult)
    }

    func deleteFile(repoPath: String, fileID: Int64) async throws {
        requestLog.append(.delete(repoPath: repoPath, fileID: fileID))
        try deleteResults.next().get()
    }

    func removeIndexEntry(repoPath: String, fileID: Int64) async throws {
        requestLog.append(.removeIndex(repoPath: repoPath, fileID: fileID))
        try removeIndexResults.next().get()
    }

    func assertFileDeletionRequests(
        _ expectedRequests: [DeleteRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRequests, file: file, line: line)
    }
}
