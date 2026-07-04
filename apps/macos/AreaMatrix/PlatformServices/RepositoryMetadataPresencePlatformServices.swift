import Foundation

enum RepositorySettingsPlatformServices {
    static var appVersionReader: any AppVersionReading {
        BundleAppVersionReader()
    }

    static var metadataReader: any ExistingRepositoryMetadataReading {
        SQLiteExistingRepositoryMetadataReader()
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
        VoiceOverAccessibilityAnnouncer()
    }
}

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
