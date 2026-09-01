import AreaMatrixFeatureIngestion

extension RepositoryOpeningResult {
    @MainActor
    func makeRepositorySession() -> RepositorySession {
        RepositorySession(
            repoPath: config.repoPath,
            revision: config.revision,
            access: RepositoryAccessSnapshot(
                isReadOnly: isReadOnly,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }

    @MainActor
    func refresh(_ session: RepositorySession) throws {
        try session.refresh(
            repoPath: config.repoPath,
            revision: config.revision,
            access: RepositoryAccessSnapshot(
                isReadOnly: isReadOnly,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }
}
