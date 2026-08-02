@testable import AreaMatrix
import XCTest

struct AITagSuggestionBridgeRequests {
    let suggest: [AITagSuggestionRequestSnapshot]
    let apply: [ApplyAITagSuggestionsRequestSnapshot]

    func assertNoAITagSuggestionRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(suggest, [], file: file, line: line)
        XCTAssertEqual(apply, [], file: file, line: line)
    }

    func assertNoAITagSuggestionApplyRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(apply, [], file: file, line: line)
    }

    func assertSuggestFileIDs(
        _ expectedFileIDs: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(suggest.map(\.fileID).sorted(), expectedFileIDs.sorted(), file: file, line: line)
    }

    func assertApplyFileIDs(
        _ expectedFileIDs: [Int64],
        confirmed expectedConfirmed: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            apply.map(\.fileId).sorted(),
            expectedFileIDs.sorted(),
            file: file,
            line: line
        )
        if let expectedConfirmed {
            XCTAssertEqual(
                apply.map(\.confirmed),
                Array(repeating: expectedConfirmed, count: apply.count),
                file: file,
                line: line
            )
        }
    }

    @discardableResult
    func assertSingleSuggestRequest(
        fileID expectedFileID: Int64? = nil,
        candidateTags expectedCandidateTags: [String]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> AITagSuggestionRequestSnapshot? {
        XCTAssertEqual(suggest.count, 1, file: file, line: line)
        let request = suggest.first
        if let expectedFileID {
            XCTAssertEqual(request?.fileID, expectedFileID, file: file, line: line)
        }
        if let expectedCandidateTags {
            XCTAssertEqual(request?.candidateTags, expectedCandidateTags, file: file, line: line)
        }
        return request
    }

    @discardableResult
    func assertSingleApplyRequest(
        fileID expectedFileID: Int64? = nil,
        confirmed expectedConfirmed: Bool? = nil,
        callLogID expectedCallLogID: Int64? = nil,
        suggestionIDs expectedSuggestionIDs: [String]? = nil,
        firstSuggestionDisplayName expectedFirstSuggestionDisplayName: String? = nil,
        firstSuggestionSlug expectedFirstSuggestionSlug: String? = nil,
        firstSuggestionEditedByUser expectedFirstSuggestionEditedByUser: Bool? = nil,
        firstSuggestionMergeTargetSlug expectedFirstSuggestionMergeTargetSlug: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(apply.count, 1, file: file, line: line)
        let request = apply.first
        if let expectedFileID {
            XCTAssertEqual(request?.fileId, expectedFileID, file: file, line: line)
        }
        if let expectedConfirmed {
            XCTAssertEqual(request?.confirmed, expectedConfirmed, file: file, line: line)
        }
        if let expectedCallLogID {
            XCTAssertEqual(request?.callLogId, expectedCallLogID, file: file, line: line)
        }
        if let expectedSuggestionIDs {
            XCTAssertEqual(request?.suggestions.map(\.suggestionId), expectedSuggestionIDs, file: file, line: line)
        }
        if let expectedFirstSuggestionDisplayName {
            XCTAssertEqual(
                request?.suggestions.first?.displayName,
                expectedFirstSuggestionDisplayName,
                file: file,
                line: line
            )
        }
        if let expectedFirstSuggestionSlug {
            XCTAssertEqual(request?.suggestions.first?.slug, expectedFirstSuggestionSlug, file: file, line: line)
        }
        if let expectedFirstSuggestionEditedByUser {
            XCTAssertEqual(
                request?.suggestions.first?.editedByUser,
                expectedFirstSuggestionEditedByUser,
                file: file,
                line: line
            )
        }
        if let expectedFirstSuggestionMergeTargetSlug {
            XCTAssertEqual(
                request?.suggestions.first?.mergeTargetSlug,
                expectedFirstSuggestionMergeTargetSlug,
                file: file,
                line: line
            )
        }
    }
}

protocol AITagSuggestionBridgeRequestRecording: Actor {
    var tagSuggestionRequestsForAssertions: AITagSuggestionBridgeRequests { get }
}

