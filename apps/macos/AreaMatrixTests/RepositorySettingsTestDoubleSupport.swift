@testable import AreaMatrix
import XCTest

actor RepoSettingsMetadataReader: ExistingRepositoryMetadataReading {
    private var results: [Result<ExistingRepositoryMetadataSnapshot, Error>]

    init(results: [Result<ExistingRepositoryMetadataSnapshot, Error>]) {
        self.results = results
    }

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing metadata test result")
        }

        return try results.removeFirst().get()
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

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRepoPaths([], file: file, line: line)
    }
}

typealias RepositorySettingsCapabilityRequest = PlatformCapabilityRequest
typealias RepoSettingsCapabilityLoader = RecordingPlatformCapabilityLoader
