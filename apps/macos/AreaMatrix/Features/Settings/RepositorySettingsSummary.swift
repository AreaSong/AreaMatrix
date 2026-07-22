import Foundation

struct RepositorySettingsLoadError: Equatable {
    var message: String
    var recovery: String
}

struct RepositorySettingsSyncError: Equatable {
    var message: String
    var recovery: String
}

struct RepositorySettingsOverviewActionError: Equatable {
    var message: String
    var recovery: String
}

protocol CoreVersionLoading: Sendable {
    func coreVersion() async throws -> String
}

enum RepositorySettingsDatabaseStatus: Equatable {
    case ok
    case locked
    case needsRecovery

    var label: String {
        switch self {
        case .ok:
            L10n.string("OK")
        case .locked:
            L10n.string("Locked")
        case .needsRecovery:
            L10n.string("Needs recovery")
        }
    }
}

enum RepositorySettingsWatcherStatus: Equatable {
    case running
    case paused

    var label: String {
        switch self {
        case .running:
            L10n.string("Running")
        case .paused:
            L10n.string("Paused")
        }
    }
}

struct RepositorySettingsHealthSummary: Equatable {
    var databaseStatus: RepositorySettingsDatabaseStatus
    var schemaVersion: Int64?
    var filesIndexed: Int64?
    var lastOpenedAt: Int64?
    var lastScanAt: Int64?
    var watcherStatus: RepositorySettingsWatcherStatus
}

struct RepositorySettingsHealthError: Equatable {
    var databaseStatus: RepositorySettingsDatabaseStatus
    var message: String
    var recovery: String
}

struct RepositorySettingsSummary: Equatable {
    static let generatedOverviewRelativePath = ".areamatrix/generated/root.md"

    var repositoryName: String
    var location: String
    var metadataStatus: String
    var locationType: String
    var coreVersion: String
    var overviewMode: String
    var generatedPath: String
    var rootFile: String
    var readmePolicy: String

    init(
        config: RepoConfigSnapshot,
        fallbackRepoPath: String,
        coreVersion: String,
        metadataPresence: RepoMetadataPresence
    ) {
        let resolvedPath = config.repoPath.isEmpty || config.repoPath != fallbackRepoPath
            ? fallbackRepoPath
            : config.repoPath
        repositoryName = Self.repositoryName(for: resolvedPath)
        location = resolvedPath
        metadataStatus = metadataPresence.directoryStatusLabel
        locationType = Self.locationType(for: resolvedPath)
        self.coreVersion = coreVersion
        overviewMode = Self.overviewModeLabel(for: config.overviewOutput)
        generatedPath = Self.generatedOverviewRelativePath
        rootFile = config.overviewOutput == "RootAreaMatrixFile" ? "AREAMATRIX.md" : L10n.string("Off")
        readmePolicy = L10n.string("User file, never managed by AreaMatrix")
    }

    private static func repositoryName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "AreaMatrix" : name
    }

    private static func locationType(for path: String) -> String {
        let normalizedPath = path.lowercased()
        if normalizedPath.contains("mobile documents") || normalizedPath.contains("icloud") {
            return L10n.string("iCloud Drive")
        }
        if normalizedPath.contains("onedrive") {
            return L10n.string("OneDrive")
        }
        if normalizedPath.hasPrefix("smb://") || normalizedPath.hasPrefix("/volumes/") {
            return L10n.string("Network mount")
        }
        return path.isEmpty ? L10n.string("Unknown") : L10n.string("Local folder")
    }

    private static func overviewModeLabel(for value: String) -> String {
        value == "RootAreaMatrixFile"
            ? L10n.string("Root AREAMATRIX.md enabled")
            : L10n.string("Generated only")
    }
}

extension RepoConfigSnapshot {
    func withRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }
}
