import Foundation

enum RepositorySettingsPlatformServices {
    static var appVersionReader: any AppVersionReading {
        AppPlatformServices.appVersionReader
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        AppPlatformServices.existingRepositoryMetadataReader
    }

    static var metadataPresenceChecker: any RepoMetadataPresenceChecking {
        FileSystemRepoMetadataPresenceChecker()
    }

    static var finderOpener: any RepositoryFinderOpening {
        AppPlatformServices.finderOpener
    }

    static var pathCopier: any RepositoryPathCopying {
        AppPlatformServices.pathCopier
    }

    static var generatedOverviewRevealer: any RepositoryFileRevealing {
        AppPlatformServices.fileRevealer
    }

    static var accessibilityAnnouncer: any AccessibilityAnnouncing {
        AppPlatformServices.accessibilityAnnouncer
    }
}

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
