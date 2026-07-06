@testable import AreaMatrix

extension RecordingCoreErrorMapper {
    static func repositorySettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            let userMessage: String
            let kind: CoreErrorKindSnapshot
            switch error {
            case .Db:
                kind = .db
                userMessage = "数据库错误"
            case .PermissionDenied:
                kind = .permissionDenied
                userMessage = "权限错误"
            default:
                kind = .config
                userMessage = "配置错误"
            }

            return CoreErrorMappingSnapshot.testFixture(
                kind: kind,
                userMessage: userMessage,
                severity: .medium,
                suggestedAction: "Retry status",
                recoverability: .retryable,
                rawContext: "repository-settings repository-settings-core"
            )
        }
    }
}
