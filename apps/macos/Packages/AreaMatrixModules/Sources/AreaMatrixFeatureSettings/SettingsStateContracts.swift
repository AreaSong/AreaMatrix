import Foundation

public enum ClassifierSettingsPaths {
    public static let classifierRelativePath = ".areamatrix/classifier.yaml"
    public static let validationProbeFilename = "AreaMatrixValidationProbe.txt"

    public static func classifierConfigURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("classifier.yaml", isDirectory: false)
    }
}

public struct RepoMetadataPresence: Equatable, Sendable {
    public var hasMetadataDirectory: Bool
    public var hasMetadataDatabase: Bool

    public init(hasMetadataDirectory: Bool, hasMetadataDatabase: Bool) {
        self.hasMetadataDirectory = hasMetadataDirectory
        self.hasMetadataDatabase = hasMetadataDatabase
    }
}

public enum RepositorySettingsDatabaseStatus: Equatable, Sendable {
    case ok
    case locked
    case needsRecovery
}

public enum RepositorySettingsWatcherStatus: Equatable, Sendable {
    case running
    case paused
}

public enum ValidationPhaseState<Failure: Equatable>: Equatable {
    case idle
    case validating
    case passed
    case failed(Failure)
}
