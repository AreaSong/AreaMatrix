import Foundation

protocol CoreEmptyRepositoryOpening: Sendable {
    func openEmptyRepository(repoPath: String) async throws -> RepoConfigSnapshot
    func openAdoptedRepository(repoPath: String) async throws -> RepoConfigSnapshot
}

extension CoreBridge: CoreEmptyRepositoryOpening {
    func openEmptyRepository(repoPath: String) async throws -> RepoConfigSnapshot {
        try await openInitializedRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepoConfigSnapshot {
        try await openInitializedRepository(repoPath: repoPath)
    }

    private func openInitializedRepository(repoPath: String) async throws -> RepoConfigSnapshot {
        let config = RepoConfigSnapshot(coreConfig: try loadOpeningCoreConfig(repoPath: repoPath))
        _ = try listOpeningCoreTreeJSON(repoPath: repoPath, locale: config.locale)
        return config
    }
}

private func loadOpeningCoreConfig(repoPath: String) throws -> RepoConfig {
    try loadConfig(repoPath: repoPath)
}

private func listOpeningCoreTreeJSON(repoPath: String, locale: String) throws -> String {
    try listTreeJson(repoPath: repoPath, locale: locale)
}
