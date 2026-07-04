@testable import AreaMatrix
import XCTest

actor AITagSuggestionAITagBridge: CoreAITagSuggestionManaging {
    private let report: AiTagSuggestionReport
    private var suggestRequests: [AiTagSuggestionRequest] = []
    private var applyRequests: [ApplyAiTagSuggestionsRequest] = []

    init(_ report: AiTagSuggestionReport) {
        self.report = report
    }

    func suggestTagsWithAI(repoPath: String, request: AiTagSuggestionRequest) async throws -> AiTagSuggestionReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        suggestRequests.append(request)
        return report
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAiTagSuggestionsRequest
    ) async throws -> AiTagSuggestionApplyReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        applyRequests.append(request)
        return aiTagSuggestionApplyReport(fileID: request.fileId)
    }

    func requests() -> (suggest: [AiTagSuggestionRequest], apply: [ApplyAiTagSuggestionsRequest]) {
        (suggestRequests, applyRequests)
    }
}

actor AITagSuggestionBatchAITagBridge: CoreAITagSuggestionManaging {
    private let reports: [Int64: AiTagSuggestionReport]
    private let applyReports: [Int64: AiTagSuggestionApplyReport]
    private var suggestRequests: [AiTagSuggestionRequest] = []
    private var applyRequests: [ApplyAiTagSuggestionsRequest] = []

    init(
        reports: [Int64: AiTagSuggestionReport],
        applyReports: [Int64: AiTagSuggestionApplyReport] = [:]
    ) {
        self.reports = reports
        self.applyReports = applyReports
    }

    func suggestTagsWithAI(repoPath: String, request: AiTagSuggestionRequest) async throws -> AiTagSuggestionReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        suggestRequests.append(request)
        guard let report = reports[request.fileId] else {
            throw CoreError.FileNotFound(path: "\(request.fileId)")
        }
        return report
    }

    func applyAITagSuggestions(
        repoPath: String,
        request: ApplyAiTagSuggestionsRequest
    ) async throws -> AiTagSuggestionApplyReport {
        XCTAssertEqual(repoPath, "/tmp/repo")
        applyRequests.append(request)
        return applyReports[request.fileId] ?? aiTagSuggestionBatchApplyReport(
            fileID: request.fileId,
            suggestionID: request.suggestions.first?.suggestionId ?? "ai-tag-finance",
            slug: request.suggestions.first?.slug ?? "finance"
        )
    }

    func requests() -> (suggest: [AiTagSuggestionRequest], apply: [ApplyAiTagSuggestionsRequest]) {
        (suggestRequests, applyRequests)
    }
}
