import AreaMatrixFeatureSettings
import Foundation

protocol RepoMetadataPresenceChecking {
    func metadataPresence(repoPath: String) -> RepoMetadataPresence
}

extension RepoMetadataPresence {
    var directoryStatusLabel: String {
        hasMetadataDirectory
            ? L10n.string("settings.repository.metadataFound")
            : L10n.string("settings.repository.metadataMissing")
    }
}
