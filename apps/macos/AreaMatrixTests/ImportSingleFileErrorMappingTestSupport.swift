@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func importSingleFileError(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        makeImportSingleFileError(
            kind: kind,
            suggestedAction: "Resolve the conflict and retry.",
            rawContext: "import-single import-single-sheet"
        )
    }

    static func importCopyFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        makeImportSingleFileError(
            kind: kind,
            suggestedAction: "Choose a different file or resolve the conflict.",
            rawContext: "copy import"
        )
    }

    static func importMoveFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: kind == .permissionDenied ? "无访问权限" : "导入失败",
            severity: .high,
            suggestedAction: "Choose a different file or resolve the conflict.",
            recoverability: .userActionRequired,
            rawContext: "move import"
        )
    }

    static func importIndexFixture(kind: CoreErrorKindSnapshot) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: kind == .iCloudPlaceholder ? "iCloud 文件尚未下载" : "导入失败",
            severity: .high,
            suggestedAction: "Choose a different file or resolve the conflict.",
            recoverability: .userActionRequired,
            rawContext: "index import"
        )
    }

    private static func makeImportSingleFileError(
        kind: CoreErrorKindSnapshot,
        suggestedAction: String,
        rawContext: String
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: importErrorMessage(for: kind),
            severity: .high,
            suggestedAction: suggestedAction,
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func importErrorMessage(for kind: CoreErrorKindSnapshot) -> String {
        switch kind {
        case .duplicateFile:
            "检测到重复文件"
        case .invalidPath:
            "路径无效"
        case .permissionDenied:
            "无访问权限"
        case .iCloudPlaceholder:
            "iCloud 文件尚未下载"
        case .io:
            "文件读写失败"
        case .db:
            "数据库错误"
        case .fileNotFound:
            "文件不存在"
        case .expiredAction:
            "操作已过期"
        case .config:
            "配置不可用"
        case .validation:
            "输入校验失败"
        case .classify:
            "分类失败"
        case .conflict:
            "命名冲突未解决"
        case .repoNotInitialized:
            "资料库尚未初始化"
        case .stagingRecoveryRequired:
            "需要先恢复未完成导入"
        case .internal:
            "内部错误"
        }
    }
}

extension RecordingCoreErrorMapper {
    static func importSingleFile() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importSingleFileError(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }

    static func importCopy() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importCopyFixture(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }

    static func importMove() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importMoveFixture(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }

    static func importIndex() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.importIndexFixture(
                kind: CoreErrorKindTestMapper.kind(for: error)
            )
        }
    }
}
