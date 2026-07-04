@testable import AreaMatrix
import Foundation

@MainActor
func classifierSettingsRecoveryModel(
    repoURL: URL,
    predictor: any CoreCategoryPredicting,
    editor: any CoreClassifierRuleEditing = ClassifierSettingsRecordingRuleEditor()
) async -> ClassifierSettingsModel {
    let model = ClassifierSettingsModel(
        repoPath: repoURL.path,
        loader: StaticConfigurationLoader(config: .classifierRecoveryFixture(repoPath: repoURL.path)),
        updater: NoopConfigurationUpdater(),
        predictor: predictor,
        ruleEditor: editor,
        errorMapper: ClassifierSettingsRecoveryErrorMapper(),
        accessibilityAnnouncer: NoopAccessibilityAnnouncer()
    )
    await model.load()
    return model
}

actor ClassifierSettingsRecoveryErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case let .Config(reason):
            .classifierRecoveryMapping(kind: .config, userMessage: "分类规则无效：\(reason)")
        default:
            .classifierRecoveryMapping(kind: .internal, userMessage: "分类规则校验失败")
        }
    }
}

extension RecordingCoreErrorMapper {
    static func classifierSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            switch error {
            case .Db:
                .classifierSettingsMapping(kind: .db, userMessage: "数据库错误")
            case let .Config(reason):
                .classifierSettingsMapping(kind: .config, userMessage: "分类规则无效：\(reason)")
            case let .Classify(reason):
                .classifierSettingsMapping(kind: .classify, userMessage: "无法预览分类：\(reason)")
            case .PermissionDenied:
                .classifierSettingsMapping(kind: .permissionDenied, userMessage: "无访问权限")
            default:
                .classifierSettingsMapping(kind: .internal, userMessage: "保存失败")
            }
        }
    }
}
