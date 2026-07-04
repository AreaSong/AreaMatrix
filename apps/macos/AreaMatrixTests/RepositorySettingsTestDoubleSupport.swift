@testable import AreaMatrix

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
    private(set) var repoPaths: [String] = []
    private let presence: RepoMetadataPresence

    init(presence: RepoMetadataPresence) {
        self.presence = presence
    }

    func metadataPresence(repoPath: String) -> RepoMetadataPresence {
        repoPaths.append(repoPath)
        return presence
    }
}

typealias RepositorySettingsCapabilityRequest = PlatformCapabilityRequest
typealias RepoSettingsCapabilityLoader = RecordingPlatformCapabilityLoader
