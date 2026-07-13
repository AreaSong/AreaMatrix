@testable import AreaMatrix
import XCTest

typealias SmartListRecordingSavedSearchStore = RecordingSavedSearchStore

struct SavedSearchCreateRequestRecord: Equatable {
    var repoPath: String
    var request: CreateSavedSearchRequestSnapshot
}

struct SavedSearchUpdateRequestRecord: Equatable {
    var repoPath: String
    var request: UpdateSavedSearchRequestSnapshot
}

struct SavedSearchDeleteRequestRecord: Equatable {
    var repoPath: String
    var savedSearchID: Int64
}

actor RecordingSavedSearchStore: CoreSavedSearchCRUD {
    enum Step {
        case list([SavedSearchSnapshot])
        case listResult(Swift.Result<[SavedSearchSnapshot], Error>)
        case create(Swift.Result<SavedSearchSnapshot, Error>)
        case update(Swift.Result<SavedSearchSnapshot, Error>)
        case delete(Swift.Result<Void, Error>)
    }

    private var steps: [Step]
    private var listRepoPathsStorage: [String] = []
    private var createRecords: [SavedSearchCreateRequestRecord] = []
    private var updateRecords: [SavedSearchUpdateRequestRecord] = []
    private var deleteRecords: [SavedSearchDeleteRequestRecord] = []

    init(results: [Step]) {
        steps = results
    }

    init(listResults: [Swift.Result<[SavedSearchSnapshot], Error>]) {
        steps = listResults.map(Step.listResult)
    }

    func createSavedSearch(
        repoPath: String,
        request: CreateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        createRecords.append(SavedSearchCreateRequestRecord(repoPath: repoPath, request: request))
        guard let step = consumeStep() else {
            throw CoreError.Db(message: "missing saved search create result")
        }

        switch step {
        case let .create(result):
            return try result.get()
        case .list, .listResult, .update, .delete:
            throw CoreError.Internal(message: "expected saved search create result")
        }
    }

    func updateSavedSearch(
        repoPath: String,
        request: UpdateSavedSearchRequestSnapshot
    ) async throws -> SavedSearchSnapshot {
        updateRecords.append(SavedSearchUpdateRequestRecord(repoPath: repoPath, request: request))
        guard let step = consumeStep() else {
            throw CoreError.Db(message: "missing saved search update result")
        }

        switch step {
        case let .update(result):
            return try result.get()
        case .list, .listResult, .create, .delete:
            throw CoreError.Internal(message: "expected saved search update result")
        }
    }

    func deleteSavedSearch(repoPath: String, savedSearchID: Int64) async throws {
        deleteRecords.append(SavedSearchDeleteRequestRecord(repoPath: repoPath, savedSearchID: savedSearchID))
        guard let step = consumeStep() else {
            throw CoreError.Db(message: "missing saved search delete result")
        }

        switch step {
        case let .delete(result):
            try result.get()
        case .list, .listResult, .create, .update:
            throw CoreError.Internal(message: "expected saved search delete result")
        }
    }

    func listSavedSearches(repoPath: String) async throws -> [SavedSearchSnapshot] {
        listRepoPathsStorage.append(repoPath)
        guard let step = consumeStep() else { return [] }

        switch step {
        case let .list(saved):
            return saved
        case let .listResult(result):
            return try result.get()
        case .create, .update, .delete:
            throw CoreError.Internal(message: "expected saved search list result")
        }
    }

    func assertSavedSearchListRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(listRepoPathsStorage, expectedRepoPaths, file: file, line: line)
    }

    func assertSavedSearchCreateRequests(
        _ expectedRequests: [SavedSearchCreateRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(createRecords, expectedRequests, file: file, line: line)
    }

    func assertSavedSearchUpdateRequests(
        _ expectedRequests: [SavedSearchUpdateRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(updateRecords, expectedRequests, file: file, line: line)
    }

    func assertSavedSearchDeleteRequests(
        _ expectedRequests: [SavedSearchDeleteRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(deleteRecords, expectedRequests, file: file, line: line)
    }

    private func consumeStep() -> Step? {
        guard !steps.isEmpty else { return nil }
        return steps.removeFirst()
    }
}
