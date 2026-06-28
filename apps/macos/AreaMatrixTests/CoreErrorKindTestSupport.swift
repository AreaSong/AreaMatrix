@testable import AreaMatrix

enum CoreErrorKindTestMapper {
    static func kind(for error: CoreError) -> CoreErrorKindSnapshot {
        storageKind(for: error) ?? repositoryKind(for: error) ?? actionKind(for: error) ?? .internal
    }

    private static func storageKind(for error: CoreError) -> CoreErrorKindSnapshot? {
        switch error {
        case .Io:
            .io
        case .Db:
            .db
        case .Conflict:
            .conflict
        case .DuplicateFile:
            .duplicateFile
        case .FileNotFound:
            .fileNotFound
        default:
            nil
        }
    }

    private static func repositoryKind(for error: CoreError) -> CoreErrorKindSnapshot? {
        switch error {
        case .Config:
            .config
        case .Validation:
            .validation
        case .Classify:
            .classify
        case .RepoNotInitialized:
            .repoNotInitialized
        case .InvalidPath:
            .invalidPath
        case .PermissionDenied:
            .permissionDenied
        default:
            nil
        }
    }

    private static func actionKind(for error: CoreError) -> CoreErrorKindSnapshot? {
        switch error {
        case .ExpiredAction:
            .expiredAction
        case .ICloudPlaceholder:
            .iCloudPlaceholder
        case .StagingRecoveryRequired:
            .stagingRecoveryRequired
        default:
            nil
        }
    }
}