extension AITagSuggestionBridgeRequestRecording {
    func assertNoAITagSuggestionRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tagSuggestionRequestsForAssertions.assertNoAITagSuggestionRequests(file: file, line: line)
    }

    func assertNoAITagSuggestionApplyRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tagSuggestionRequestsForAssertions.assertNoAITagSuggestionApplyRequests(file: file, line: line)
    }

    func assertSuggestFileIDs(
        _ expectedFileIDs: [Int64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tagSuggestionRequestsForAssertions.assertSuggestFileIDs(expectedFileIDs, file: file, line: line)
    }

    func assertApplyFileIDs(
        _ expectedFileIDs: [Int64],
        confirmed expectedConfirmed: Bool? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tagSuggestionRequestsForAssertions.assertApplyFileIDs(
            expectedFileIDs,
            confirmed: expectedConfirmed,
            file: file,
            line: line
        )
    }

    func assertSingleSuggestRequest(
        fileID expectedFileID: Int64? = nil,
        candidateTags expectedCandidateTags: [String]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tagSuggestionRequestsForAssertions.assertSingleSuggestRequest(
            fileID: expectedFileID,
            candidateTags: expectedCandidateTags,
            file: file,
            line: line
        )
    }

    func assertSingleApplyRequest(
        fileID expectedFileID: Int64? = nil,
        confirmed expectedConfirmed: Bool? = nil,
        callLogID expectedCallLogID: Int64? = nil,
        suggestionIDs expectedSuggestionIDs: [String]? = nil,
        firstSuggestionDisplayName expectedFirstSuggestionDisplayName: String? = nil,
        firstSuggestionSlug expectedFirstSuggestionSlug: String? = nil,
        firstSuggestionEditedByUser expectedFirstSuggestionEditedByUser: Bool? = nil,
        firstSuggestionMergeTargetSlug expectedFirstSuggestionMergeTargetSlug: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tagSuggestionRequestsForAssertions.assertSingleApplyRequest(
            fileID: expectedFileID,
            confirmed: expectedConfirmed,
            callLogID: expectedCallLogID,
            suggestionIDs: expectedSuggestionIDs,
            firstSuggestionDisplayName: expectedFirstSuggestionDisplayName,
            firstSuggestionSlug: expectedFirstSuggestionSlug,
            firstSuggestionEditedByUser: expectedFirstSuggestionEditedByUser,
            firstSuggestionMergeTargetSlug: expectedFirstSuggestionMergeTargetSlug,
            file: file,
            line: line
        )
    }
}

actor AITagSuggestionAITagBridge: CoreAITagSuggestionManaging, AITagSuggestionBridgeRequestRecording {
    private let report: AITagSuggestionReportSnapshot
    private var suggestRequests: [AITagSuggestionRequestSnapshot] = []
    private var applyRequests: [ApplyAITagSuggestionsRequestSnapshot] = []

    init(_ report: AITagSuggestionReportSnapshot) {
        self.report = report
    }

    func suggestTagsWithAI(
        repoPath: String,
        request: AITagSuggestionRequestSnapshot
    ) async throws -> AITagSuggestionReportSnapshot {
        XCTAssertEqual(repoPath, "/tmp/repo")
        suggestRequests.append(request)
        return report
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAITagSuggestionsRequestSnapshot
    ) async throws -> AITagSuggestionApplyReportSnapshot {
        XCTAssertEqual(repoPath, "/tmp/repo")
        applyRequests.append(request)
        return aiTagSuggestionApplyReport(fileID: request.fileId)
    }

    var tagSuggestionRequestsForAssertions: AITagSuggestionBridgeRequests {
        AITagSuggestionBridgeRequests(suggest: suggestRequests, apply: applyRequests)
    }
}

actor AITagSuggestionBatchAITagBridge: CoreAITagSuggestionManaging, AITagSuggestionBridgeRequestRecording {
    private let reports: [Int64: AITagSuggestionReportSnapshot]
    private let applyReports: [Int64: AITagSuggestionApplyReportSnapshot]
    private var suggestRequests: [AITagSuggestionRequestSnapshot] = []
    private var applyRequests: [ApplyAITagSuggestionsRequestSnapshot] = []

    init(
        reports: [Int64: AITagSuggestionReportSnapshot],
        applyReports: [Int64: AITagSuggestionApplyReportSnapshot] = [:]
    ) {
        self.reports = reports
        self.applyReports = applyReports
    }

    func suggestTagsWithAI(
        repoPath: String,
        request: AITagSuggestionRequestSnapshot
    ) async throws -> AITagSuggestionReportSnapshot {
        XCTAssertEqual(repoPath, "/tmp/repo")
        suggestRequests.append(request)
        guard let report = reports[request.fileID] else {
            throw CoreError.FileNotFound(path: "\(request.fileID)")
        }
        return report
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAITagSuggestionsRequestSnapshot
    ) async throws -> AITagSuggestionApplyReportSnapshot {
        XCTAssertEqual(repoPath, "/tmp/repo")
        applyRequests.append(request)
        return applyReports[request.fileId] ?? aiTagSuggestionBatchApplyReport(
            fileID: request.fileId,
            suggestionID: request.suggestions.first?.suggestionId ?? "ai-tag-finance",
            slug: request.suggestions.first?.slug ?? "finance"
        )
    }

    var tagSuggestionRequestsForAssertions: AITagSuggestionBridgeRequests {
        AITagSuggestionBridgeRequests(suggest: suggestRequests, apply: applyRequests)
    }
}
