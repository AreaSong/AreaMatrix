@testable import AreaMatrix

actor StaticExistingRepositoryMetadataReader: ExistingRepositoryMetadataReading {
    private let result: Result<ExistingRepositoryMetadataSnapshot, Error>
    private var paths: [String] = []

    init(schemaVersion: Int64, lastOpenedAt: Int64? = nil, configuredRepoPath: String? = nil) {
        result = .success(.testFixture(
            schemaVersion: schemaVersion,
            lastOpenedAt: lastOpenedAt,
            configuredRepoPath: configuredRepoPath
        ))
    }

    init(result: Result<ExistingRepositoryMetadataSnapshot, Error>) {
        self.result = result
    }

    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot {
        paths.append(repoPath)
        return try result.get()
    }

    func requestedPaths() -> [String] {
        paths
    }
}
