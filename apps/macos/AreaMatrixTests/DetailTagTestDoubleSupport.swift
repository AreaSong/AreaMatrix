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

    private var listResults: TestResultQueue<TagSetSnapshot>
    private var addResults: TestResultQueue<TagSetSnapshot>
    private var removeResults: TestResultQueue<TagSetSnapshot>
    private var suggestionResults: TestResultQueue<TagSuggestionReportSnapshot>
    private var applySuggestionResults: TestResultQueue<TagSuggestionApplyReportSnapshot>
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
        self.listResults = TestResultQueue(results: listResults) {
            .failure(CoreError.Internal(message: "missing detail tag list test result"))
        }
        self.addResults = TestResultQueue(results: addResults) {
            .failure(CoreError.Internal(message: "missing detail tag add test result"))
        }
        self.removeResults = TestResultQueue(results: removeResults) {
            .failure(CoreError.Internal(message: "missing detail tag remove test result"))
        }
        self.suggestionResults = TestResultQueue(results: suggestionResults) {
            .failure(CoreError.Internal(message: "missing detail tag suggestion test result"))
        }
        self.applySuggestionResults = TestResultQueue(results: applySuggestionResults) {
            .failure(CoreError.Internal(message: "missing detail tag apply suggestion test result"))
        }
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
        return try suggestionResults.next {
            .success(.tagSuggestionsFixture(fileID: request.fileID))
        }
    }

    func applyTagSuggestions(
        repoPath: String,
        request: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot {
        recordedApplySuggestionRequests.append(ApplyTagSuggestionsRequestRecord(repoPath: repoPath, request: request))
        return try applySuggestionResults.next {
            .success(.tagSuggestionsApplied(fileID: request.fileID))
        }
    }

    func assertDetailTagAddRequests(
        _ expectedRequests: [DetailTagMutationRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedAddRequests, expectedRequests, file: file, line: line)
    }

    func assertDetailTagRemoveRequests(
        _ expectedRequests: [DetailTagMutationRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedRemoveRequests, expectedRequests, file: file, line: line)
    }

    func assertDetailTagListRequests(
        _ expectedRequests: [DetailTagListRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedListRequests, expectedRequests, file: file, line: line)
    }

    func assertDetailTagListRequestFileIDs(
        _ expectedFileIDs: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedListRequests.map(\.fileID), expectedFileIDs, file: file, line: line)
    }

    func assertDetailTagSuggestionRequests(
        _ expectedRequests: [TagSuggestionRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedSuggestionRequests, expectedRequests, file: file, line: line)
    }

    func assertDetailTagApplySuggestionRequests(
        _ expectedRequests: [ApplyTagSuggestionsRequestRecord],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedApplySuggestionRequests, expectedRequests, file: file, line: line)
    }

    func assertNoDetailTagApplySuggestionRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertDetailTagApplySuggestionRequests([], file: file, line: line)
    }

    func assertLastDetailTagApplySuggestionRequestSuggestions(
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

    private func consume(
        _ results: inout TestResultQueue<TagSetSnapshot>,
        fallbackFileID: Int64
    ) throws -> TagSetSnapshot {
        try results.next {
            .success(TagSetSnapshot.tagAddFixture(fileID: fallbackFileID, values: []))
        }
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
