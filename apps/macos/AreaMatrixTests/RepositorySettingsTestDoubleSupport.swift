@testable import AreaMatrix
import XCTest

actor RepoSettingsMetadataReader: ExistingRepositoryMetadataReading {
    private var resultQueue: TestResultQueue<ExistingRepositoryMetadataSnapshot>

    init(results: [Swift.Result<ExistingRepositoryMetadataSnapshot, Error>]) {
        resultQueue = TestResultQueue(results: results) {
            .failure(CoreError.Internal(message: "missing metadata test result"))
        }
    }

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        try resultQueue.next()
    }
}

typealias RepoSettingsRepositoryOpener = RecordingRepositoryOpener

typealias RepoSettingsScanSessionReader = RecordingScanSessionReader

final class RecordingRepoMetadataPresenceChecker: RepoMetadataPresenceChecking {
    private var repoPaths: [String] = []
    private let presence: RepoMetadataPresence

    init(presence: RepoMetadataPresence) {
        self.presence = presence
    }

    func metadataPresence(repoPath: String) -> RepoMetadataPresence {
        repoPaths.append(repoPath)
        return presence
    }

    func assertRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(repoPaths, expectedRepoPaths, file: file, line: line)
    }

    func assertNoRepoMetadataPresenceRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRepoPaths([], file: file, line: line)
    }
}

typealias RepositorySettingsCapabilityRequest = PlatformCapabilityRequest
typealias RepoSettingsCapabilityLoader = RecordingPlatformCapabilityLoader
