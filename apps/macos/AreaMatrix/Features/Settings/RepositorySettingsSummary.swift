import Foundation

struct RepositorySettingsLoadError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct RepositorySettingsSyncError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct RepositorySettingsOverviewActionError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
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
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct RepositorySettingsSummary: Equatable {
    static let generatedOverviewRelativePath = ".areamatrix/generated/root.md"

    var repositoryName: String
    var location: String
    private var metadataPresence: RepoMetadataPresence
    private var coreVersionValue: String?
    private var overviewOutput: String

    var metadataStatus: String {
        metadataPresence.directoryStatusLabel
    }

    var locationType: String {
        Self.locationType(for: location)
    }

    var coreVersion: String {
        coreVersionValue ?? L10n.string("Unknown")
    }

    var overviewMode: String {
        Self.overviewModeLabel(for: overviewOutput)
    }

    var generatedPath: String {
        Self.generatedOverviewRelativePath
    }

    var rootFile: String {
        overviewOutput == "RootAreaMatrixFile" ? "AREAMATRIX.md" : L10n.string("Off")
    }

    var readmePolicy: String {
        L10n.string("User file, never managed by AreaMatrix")
    }

    init(
        config: AppRepoConfigSnapshot,
        fallbackRepoPath: String,
        coreVersion: String?,
        metadataPresence: RepoMetadataPresence
    ) {
        let resolvedPath = config.repoPath.isEmpty || config.repoPath != fallbackRepoPath
            ? fallbackRepoPath
            : config.repoPath
        repositoryName = Self.repositoryName(for: resolvedPath)
        location = resolvedPath
        self.metadataPresence = metadataPresence
        coreVersionValue = coreVersion
        overviewOutput = config.overviewOutput
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

extension AppRepoConfigSnapshot {
    func withRepositoryPath(_ value: String) -> AppRepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }
}
