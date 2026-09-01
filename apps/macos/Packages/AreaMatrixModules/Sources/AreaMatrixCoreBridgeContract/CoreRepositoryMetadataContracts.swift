public protocol ExistingRepositoryMetadataReading: Sendable {
    func metadata(repoPath: String) async throws -> ExistingRepositoryMetadataSnapshot
}

public struct ExistingRepositoryMetadataSnapshot: Equatable, Sendable {
    public var schemaVersion: Int64
    public var lastOpenedAt: Int64?
    public var configuredRepoPath: String?

    public init(
        schemaVersion: Int64,
        lastOpenedAt: Int64?,
        configuredRepoPath: String?
    ) {
        self.schemaVersion = schemaVersion
        self.lastOpenedAt = lastOpenedAt
        self.configuredRepoPath = configuredRepoPath
    }
}
