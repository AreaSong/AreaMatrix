import Foundation

protocol RepoMetadataPresenceChecking {
    func metadataPresence(repoPath: String) -> RepoMetadataPresence
}

struct RepoMetadataPresence: Equatable {
    var hasMetadataDirectory: Bool
    var hasMetadataDatabase: Bool

    var directoryStatusLabel: String {
        hasMetadataDirectory ? ".areamatrix/ found" : ".areamatrix/ missing"
    }
}
