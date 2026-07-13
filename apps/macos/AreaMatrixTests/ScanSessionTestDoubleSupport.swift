@testable import AreaMatrix
import XCTest

struct ScanSessionResumeRequest: Equatable {
    var repoPath: String
    var scanSessionId: Int64
}

actor RecordingScanSessionReader: CoreScanSessionReading, RepoPathRequestRecording {
    typealias ScanSessionResult = Swift.Result<ScanSessionSnapshot?, Error>
    typealias ResumeResult = Swift.Result<ReindexReportSnapshot, Error>

    private var scanSessionQueue: TestResultQueue<ScanSessionSnapshot?>
    private var resumeQueue: TestResultQueue<ReindexReportSnapshot>
    private var repoPaths: [String] = []
    private var resumeRequests: [ScanSessionResumeRequest] = []

    init(session: ScanSessionSnapshot? = nil, resumeReport: ReindexReportSnapshot? = nil) {
        scanSessionQueue = TestResultQueue(result: .success(session), missingResult: Self.missingScanSessionResult)
        resumeQueue = TestResultQueue(
            result: resumeReport.map { .success($0) } ?? Self.missingResumeResult(),
            missingResult: Self.missingResumeResult
        )
    }

    init(result: ScanSessionResult, resumeResult: ResumeResult? = nil) {
        scanSessionQueue = TestResultQueue(result: result, missingResult: Self.missingScanSessionResult)
        resumeQueue = TestResultQueue(
            result: resumeResult ?? Self.missingResumeResult(),
            missingResult: Self.missingResumeResult
        )
    }

    init(sessions: [ScanSessionSnapshot?], resumeReports: [ReindexReportSnapshot] = []) {
        scanSessionQueue = TestResultQueue(
            results: sessions.map { .success($0) },
            missingResult: Self.missingScanSessionResult
        )
        resumeQueue = TestResultQueue(
            results: resumeReports.map { .success($0) },
            missingResult: Self.missingResumeResult
        )
    }

    init(results: [ScanSessionResult], resumeResults: [ResumeResult] = []) {
        scanSessionQueue = TestResultQueue(results: results, missingResult: Self.missingScanSessionResult)
        resumeQueue = TestResultQueue(results: resumeResults, missingResult: Self.missingResumeResult)
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        repoPaths.append(repoPath)
        return try nextResult()
    }

    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        resumeRequests.append(ScanSessionResumeRequest(repoPath: repoPath, scanSessionId: scanSessionId))
        return try nextResumeResult()
    }

    var repoPathsForAssertions: [String] {
        repoPaths
    }

    func assertScanSessionResumeRequests(
        _ expectedRequests: [ScanSessionResumeRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(resumeRequests, expectedRequests, file: file, line: line)
    }

    private func nextResult() throws -> ScanSessionSnapshot? {
        try scanSessionQueue.next()
    }

    private func nextResumeResult() throws -> ReindexReportSnapshot {
        try resumeQueue.next()
    }

    private static func missingScanSessionResult() -> ScanSessionResult {
        .failure(CoreError.Internal(message: "missing scan session fixture"))
    }

    private static func missingResumeResult() -> ResumeResult {
        .failure(CoreError.Internal(message: "missing scan session resume fixture"))
    }
}

typealias StaticScanSessionReader = RecordingScanSessionReader
