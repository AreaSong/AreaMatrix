import AreaMatrixFeatureSettings
import Foundation

struct FileSystemRepoMetadataPresenceChecker: RepoMetadataPresenceChecking {
    func metadataPresence(repoPath: String) -> RepoMetadataPresence {
        let metadataURL = RepositoryMetadataPath.metadataURL(repoPath: repoPath)
        let databaseURL = metadataURL.appendingPathComponent("index.db", isDirectory: false)

        return RepoMetadataPresence(
            hasMetadataDirectory: FileManager.default.fileExists(atPath: metadataURL.path),
            hasMetadataDatabase: FileManager.default.fileExists(atPath: databaseURL.path)
        )
    }
}

enum RepositoryMetadataPath {
    static func metadataURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
    }
}
