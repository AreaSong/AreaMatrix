@testable import AreaMatrix
import XCTest

struct DetailTagMutationRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var tag: String
}

struct DetailTagListRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

struct TagSuggestionRequestRecord: Equatable {
    var repoPath: String
    var request: TagSuggestionRequestSnapshot
}

struct ApplyTagSuggestionsRequestRecord: Equatable {
    var repoPath: String
    var request: ApplyTagSuggestionsRequestSnapshot
}

actor DetailTagRecordingStore: CoreTagCRUD {
    typealias Result = Swift.Result<TagSetSnapshot, Error>
    typealias SuggestionResult = Swift.Result<TagSuggestionReportSnapshot, Error>
    typealias ApplySuggestionResult = Swift.Result<TagSuggestionApplyReportSnapshot, Error>

    private var listResults: [Result]
    private var addResults: [Result]
    private var removeResults: [Result]
    private var suggestionResults: [SuggestionResult]
    private var applySuggestionResults: [ApplySuggestionResult]
    private var recordedListRequests: [DetailTagListRequest] = []
    private var recordedAddRequests: [DetailTagMutationRequest] = []
    private var recordedRemoveRequests: [DetailTagMutationRequest] = []
    private var recordedSuggestionRequests: [TagSuggestionRequestRecord] = []
    private var recordedApplySuggestionRequests: [ApplyTagSuggestionsRequestRecord] = []

    init(
        listResults: [Result] = [],
        addResults: [Result] = [],
        removeResults: [Result] = [],
        suggestionResults: [SuggestionResult] = [],
        applySuggestionResults: [ApplySuggestionResult] = []
    ) {
        self.listResults = listResults
        self.addResults = addResults
        self.removeResults = removeResults
        self.suggestionResults = suggestionResults
        self.applySuggestionResults = applySuggestionResults
    }

    func listTags(repoPath: String, fileID: Int64) async throws -> TagSetSnapshot {
        recordedListRequests.append(DetailTagListRequest(repoPath: repoPath, fileID: fileID))
        return try consume(&listResults, fallbackFileID: fileID)
    }

    func addTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        recordedAddRequests.append(DetailTagMutationRequest(repoPath: repoPath, fileID: fileID, tag: tag))
        return try consume(&addResults, fallbackFileID: fileID)
    }

    func removeTag(repoPath: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        recordedRemoveRequests.append(DetailTagMutationRequest(repoPath: repoPath, fileID: fileID, tag: tag))
        return try consume(&removeResults, fallbackFileID: fileID)
    }

    func suggestTagsForFile(
        repoPath: String,
        request: TagSuggestionRequestSnapshot
    ) async throws -> TagSuggestionReportSnapshot {
        recordedSuggestionRequests.append(TagSuggestionRequestRecord(repoPath: repoPath, request: request))
        guard !suggestionResults.isEmpty else { return .tagSuggestionsFixture(fileID: request.fileID) }
        return try suggestionResults.removeFirst().get()
    }

    func applyTagSuggestions(
        repoPath: String,
        request: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot {
        recordedApplySuggestionRequests.append(ApplyTagSuggestionsRequestRecord(repoPath: repoPath, request: request))
        guard !applySuggestionResults.isEmpty else { return .tagSuggestionsApplied(fileID: request.fileID) }
        return try applySuggestionResults.removeFirst().get()
    }

    func addRequests() -> [DetailTagMutationRequest] {
        recordedAddRequests
    }

    func removeRequests() -> [DetailTagMutationRequest] {
        recordedRemoveRequests
    }

    func assertAddRequests(
        _ expectedRequests: [DetailTagMutationRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedAddRequests, expectedRequests, file: file, line: line)
    }

    func assertRemoveRequests(
        _ expectedRequests: [DetailTagMutationRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRemoveRequests, expectedRequests, file: file, line: line)
    }

    func assertListRequests(
        _ expectedRequests: [DetailTagListRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedListRequests, expectedRequests, file: file, line: line)
    }

    func assertListRequestFileIDs(
        _ expectedFileIDs: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedListRequests.map(\.fileID), expectedFileIDs, file: file, line: line)
    }

    func assertSuggestionRequests(
        _ expectedRequests: [TagSuggestionRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedSuggestionRequests, expectedRequests, file: file, line: line)
    }

    func assertApplySuggestionRequests(
        _ expectedRequests: [ApplyTagSuggestionsRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedApplySuggestionRequests, expectedRequests, file: file, line: line)
    }

    func assertNoApplySuggestionRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertApplySuggestionRequests([], file: file, line: line)
    }

    func assertLastApplySuggestionRequestSuggestions(
        _ expectedSuggestions: [ApplyTagSuggestionItemSnapshot],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            recordedApplySuggestionRequests.last?.request.suggestions,
            expectedSuggestions,
            file: file,
            line: line
        )
    }

    private func consume(_ results: inout [Result], fallbackFileID: Int64) throws -> TagSetSnapshot {
        guard !results.isEmpty else { return TagSetSnapshot.tagAddFixture(fileID: fallbackFileID, values: []) }
        return try results.removeFirst().get()
    }
}

actor TagFilterForbiddenTagStore: CoreTagCRUD {
    private var calls: [String] = []

    func listTags(repoPath _: String, fileID _: Int64) async throws -> TagSetSnapshot {
        calls.append("listTags")
        throw CoreError.Internal(message: "tag-filters search-filters must use list_filter_facets")
    }

    func addTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        calls.append("addTag")
        throw CoreError.Internal(message: "tag-filters search-filters must not add tags")
    }

    func removeTag(repoPath _: String, fileID _: Int64, tag _: String) async throws -> TagSetSnapshot {
        calls.append("removeTag")
        throw CoreError.Internal(message: "tag-filters search-filters must not remove tags")
    }

    func assertNoCalls(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(calls, [], file: file, line: line)
    }
}
