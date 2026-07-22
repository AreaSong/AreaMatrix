import Foundation

protocol RepoMetadataPresenceChecking {
    func metadataPresence(repoPath: String) -> RepoMetadataPresence
}

struct RepoMetadataPresence: Equatable {
    var hasMetadataDirectory: Bool
    var hasMetadataDatabase: Bool

    var directoryStatusLabel: String {
        hasMetadataDirectory
            ? L10n.string("settings.repository.metadataFound")
            : L10n.string("settings.repository.metadataMissing")
    }
}
