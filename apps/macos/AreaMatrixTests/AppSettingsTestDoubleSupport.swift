@testable import AreaMatrix
import XCTest

struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?
    var lastOpenedAtByRepoPath: [String: Int64] = [:]

    func configuredRepoPath() -> String? {
        repoPath
    }

    func lastSuccessfulRepoOpenAt(repoPath: String) -> Int64? {
        lastOpenedAtByRepoPath[repoPath]
    }
}

final class RecordingAppSettingsWriter: AppSettingsWriting {
    private var savedRepoPaths: [String] = []
    private var successfulRepoOpens: [(repoPath: String, openedAt: Int64)] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }

    func saveSuccessfulRepoOpen(repoPath: String, openedAt: Int64) {
        successfulRepoOpens.append((repoPath: repoPath, openedAt: openedAt))
    }

    func assertSavedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(savedRepoPaths, expectedRepoPaths, file: file, line: line)
    }

    func assertNoSavedRepoPaths(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertSavedRepoPaths([], file: file, line: line)
    }

    func assertSuccessfulRepoOpenPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(successfulRepoOpens.map(\.repoPath), expectedRepoPaths, file: file, line: line)
    }
}
