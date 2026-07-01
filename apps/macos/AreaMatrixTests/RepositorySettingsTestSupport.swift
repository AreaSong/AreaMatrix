@testable import AreaMatrix
import Foundation

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

func temporaryRepositorySettingsRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRepositorySettings")
}

func createRepositorySettingsMetadataDatabaseMarker(in repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try Data().write(to: metadataURL.appendingPathComponent("index.db"))
}

func removeRepositorySettingsMetadataDatabaseSidecars(in repoURL: URL) {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    for name in ["index.db-wal", "index.db-shm"] {
        try? removeTestTemporaryItem(metadataURL.appendingPathComponent(name))
    }
}
