import Foundation

struct FileSystemRepoMetadataPresenceChecker: RepoMetadataPresenceChecking {
    func metadataPresence(repoPath: String) -> RepoMetadataPresence {
        let metadataURL = URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
        let databaseURL = metadataURL.appendingPathComponent("index.db", isDirectory: false)

        return RepoMetadataPresence(
            hasMetadataDirectory: FileManager.default.fileExists(atPath: metadataURL.path),
            hasMetadataDatabase: FileManager.default.fileExists(atPath: databaseURL.path)
        )
    }
}
