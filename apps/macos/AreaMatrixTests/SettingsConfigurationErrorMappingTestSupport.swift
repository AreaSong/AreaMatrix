@testable import AreaMatrix

extension RecordingCoreErrorMapper {
    static func generalSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            switch error {
            case .Db:
                .generalSettingsMapping(kind: .db, userMessage: "数据库错误")
            case .Config:
                .generalSettingsMapping(kind: .config, userMessage: "配置错误")
            case .PermissionDenied:
                .generalSettingsMapping(kind: .permissionDenied, userMessage: "无访问权限")
            default:
                .generalSettingsMapping(kind: .internal, userMessage: "保存失败")
            }
        }
    }

    static func advancedSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            switch error {
            case .Db:
                .advancedSettingsMapping(kind: .db, userMessage: "Database error")
            case .Config:
                .advancedSettingsMapping(kind: .config, userMessage: "Configuration error")
            case .PermissionDenied:
                .advancedSettingsMapping(kind: .permissionDenied, userMessage: "Permission denied")
            default:
                .advancedSettingsMapping(kind: .internal, userMessage: "Save failed")
            }
        }
    }

    static func integrationsSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            switch error {
            case .Db:
                .integrationsSettingsMapping(kind: .db, userMessage: "数据库错误")
            case .PermissionDenied:
                .integrationsSettingsMapping(kind: .permissionDenied, userMessage: "权限错误")
            default:
                .integrationsSettingsMapping(kind: .config, userMessage: "配置错误")
            }
        }
    }
}

private extension CoreErrorMappingSnapshot {
    static func generalSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: kind.rawValue
        )
    }

    static func advancedSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry save",
            recoverability: .retryable,
            rawContext: kind.rawValue
        )
    }

    static func integrationsSettingsMapping(
        kind: CoreErrorKindSnapshot,
        userMessage: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: kind == .db ? "Retry save" : "Retry status",
            recoverability: .retryable,
            rawContext: "integrations-settings repository-config"
        )
    }
}
