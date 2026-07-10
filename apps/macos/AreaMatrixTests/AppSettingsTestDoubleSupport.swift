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
    private(set) var savedRepoPaths: [String] = []
    private(set) var successfulRepoOpens: [(repoPath: String, openedAt: Int64)] = []
    var successfulRepoOpenPaths: [String] {
        successfulRepoOpens.map(\.repoPath)
    }

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

    func assertSuccessfulRepoOpenPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(successfulRepoOpenPaths, expectedRepoPaths, file: file, line: line)
    }
}
