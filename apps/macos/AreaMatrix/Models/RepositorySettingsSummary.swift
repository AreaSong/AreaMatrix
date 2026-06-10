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
            "OK"
        case .locked:
            "Locked"
        case .needsRecovery:
            "Needs recovery"
        }
    }
}

enum RepositorySettingsWatcherStatus: Equatable {
    case running
    case paused

    var label: String {
        switch self {
        case .running:
            "Running"
        case .paused:
            "Paused"
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

    init(config: RepoConfigSnapshot, fallbackRepoPath: String, coreVersion: String) {
        let resolvedPath = config.repoPath.isEmpty || config.repoPath != fallbackRepoPath
            ? fallbackRepoPath
            : config.repoPath
        repositoryName = Self.repositoryName(for: resolvedPath)
        location = resolvedPath
        metadataStatus = Self.metadataStatus(for: resolvedPath)
        locationType = Self.locationType(for: resolvedPath)
        self.coreVersion = coreVersion
        overviewMode = Self.overviewModeLabel(for: config.overviewOutput)
        generatedPath = Self.generatedOverviewRelativePath
        rootFile = config.overviewOutput == "RootAreaMatrixFile" ? "AREAMATRIX.md" : "Off"
        readmePolicy = "User file, never managed by AreaMatrix"
    }

    private static func repositoryName(for path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "AreaMatrix" : name
    }

    private static func metadataStatus(for path: String) -> String {
        let metadataURL = URL(fileURLWithPath: path, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
        return FileManager.default.fileExists(atPath: metadataURL.path)
            ? ".areamatrix/ found"
            : ".areamatrix/ missing"
    }

    private static func locationType(for path: String) -> String {
        let normalizedPath = path.lowercased()
        if normalizedPath.contains("mobile documents") || normalizedPath.contains("icloud") {
            return "iCloud Drive"
        }
        if normalizedPath.contains("onedrive") {
            return "OneDrive"
        }
        if normalizedPath.hasPrefix("smb://") || normalizedPath.hasPrefix("/volumes/") {
            return "Network mount"
        }
        return path.isEmpty ? "Unknown" : "Local folder"
    }

    private static func overviewModeLabel(for value: String) -> String {
        value == "RootAreaMatrixFile" ? "Root AREAMATRIX.md enabled" : "Generated only"
    }
}

extension RepoConfigSnapshot {
    func withRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }
}
