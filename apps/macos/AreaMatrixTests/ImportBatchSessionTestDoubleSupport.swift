@testable import AreaMatrix
import XCTest

struct ImportBatchSavedSessionExpectation {
    var repoPath: String?
    var completed: Int?
    var failed: Int?
    var total: Int?
    var itemPhases: [ImportBatchProgressSnapshot.Phase]?

    init(
        repoPath: String? = nil,
        completed: Int? = nil,
        failed: Int? = nil,
        total: Int? = nil,
        itemPhases: [ImportBatchProgressSnapshot.Phase]? = nil
    ) {
        self.repoPath = repoPath
        self.completed = completed
        self.failed = failed
        self.total = total
        self.itemPhases = itemPhases
    }
}

actor StaticImportBatchSessionStore: ImportBatchSessionPersisting {
    private let session: ImportBatchSessionSnapshot?
    private var cleared: [String] = []

    init(session: ImportBatchSessionSnapshot?) {
        self.session = session
    }

    func saveSession(_: ImportBatchSessionSnapshot) async {}

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        guard session?.repoPath == repoPath else { return nil }
        return session
    }

    func clearSession(repoPath: String) {
        cleared.append(repoPath)
    }

    func waitForClearedRepoPaths(_ expected: [String], attempts: Int = 1000) async -> [String] {
        await waitForActorTestValue(
            on: self,
            attempts: attempts,
            failureMessage: { "Timed out waiting for cleared import batch session repo paths, got \(cleared)" },
            value: {
                cleared == expected ? cleared : nil
            }
        ) ?? cleared
    }
}

actor RecordingImportBatchSessionStore: ImportBatchSessionPersisting {
    private var saved: [ImportBatchSessionSnapshot] = []
    private var cleared: [String] = []
    private var sessionsByRepoPath: [String: ImportBatchSessionSnapshot] = [:]

    func saveSession(_ session: ImportBatchSessionSnapshot) async {
        saved.append(session)
        sessionsByRepoPath[session.repoPath] = session
    }

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        sessionsByRepoPath[repoPath]
    }

    func clearSession(repoPath: String) async {
        cleared.append(repoPath)
        sessionsByRepoPath[repoPath] = nil
    }

    func assertFirstSavedSession(
        _ expected: ImportBatchSavedSessionExpectation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSavedSession(
            saved.first,
            expected: expected,
            file: file,
            line: line
        )
    }

    func assertLastSavedSession(
        _ expected: ImportBatchSavedSessionExpectation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSavedSession(
            saved.last,
            expected: expected,
            file: file,
            line: line
        )
    }

    func assertClearedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(cleared, expectedRepoPaths, file: file, line: line)
    }

    private func assertSavedSession(
        _ session: ImportBatchSessionSnapshot?,
        expected: ImportBatchSavedSessionExpectation,
        file: StaticString,
        line: UInt
    ) {
        guard let session else {
            XCTFail("Expected saved import batch session", file: file, line: line)
            return
        }
        if let repoPath = expected.repoPath {
            XCTAssertEqual(session.repoPath, repoPath, file: file, line: line)
        }
        if let completed = expected.completed {
            XCTAssertEqual(session.completed, completed, file: file, line: line)
        }
        if let failed = expected.failed {
            XCTAssertEqual(session.failed, failed, file: file, line: line)
        }
        if let total = expected.total {
            XCTAssertEqual(session.total, total, file: file, line: line)
        }
        if let itemPhases = expected.itemPhases {
            XCTAssertEqual(session.items.map(\.phase), itemPhases, file: file, line: line)
        }
    }
}
