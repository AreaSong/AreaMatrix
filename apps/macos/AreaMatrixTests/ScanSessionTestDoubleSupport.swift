@testable import AreaMatrix

struct ScanSessionResumeRequest: Equatable {
    var repoPath: String
    var scanSessionId: Int64
}

actor RecordingScanSessionReader: CoreScanSessionReading {
    typealias ScanSessionResult = Swift.Result<ScanSessionSnapshot?, Error>
    typealias ResumeResult = Swift.Result<ReindexReportSnapshot, Error>

    private let repeatingResult: ScanSessionResult?
    private var queuedResults: [ScanSessionResult]
    private let repeatingResumeResult: ResumeResult?
    private var queuedResumeResults: [ResumeResult]
    private var repoPaths: [String] = []
    private var resumeRequests: [ScanSessionResumeRequest] = []

    init(session: ScanSessionSnapshot? = nil, resumeReport: ReindexReportSnapshot? = nil) {
        repeatingResult = .success(session)
        queuedResults = []
        repeatingResumeResult = resumeReport.map { .success($0) }
        queuedResumeResults = []
    }

    init(result: ScanSessionResult, resumeResult: ResumeResult? = nil) {
        repeatingResult = result
        queuedResults = []
        repeatingResumeResult = resumeResult
        queuedResumeResults = []
    }

    init(sessions: [ScanSessionSnapshot?], resumeReports: [ReindexReportSnapshot] = []) {
        repeatingResult = nil
        queuedResults = sessions.map { .success($0) }
        repeatingResumeResult = nil
        queuedResumeResults = resumeReports.map { .success($0) }
    }

    init(results: [ScanSessionResult], resumeResults: [ResumeResult] = []) {
        repeatingResult = nil
        queuedResults = results
        repeatingResumeResult = nil
        queuedResumeResults = resumeResults
    }

    func latestScanSession(repoPath: String) async throws -> ScanSessionSnapshot? {
        repoPaths.append(repoPath)
        return try nextResult()
    }

    func resumeScanSession(repoPath: String, scanSessionId: Int64) async throws -> ReindexReportSnapshot {
        resumeRequests.append(ScanSessionResumeRequest(repoPath: repoPath, scanSessionId: scanSessionId))
        return try nextResumeResult()
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }

    func recordedRepoPaths() -> [String] {
        repoPaths
    }

    func recordedResumeRequests() -> [ScanSessionResumeRequest] {
        resumeRequests
    }

    private func nextResult() throws -> ScanSessionSnapshot? {
        if let repeatingResult {
            return try repeatingResult.get()
        }
        guard !queuedResults.isEmpty else {
            throw CoreError.Internal(message: "missing scan session fixture")
        }

        return try queuedResults.removeFirst().get()
    }

    private func nextResumeResult() throws -> ReindexReportSnapshot {
        if let repeatingResumeResult {
            return try repeatingResumeResult.get()
        }
        guard !queuedResumeResults.isEmpty else {
            throw CoreError.Internal(message: "missing scan session resume fixture")
        }

        return try queuedResumeResults.removeFirst().get()
    }
}

typealias StaticScanSessionReader = RecordingScanSessionReader
